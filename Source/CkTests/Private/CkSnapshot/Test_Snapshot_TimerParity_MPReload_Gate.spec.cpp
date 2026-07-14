// CkSnapshot Timer-Parity GATE — strict value round-trip of a Construct-composed Timer's runtime state through a
// listen-server SEAMLESS ServerTravel reload, asserted on the SERVER (authority). Unlike the Attribute/Team parity
// gates, the assertions are server-side: a Timer is UNREPLICATED, so its restored state lives only on the authority
// (the load-path HydrationApply runs there); the client re-Constructs a fresh timer and never receives the saved
// position. Two timers exercise both axes:
//   - Countdown : a 10s CountDown timer advanced to elapsed 7 (mid-run) — proves elapsed + CountDown direction +
//                 Paused run-state survive save -> restore, not just Construct re-derivation (which would give a full
//                 chrono at elapsed 10).
//   - Done      : a 4s CountUp timer advanced to elapsed 4 (== GoalValue, terminal) — proves the terminal state
//                 round-trips AND that restore does not re-broadcast OnTimerDone (the handler positions via Jump,
//                 which never fires OnTimerDone, and a restored Paused+done timer is never ticked by the Update
//                 processors). See the report for the delegate-count limitation.
// Surface in Session Frontend: Ck.Snapshot.Parity.Timer_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Math/UnrealMathUtility.h"    // FMath::IsNearlyEqual

#include "CkTimer/CkTimer_Utils.h"

#include "CkTests/CkTests_Fragment_Data.h" // TAG_Timer_AutoTest_Net_*

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkSnapshot/Subsystem/CkSnapshot_Subsystem.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

namespace
{
    constexpr auto Timer_MapPath  = TEXT("/Engine/Maps/Entry");
    const auto     Timer_SlotName = FName{TEXT("CkSnapshot_TimerParity_GateSlot")};
    const auto     Timer_SavedLoc = FVector{100.0, 200.0, 300.0};

    // Countdown timer: Construct duration 10s (CountDown). Setup Completes the chrono to elapsed 10; a server-side
    // Jump of 3s Consumes it down to elapsed 7. Paused throughout, so elapsed does not drift. Deliberately asymmetric
    // (elapsed 7 != remaining 3) so an elapsed/remaining confusion in Produce/Hydration would be caught.
    constexpr auto Countdown_JumpSec            = 3.0;
    constexpr auto Countdown_ExpectedElapsedSec = 7.0;

    // Done timer: Construct duration 4s (CountUp). Setup leaves the chrono at elapsed 0; a server-side Jump of 4s Ticks
    // it up to elapsed 4 == GoalValue → done.
    constexpr auto Done_JumpSec            = 4.0;
    constexpr auto Done_ExpectedElapsedSec = 4.0;

    constexpr auto ElapsedToleranceSec = 0.05; // Paused → exact; small epsilon for the FCk_Time double round-trip.

    static TWeakObjectPtr<UWorld> GTimer_PreServerWorld;

    auto Timer_MapNameOf(UWorld* InWorld) -> FString
    {
        return InWorld != nullptr ? InWorld->RemovePIEPrefix(InWorld->GetOutermost()->GetName()) : FString{};
    }

    auto Timer_Subsystem(UWorld* InWorld) -> UCk_Snapshot_Subsystem_UE*
    {
        if (InWorld == nullptr || InWorld->GetGameInstance() == nullptr) { return nullptr; }
        return InWorld->GetGameInstance()->GetSubsystem<UCk_Snapshot_Subsystem_UE>();
    }

    auto Timer_FindProbe(UWorld* InWorld) -> ACk_AutoTest_NetSubject_M2bProbe_Replicated*
    {
        if (InWorld == nullptr) { return nullptr; }
        for (auto It = TActorIterator<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(InWorld); It; ++It) { return *It; }
        return nullptr;
    }

    auto Timer_ResolveEntity(AActor* InProbe) -> FCk_Handle
    {
        if (InProbe == nullptr) { return {}; }
        return UCk_Utils_OwningActor_UE::TryGet_ActorEntityHandle(InProbe);
    }

    auto Timer_ResolveByTag(AActor* InProbe, const FGameplayTag& InTimerName) -> FCk_Handle_Timer
    {
        const auto Owner = Timer_ResolveEntity(InProbe);
        if (ck::Is_NOT_Valid(Owner)) { return {}; }
        return UCk_Utils_Timer_UE::TryGet_Timer(Owner, InTimerName);
    }

    auto Timer_ResolveCountdown(AActor* InProbe) -> FCk_Handle_Timer
    {
        return Timer_ResolveByTag(InProbe, TAG_Timer_AutoTest_Net_Countdown.GetTag());
    }

    auto Timer_ResolveDone(AActor* InProbe) -> FCk_Handle_Timer
    {
        return Timer_ResolveByTag(InProbe, TAG_Timer_AutoTest_Net_Done.GetTag());
    }

    auto Timer_ElapsedSeconds(const FCk_Handle_Timer& InTimer) -> double
    {
        return UCk_Utils_Timer_UE::Get_CurrentTimerValue(InTimer).Get_TimeElapsed().Get_Seconds();
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_TimerParity_MPReload_Gate,
    "Ck.Snapshot.Parity.Timer_MPReload",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_TimerParity_MPReload_Gate::RunTest(const FString& Parameters)
{
    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;

    constexpr auto NumPIEClients = 2;        // server window + 1 connected client
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    constexpr auto FramesPerSettle = 30;
    constexpr auto ReloadTimeoutSeconds = 60.0f;
    constexpr auto FramesPostReconnect = 60;

    GTimer_PreServerWorld = nullptr;

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, FString{Timer_MapPath}));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Stage 1 — open the PIE seamless gate + spawn the replicated bridged probe on the server.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
            { CVar->Set(1, ECVF_SetByCode); }

            auto SpawnInfo = FActorSpawnParameters{};
            SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
            auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
                ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{Timer_SavedLoc}, SpawnInfo);
            if (Probe == nullptr) { AddError(TEXT("Stage 1: replicated probe spawn returned null")); }
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 2 — pre-reload sanity: the server timers are composed (Construct + Setup ran).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { return false; }
            auto* Probe = Timer_FindProbe(Server);
            return ck::IsValid(Timer_ResolveCountdown(Probe)) && ck::IsValid(Timer_ResolveDone(Probe));
        }),
        ReadyTimeoutSeconds));

    // Stage 3 — ADVANCE both timers on the server via a DEFERRED Request_Jump (processed on a later tick; asserted in
    // Stage 3b after a settle). Countdown: Consume 3 (full 10 → elapsed 7). Done: Tick 4 (0 → elapsed 4 == goal).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = Timer_FindProbe(InServer);
            auto Countdown = Timer_ResolveCountdown(Probe);
            auto Done      = Timer_ResolveDone(Probe);
            if (ck::Is_NOT_Valid(Countdown) || ck::Is_NOT_Valid(Done))
            { AddError(TEXT("Stage 3: server timers unresolved")); return; }

            UCk_Utils_Timer_UE::Request_Jump(Countdown, FCk_Request_Timer_Jump{FCk_Time{Countdown_JumpSec}});
            UCk_Utils_Timer_UE::Request_Jump(Done,      FCk_Request_Timer_Jump{FCk_Time{Done_JumpSec}});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 3b — assert the SERVER holds the advanced state before saving (failing here means the Jump didn't take,
    // not that snapshot broke).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Probe = Timer_FindProbe(InServer);
            auto Countdown = Timer_ResolveCountdown(Probe);
            auto Done      = Timer_ResolveDone(Probe);
            if (ck::Is_NOT_Valid(Countdown) || ck::Is_NOT_Valid(Done))
            { AddError(TEXT("Stage 3b: server timers unresolved")); return; }

            TestTrue(TEXT("pre-save: Countdown elapsed == 7"),
                FMath::IsNearlyEqual(Timer_ElapsedSeconds(Countdown), Countdown_ExpectedElapsedSec, ElapsedToleranceSec));
            TestTrue(TEXT("pre-save: Countdown direction == CountDown"),
                UCk_Utils_Timer_UE::Get_CountDirection(Countdown) == ECk_Timer_CountDirection::CountDown);
            TestTrue(TEXT("pre-save: Countdown run-state == Paused"),
                UCk_Utils_Timer_UE::Get_CurrentState(Countdown) == ECk_Timer_State::Paused);

            TestTrue(TEXT("pre-save: Done elapsed == 4 (== GoalValue)"),
                FMath::IsNearlyEqual(Timer_ElapsedSeconds(Done), Done_ExpectedElapsedSec, ElapsedToleranceSec));
            TestTrue(TEXT("pre-save: Done is terminal (Get_IsDone)"),
                UCk_Utils_Timer_UE::Get_CurrentTimerValue(Done).Get_IsDone());
            TestTrue(TEXT("pre-save: Done direction == CountUp"),
                UCk_Utils_Timer_UE::Get_CountDirection(Done) == ECk_Timer_CountDirection::CountUp);
        })));

    // Stage 4 — Save on the server; stash the pre-travel server world.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GTimer_PreServerWorld = InServer;
            auto* Sub = Timer_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 4: no snapshot subsystem")); return; }
            Sub->Request_Save(Timer_SlotName, FCk_Delegate_OnSaveComplete{});
        })));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPerSettle));

    // Stage 5 — fire async Load (triggers seamless ServerTravel) + assert non-blocking.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            auto* Sub = Timer_Subsystem(InServer);
            if (Sub == nullptr) { AddError(TEXT("Stage 5: no snapshot subsystem")); return; }
            Sub->Request_Load(Timer_SlotName, FCk_Delegate_OnLoadComplete{});
            TestTrue(TEXT("Stage 5: Request_Load non-blocking"), Sub->Get_IsLoadInProgress());
        })));

    // Stage 6 — poll until the server finished load, rode the travel, and the Countdown elapsed CONVERGED on the
    // restored value (proves HydrationApply's re-drive completed, not just that the timer was re-Constructed).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForCondition(
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || Server == GTimer_PreServerWorld.Get() || !Server->HasBegunPlay()) { return false; }
            if (Timer_MapNameOf(Server) != Timer_MapPath) { return false; }
            auto* Sub = Timer_Subsystem(Server);
            if (Sub == nullptr || Sub->Get_IsLoadInProgress()) { return false; }

            auto* Probe = Timer_FindProbe(Server);
            auto Countdown = Timer_ResolveCountdown(Probe);
            if (ck::Is_NOT_Valid(Countdown)) { return false; }
            return FMath::IsNearlyEqual(Timer_ElapsedSeconds(Countdown), Countdown_ExpectedElapsedSec, ElapsedToleranceSec);
        }),
        ReloadTimeoutSeconds));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));

    // Stage 7 — SERVER parity assertions: the runtime state survived save -> seamless reload -> hydration (NOT just
    // Construct re-derivation, which would give Countdown elapsed 10 and Done elapsed 0).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr) { AddError(TEXT("Stage 7: no post-travel server world")); return false; }
            auto* Probe = Timer_FindProbe(Server);
            if (Probe == nullptr) { AddError(TEXT("Stage 7: server probe missing post-reload")); return false; }

            auto Countdown = Timer_ResolveCountdown(Probe);
            auto Done      = Timer_ResolveDone(Probe);
            TestTrue(TEXT("client-independent: both timers re-resolve on the server post-reload"),
                ck::IsValid(Countdown) && ck::IsValid(Done));
            if (ck::Is_NOT_Valid(Countdown) || ck::Is_NOT_Valid(Done)) { return false; }

            // Scenario A — mid-run countdown elapsed + direction + run-state.
            TestTrue(TEXT("Countdown: elapsed round-tripped (7, not Construct default 10)"),
                FMath::IsNearlyEqual(Timer_ElapsedSeconds(Countdown), Countdown_ExpectedElapsedSec, ElapsedToleranceSec));
            TestTrue(TEXT("Countdown: direction round-tripped (CountDown)"),
                UCk_Utils_Timer_UE::Get_CountDirection(Countdown) == ECk_Timer_CountDirection::CountDown);
            TestTrue(TEXT("Countdown: run-state round-tripped (Paused)"),
                UCk_Utils_Timer_UE::Get_CurrentState(Countdown) == ECk_Timer_State::Paused);

            // Scenario B — terminal count-up timer round-trips as done.
            TestTrue(TEXT("Done: elapsed round-tripped (4 == GoalValue, not Construct default 0)"),
                FMath::IsNearlyEqual(Timer_ElapsedSeconds(Done), Done_ExpectedElapsedSec, ElapsedToleranceSec));
            TestTrue(TEXT("Done: terminal state round-tripped (Get_IsDone)"),
                UCk_Utils_Timer_UE::Get_CurrentTimerValue(Done).Get_IsDone());
            TestTrue(TEXT("Done: direction round-tripped (CountUp)"),
                UCk_Utils_Timer_UE::Get_CountDirection(Done) == ECk_Timer_CountDirection::CountUp);
            TestTrue(TEXT("Done: run-state round-tripped (Paused)"),
                UCk_Utils_Timer_UE::Get_CurrentState(Done) == ECk_Timer_State::Paused);
            return true;
        }),
        TEXT("Timer parity: Construct-timer elapsed/direction/run-state + terminal state survive save -> seamless reload")));

    // Stage 8 — no-re-fire evidence: after further ticks the restored Done timer is STILL done and STILL paused (it is
    // never ticked by the Update processors, so completion cannot recur). A direct OnTimerDone delegate-count is not
    // expressible here — the entity is destroyed+rebuilt across seamless travel, so a pre-save binding cannot survive,
    // and FCk_Delegate_Timer is a dynamic delegate needing a UFUNCTION host. This state-stability check plus the
    // handler's structural guarantee (restore positions via Jump, which never broadcasts OnTimerDone) stands in.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(FramesPostReconnect));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Probe  = Timer_FindProbe(Server);
            auto Done    = Timer_ResolveDone(Probe);
            if (ck::Is_NOT_Valid(Done)) { AddError(TEXT("Stage 8: Done timer unresolved")); return false; }

            TestTrue(TEXT("Done: still terminal after further ticks (no re-arm)"),
                UCk_Utils_Timer_UE::Get_CurrentTimerValue(Done).Get_IsDone());
            TestTrue(TEXT("Done: still Paused after further ticks (Update never ran it)"),
                UCk_Utils_Timer_UE::Get_CurrentState(Done) == ECk_Timer_State::Paused);
            return true;
        }),
        TEXT("Timer parity: restored terminal timer is stable post-load (no OnTimerDone re-fire path)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
