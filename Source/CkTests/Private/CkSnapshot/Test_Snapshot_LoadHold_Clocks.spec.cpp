// T-C6-1c / T-C6-3 / T-C6-13 — the three clock statements a load makes, each measured at the one instant it can
// be measured: the Promise_OnLoadComplete edge, which is where the world resumes.
//
//   1c  no game delta accumulates: a non-kernel processor keeps TICKING through the hold and is handed ~0 seconds.
//   3   a restored Running timer does not advance between the moment its value is final and the moment the world
//       is handed back.
//   13  in the post-travel world, wall time ran and game time did not — and the dilation dial is back where it was.
//
// TOLERANCE, derived rather than picked (G2-D4 N-M1). The freeze is global time dilation held at
// MinGlobalTimeDilation = 0.0001 (Engine/Config/BaseGame.ini; BB overrides neither bound), and UE clamps the
// undilated frame at BB's MaxUndilatedFrameTime = 0.0667 (Config/DefaultEngine.ini:306). So one frame can accrue
// at most 0.0667 * 0.0001 = 6.67e-6 s of game time, and the loader's own frame budget across every phase is
// ~2580 frames (600 teardown + 600 travel + 600 rebuild + 600 hydrate + 180 convergence). Worst case therefore
// 2580 * 6.67e-6 = 1.72e-2 s. "Frozen" means at most ~17 ms across a whole load, never exactly zero, so every
// threshold below is an epsilon at 20 ms and never an equality.
//
// WHY THE SAMPLING IS NOT WHERE THE MEMO PUT IT. The memo's T-C6-13 samples GetTimeSeconds/GetRealTimeSeconds
// either side of the load. Both are UWorld members and both restart at 0 in the post-travel world (the memo's own
// N-M4 records the clock-zero fact), so a delta across the travel measures the travel, not the hold — and an
// absolute deadline armed pre-save is trivially un-expired against a restarted clock, in every build. The
// statement is therefore made WITHIN the world it is about: between that world's BeginPlay and Ready_ToResume,
// its wall clock ran and its game clock did not.
//
// RED before C6: the post-travel world simulated at real time from its first tick through the whole rebuild,
// drain and settle, so its game clock and its wall clock advanced together (13); the accumulator was handed real
// frame deltas throughout (1c); and FProcessor_Timer_Update advanced the restored timer for the settle (3).
// Surface in Session Frontend: Ck.Snapshot.LoadHold.NoGameDeltaAccumulatesAcrossLoad
//                              Ck.Snapshot.LoadHold.NoTimerAdvanceDuringHold
//                              Ck.Snapshot.LoadHold.GameTimeFrozenWallTimeRuns

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "GameFramework/WorldSettings.h"
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Misc/ScopeExit.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Signal/CkSignal_Macros.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Signals.h"

#include "CkTests/Net/CkNetAutomation_Common.h"
#include "CkTests/Snapshot/CkAutoTest_Snapshot_LoadHold.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace ck_test_loadhold_clocks
{
    const auto NoGameDelta_SlotName = FName{TEXT("CkSnapshot_LoadHoldNoGameDelta_GateSlot")};
    const auto TimerHold_SlotName   = FName{TEXT("CkSnapshot_LoadHoldTimerHold_GateSlot")};
    const auto FrozenClock_SlotName = FName{TEXT("CkSnapshot_LoadHoldFrozenClock_GateSlot")};

    // 0.0667 (MaxUndilatedFrameTime) * 0.0001 (MinGlobalTimeDilation) * 2580 (the loader's whole frame budget)
    // = 1.72e-2 s. Rounded UP to 20 ms so the bound is stated rather than shaved.
    constexpr auto FrozenGameSecondsTolerance = 0.02;

    // Wall time genuinely elapsing during a load is not a millisecond affair — a travel, a package load and a
    // rebuild are involved. Set well above the tolerance above so the two assertions cannot both be satisfied by
    // measurement noise.
    constexpr auto MinimumWallSecondsDuringLoad = 0.10;

    auto Make_RootedWitness() -> UCk_AutoTest_Snapshot_LoadHoldWitness_UE*
    {
        auto* Witness = NewObject<UCk_AutoTest_Snapshot_LoadHoldWitness_UE>();
        Witness->AddToRoot();
        return Witness;
    }

    // OnPreLoad fires from inside Request_Load, after the load latches and before the teardown — the one moment a
    // pre-travel arm is both possible and meaningful, and the moment the fixture takes its pre-load reading.
    auto Arm_Witness(UWorld* InWorld, UCk_AutoTest_Snapshot_LoadHoldWitness_UE* InWitness) -> void
    {
        if (InWorld == nullptr || InWitness == nullptr)
        { return; }

        auto Source = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InWorld);
        if (ck::Is_NOT_Valid(Source))
        { return; }

        auto Delegate = FCk_Delegate_Snapshot_OnPreLoad{};
        Delegate.BindUFunction(InWitness, TEXT("OnPreLoad"));
        CK_SIGNAL_BIND(ck::UUtils_Signal_Snapshot_OnPreLoad, Source, Delegate,
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);
    }

    auto Spawn_ClockProbe(UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto Transient = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(InServer);
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            Transient, UCk_AutoTest_Snapshot_LoadHoldProbe_EntityScript_UE::StaticClass(), FInstancedStruct{}, {});
    }

    auto ProbeReady() -> bool
    {
        auto Elapsed = 0.0;
        return ck_autotest_snapshot_loadhold::TryGet_ProbeTimerElapsedSeconds(
            ck::auto_test::snapshot::Get_PostTravelServerWorld(), Elapsed);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_NoGameDeltaAccumulatesAcrossLoad,
    "Ck.Snapshot.LoadHold.NoGameDeltaAccumulatesAcrossLoad",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_NoGameDeltaAccumulatesAcrossLoad::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_clocks;

    auto* Witness = Make_RootedWitness();

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = NoGameDelta_SlotName;

    // ONE world: the accumulator is registry-scoped, and a listen-server pair would have the client's own world
    // recording its own numbers into a second registry the assertions never look at.
    Spec.NumPIEClients = 1;

    // ONE cycle. The witness takes a single reading at the promise edge; a second cycle would re-run Assert
    // against the first cycle's reading, which is a stability claim the two-cycle rule cannot make about a clock.
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([Witness](UWorld* InServer) -> void
    {
        Spawn_ClockProbe(InServer);
        Arm_Witness(InServer, Witness);
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool { return ProbeReady(); });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* /*InServer*/) -> void
    {
        // Zeroed immediately before the save so the readings describe THIS load.
        ck_autotest_snapshot_loadhold::Reset_Observations();
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, Witness]() -> bool
    {
        ON_SCOPE_EXIT { Witness->RemoveFromRoot(); };

        const auto& Observations = ck_autotest_snapshot_loadhold::Get_Observations();

        auto AllGood = TestEqual(TEXT("the promise fired exactly once, so there is a reading to assert on"),
            Observations.FireCount, 1);

        if (Observations.FireCount == 0)
        { return false; }

        const auto& AtFire = Observations.AtLoadComplete;

        // The positive control comes FIRST: an accumulated delta of zero only means anything if the processor
        // that would have accumulated it actually ran. A count of zero here is the vacuous-pass shape.
        AllGood &= TestTrue(
            FString::Printf(TEXT("the non-kernel accumulator TICKED during the load (ticks=%d) — a zero delta on a "
                                 "processor that never ran proves nothing"), AtFire.AccumTickCount),
            AtFire.AccumTickCount > 0);

        AllGood &= TestTrue(
            FString::Printf(TEXT("...and every one of those ticks was handed ~zero game time (accumulated %.6fs, "
                                 "bound %.4fs)"), AtFire.AccumulatedSeconds, FrozenGameSecondsTolerance),
            FMath::Abs(AtFire.AccumulatedSeconds) <= FrozenGameSecondsTolerance);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_NoTimerAdvanceDuringHold,
    "Ck.Snapshot.LoadHold.NoTimerAdvanceDuringHold",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_NoTimerAdvanceDuringHold::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_clocks;

    auto* Witness = Make_RootedWitness();

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = TimerHold_SlotName;
    Spec.NumPIEClients = 1;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([Witness](UWorld* InServer) -> void
    {
        Spawn_ClockProbe(InServer);
        Arm_Witness(InServer, Witness);
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool { return ProbeReady(); });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* /*InServer*/) -> void
    {
        ck_autotest_snapshot_loadhold::Reset_Observations();
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, Witness]() -> bool
    {
        ON_SCOPE_EXIT { Witness->RemoveFromRoot(); };

        const auto& Observations = ck_autotest_snapshot_loadhold::Get_Observations();

        // Two positive controls, because the whole assertion is a subtraction: both ends of it have to be real
        // readings taken from a timer that was really there.
        auto AllGood = TestEqual(TEXT("the probe's Promise_OnHydrated fired exactly once — the restored value is final"),
            Observations.OnHydratedFireCount, 1);

        AllGood &= TestEqual(TEXT("the promise fired exactly once"), Observations.FireCount, 1);

        AllGood &= TestTrue(TEXT("the restored timer resolved at the hydration edge"),
            Observations.AtHydrated.TimerResolved);
        AllGood &= TestTrue(TEXT("...and still resolved at the ready-to-resume edge"),
            Observations.AtLoadComplete.TimerResolved);

        if (NOT Observations.AtHydrated.TimerResolved || NOT Observations.AtLoadComplete.TimerResolved)
        { return false; }

        // The window between "this timer's value is final" and "the world is yours again" is precisely the part
        // of the hold a restored feature is alive through. A Running timer that ticks there comes back to the
        // player already ahead of the state it was saved in.
        const auto AdvancedSeconds =
            Observations.AtLoadComplete.TimerElapsedSeconds - Observations.AtHydrated.TimerElapsedSeconds;

        AllGood &= TestTrue(
            FString::Printf(TEXT("a Running restored timer does not advance between hydration and ready-to-resume "
                                 "(advanced %.6fs, bound %.4fs)"), AdvancedSeconds, FrozenGameSecondsTolerance),
            FMath::Abs(AdvancedSeconds) <= FrozenGameSecondsTolerance);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_LoadHold_GameTimeFrozenWallTimeRuns,
    "Ck.Snapshot.LoadHold.GameTimeFrozenWallTimeRuns",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::ProductFilter)

bool FCk_Snapshot_LoadHold_GameTimeFrozenWallTimeRuns::RunTest(const FString& /*Parameters*/)
{
    using namespace ck_test_loadhold_clocks;

    auto* Witness = Make_RootedWitness();

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.SlotName = FrozenClock_SlotName;
    Spec.NumPIEClients = 1;
    Spec.NumCycles = 1;

    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([Witness](UWorld* InServer) -> void
    {
        Spawn_ClockProbe(InServer);
        Arm_Witness(InServer, Witness);
    });

    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool { return ProbeReady(); });

    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld* /*InServer*/) -> void
    {
        ck_autotest_snapshot_loadhold::Reset_Observations();
    });

    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this, Witness]() -> bool
    {
        ON_SCOPE_EXIT { Witness->RemoveFromRoot(); };

        const auto& Observations = ck_autotest_snapshot_loadhold::Get_Observations();

        auto AllGood = TestEqual(TEXT("the promise fired exactly once"), Observations.FireCount, 1);
        if (Observations.FireCount == 0)
        { return false; }

        const auto& AtFire = Observations.AtLoadComplete;

        // Both clocks start at 0 when a world begins play, so within THIS world the two readings at the promise
        // edge are the two elapsed times since boot — game time and wall time over exactly the span the loader
        // owned. The pair is the whole claim: not "time is slow" but "one of these ran and the other did not".
        AllGood &= TestTrue(
            FString::Printf(TEXT("WALL time ran while the loader owned the world (%.4fs elapsed since it began "
                                 "play, floor %.2fs) — a frozen wall clock would stall every watchdog"),
                AtFire.RealTimeSeconds, MinimumWallSecondsDuringLoad),
            AtFire.RealTimeSeconds >= MinimumWallSecondsDuringLoad);

        AllGood &= TestTrue(
            FString::Printf(TEXT("...and GAME time did not (%.6fs elapsed over the same span, bound %.4fs)"),
                AtFire.GameTimeSeconds, FrozenGameSecondsTolerance),
            AtFire.GameTimeSeconds <= FrozenGameSecondsTolerance);

        // The dial is the mechanism, and a load that forgot to give it back leaves the whole session at 1/10000
        // speed. Read live rather than from the sample: this is a statement about the world the test is leaving
        // behind, not about the instant the promise fired.
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        if (NOT TestTrue(TEXT("post-load server world resolves"), Server != nullptr))
        { return false; }

        const auto* Settings = Server->GetWorldSettings();
        if (NOT TestTrue(TEXT("the post-load world has world settings to read the dilation from"), Settings != nullptr))
        { return false; }

        AllGood &= TestEqual(
            TEXT("global time dilation is back to its prior value once the world is the player's again"),
            static_cast<double>(Settings->GetEffectiveTimeDilation()), 1.0, 1.0e-3);

        // ...and it really was moved in the first place. The promise edge is AFTER the restore by construction, so
        // the only reading that can witness the freeze is the one taken mid-load, at the hydration edge. Without
        // this the pair above would pass just as well on a build that never touched the dial and simply had a
        // world whose clock happened not to move.
        AllGood &= TestTrue(TEXT("the hydration-edge reading was taken"), Observations.AtHydrated.Taken);

        AllGood &= TestTrue(
            FString::Printf(TEXT("the dilation was HELD DOWN while the loader owned the world (%.6f mid-load) — "
                                 "the freeze is the mechanism, not a side effect of an idle world"),
                Observations.AtHydrated.TimeDilation),
            Observations.AtHydrated.TimeDilation < 0.5f);

        return AllGood;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
