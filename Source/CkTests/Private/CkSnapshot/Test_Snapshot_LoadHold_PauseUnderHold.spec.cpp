// GW-33 — a world paused while a load holds it is REPORTED, once, by the loader.
//
// A paused world does not tick, and every phase of a load is driven by world ticks: the teardown cascade, the
// rebuild's kernel passes, the payload drain, the convergence pump. So a pause taken mid-load does not pause
// the load, it stops it — and if it outlives a phase's frame cap the load escapes there and reports
// Succeeded_WithLoss for facts that were never given a frame in which to converge.
//
// The framework does not REFUSE the pause. Pausing is a game-side decision taken by a game-side menu, and a
// subsystem is the wrong place to veto it; the sanctioned guard is the pause UI declining while
// Get_IsLoadInProgress. What the loader owes is that the resulting cap-escape is explained rather than
// mysterious, so it says so exactly once per load, naming the world and the epoch.
//
// The test pauses only INSIDE the load, and unpauses the moment the observation lands — driven from the core
// FTSTicker, which is what makes this observable at all: the loader's own tick is on that ticker and keeps
// running while the world it is loading does not.
//
// RED before this change: the loader had no opinion about a paused world; a pause during a load produced a
// budget burned in silence and a lossy report with no line in the log connecting the two.
// Surface in Session Frontend: Ck.Snapshot.LoadHold.PauseUnderHoldIsReported

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Macros/CkMacros.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_LoadHold.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

#include "Containers/Ticker.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h" // net.AllowPIESeamlessTravel
#include "Kismet/GameplayStatics.h"
#include "StructUtils/InstancedStruct.h"

namespace ck_test_loadhold_pause
{
    const auto Pause_SlotName = FName{TEXT("CkSnapshot_LoadHoldPause_GateSlot")};

    // What the pause driver below records, read by the assertions afterwards. Shared rather than captured by
    // reference: the ticker outlives the lambda that armed it.
    struct FPauseRun
    {
        bool PauseTook = false;             // UWorld::IsPaused() actually reported true
        bool ObservationLanded = false;     // the loader said it saw the pause, before we let go of it
        bool ReleasedByDeadline = false;    // ...or it never did, and the safety net unpaused instead
    };

    // Long enough that a healthy observation (the loader's very next ticker callback) always wins, short enough
    // that a broken one fails as itself rather than as the harness's 60 s reload timeout.
    constexpr auto PauseCeilingSeconds = 10.0;

    // Pauses the world the instant a load latches, and lets go the instant the loader says it noticed. Driven
    // from the CORE ticker on purpose: FTSTicker is wall-clocked and pause-blind, which is exactly why the
    // loader's own tick can observe a world nothing else is ticking.
    auto Arm_PauseDriver(UWorld* InServer, TSharedRef<FPauseRun> InRun) -> void
    {
        auto WeakWorld = TWeakObjectPtr<UWorld>{InServer};
        auto WeakSubsystem = TWeakObjectPtr<UCk_Snapshot_Subsystem_UE>{
            ck::auto_test::snapshot::Get_SnapshotSubsystem(InServer)};

        auto ArmedAtSeconds = FPlatformTime::Seconds();
        auto Paused = MakeShared<bool>(false);

        FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda(
        [WeakWorld, WeakSubsystem, InRun, Paused, ArmedAtSeconds](float) -> bool
        {
            auto* World = WeakWorld.Get();
            auto* Subsystem = WeakSubsystem.Get();

            if (World == nullptr || Subsystem == nullptr)
            { return false; }

            const auto Release = [&]() -> void
            {
                UGameplayStatics::SetGamePaused(World, false);
            };

            if (FPlatformTime::Seconds() - ArmedAtSeconds > PauseCeilingSeconds)
            {
                InRun->ReleasedByDeadline = *Paused;
                Release();
                return false;
            }

            if (NOT *Paused)
            {
                if (NOT Subsystem->Get_IsLoadInProgress())
                { return true; }

                UGameplayStatics::SetGamePaused(World, true);
                *Paused = true;
                InRun->PauseTook = World->IsPaused();
                return true;
            }

            if (NOT Subsystem->TestOnly_Get_PauseObservedUnderHold())
            { return true; }

            InRun->ObservationLanded = true;
            Release();
            return false;
        }));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_PauseUnderHoldIsReported,
    "Ck.Snapshot.LoadHold.PauseUnderHoldIsReported",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_PauseUnderHoldIsReported::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_pause;

    auto Run = MakeShared<FPauseRun>();

    // EXACTLY once, and that is the contract rather than an incidental count: the loader ticks every frame for
    // the whole load, so an ungated observation would print one line per frame and bury the load's own
    // diagnostics under its own noise.
    constexpr auto ExactlyOnce = 1;
    AddExpectedMessage(
        TEXT("is PAUSED while a load holds it"),
        ELogVerbosity::Warning,
        EAutomationExpectedMessageFlags::Contains,
        ExactlyOnce);

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = Pause_SlotName;

    // ONE world, ONE cycle: the subject is the loading machine's own reaction, and a second cycle would expect a
    // second Warning from a load this test does not pause.
    Spec.NumPIEClients = 1;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto Elapsed = 0.0;
        return ck_autotest_snapshot_loadhold::TryGet_ProbeTimerElapsedSeconds(
            ck::auto_test::snapshot::Get_PostTravelServerWorld(), Elapsed);
    });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([Run](UWorld* InServer) -> void
    {
        Arm_PauseDriver(InServer, Run);
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, Run]() -> bool
    {
        // The positive controls come first: the Warning assertion above is only meaningful if a pause was
        // really taken while the load really owned the world.
        auto AllGood = TestTrue(
            TEXT("the world really was paused mid-load — an unpausable world would make the Warning assertion "
                 "below a statement about nothing"),
            Run->PauseTook);

        AllGood &= TestTrue(
            TEXT("the loader observed the pause and said so, and the test held the pause until it did — so the "
                 "expected Warning is this load's, not a race the harness happened to win"),
            Run->ObservationLanded);

        AllGood &= TestFalse(
            TEXT("...and the pause was released by that observation, not by the test's safety deadline"),
            Run->ReleasedByDeadline);

        // The load still finished. Reporting a pause is a diagnostic, never a refusal — a loader that gave up
        // on a paused world would strand the player behind a loading screen for the rest of the session.
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        auto* Subsystem = ck::auto_test::snapshot::Get_SnapshotSubsystem(Server);
        if (NOT TestTrue(TEXT("snapshot subsystem present post-reload"), Subsystem != nullptr))
        { return false; }

        AllGood &= TestTrue(
            TEXT("the load reached ready-to-resume anyway — the pause is reported, not obeyed"),
            Subsystem->Get_IsReadyToResume());

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
