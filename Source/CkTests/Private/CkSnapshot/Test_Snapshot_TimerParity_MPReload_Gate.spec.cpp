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
//
// HARNESS CONVERSION (saveload-v3-ergonomics Phase 1): the StartPIE->save->load->reload-wait->EndPIE skeleton is now
// owned by ck::auto_test::snapshot::EnqueueRoundTrip (CkSnapshot_TestHarness_Common). This file supplies only the
// per-test stage lambdas (Spawn/SubjectReady/Mutate/ReloadSettled/Assert) + the parity assertions, NumCycles=2.
// Two deliberate, coverage-neutral deviations from the pre-harness file:
//   * The pre-save sanity stage (old Stage 3b: server holds elapsed 7 / done before save) is dropped — the harness
//     has no pre-save assert slot, and its only failure mode (the deferred Jump never took) surfaces identically in
//     the post-reload Assert ("elapsed round-tripped (7, not Construct default 10)" would read 10).
//   * The old Stage 8 "no re-fire after extra ticks" is folded into the two-cycle rule: NumCycles=2 re-runs the
//     WHOLE round-trip and re-asserts, a structurally STRONGER stability check than +60 ticks (a re-arm between
//     cycles changes cycle-2 state). The Assert lambda still ticks SettleFrames before running (harness default),
//     so the terminal/paused checks below already read post-settle.
//
// Surface in Session Frontend: Ck.Snapshot.Parity.Timer_MPReload

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"
#include "EngineUtils.h"               // TActorIterator
#include "HAL/IConsoleManager.h"       // net.AllowPIESeamlessTravel
#include "Math/UnrealMathUtility.h"    // FMath::IsNearlyEqual

#include "CkTimer/CkTimer_Utils.h"

#include "CkTests/CkTests_Fragment_Data.h" // TAG_Timer_AutoTest_Net_*

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"
#include "CkTests/Snapshot/CkSnapshot_TestHarness_Common.h"

namespace
{
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

    auto Spec = ck::auto_test::snapshot::FCk_SnapshotRoundTrip_Spec{};
    Spec.NumPIEClients = 2;                 // server window + 1 connected client
    Spec.SlotName      = Timer_SlotName;
    Spec.NumCycles     = 2;                 // two-cycle rule (idempotency / no double-apply stacking)

    // Spawn — open the PIE seamless gate + spawn the replicated bridged probe on the server (composes both timers in
    // Construct).
    Spec.Spawn = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
    {
        if (auto* CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("net.AllowPIESeamlessTravel")))
        { CVar->Set(1, ECVF_SetByCode); }

        auto SpawnInfo = FActorSpawnParameters{};
        SpawnInfo.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
        auto* Probe = InServer->SpawnActor<ACk_AutoTest_NetSubject_M2bProbe_Replicated>(
            ACk_AutoTest_NetSubject_M2bProbe_Replicated::StaticClass(), FTransform{Timer_SavedLoc}, SpawnInfo);
        if (Probe == nullptr) { AddError(TEXT("Spawn: replicated probe spawn returned null")); }
    });

    // SubjectReady — both timers composed (Construct + Setup ran) before we mutate.
    Spec.SubjectReady = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        if (Server == nullptr) { return false; }
        auto* Probe = Timer_FindProbe(Server);
        return ck::IsValid(Timer_ResolveCountdown(Probe)) && ck::IsValid(Timer_ResolveDone(Probe));
    });

    // Mutate — ADVANCE both timers via a DEFERRED Request_Jump (drains on a later tick; the harness settle after
    // Mutate lets it take before Save). Countdown: Consume 3 (full 10 → elapsed 7). Done: Tick 4 (0 → elapsed 4 == goal).
    Spec.Mutate = FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
    {
        auto* Probe = Timer_FindProbe(InServer);
        auto Countdown = Timer_ResolveCountdown(Probe);
        auto Done      = Timer_ResolveDone(Probe);
        if (ck::Is_NOT_Valid(Countdown) || ck::Is_NOT_Valid(Done))
        { AddError(TEXT("Mutate: server timers unresolved")); return; }

        UCk_Utils_Timer_UE::Request_Jump(Countdown, FCk_Request_Timer_Jump{FCk_Time{Countdown_JumpSec}}, {});
        UCk_Utils_Timer_UE::Request_Jump(Done,      FCk_Request_Timer_Jump{FCk_Time{Done_JumpSec}}, {});
    });

    // ReloadSettled — extra reload predicate ANDed onto the harness default: the Countdown elapsed CONVERGED on the
    // restored value (proves HydrationApply's re-drive completed, not just a re-Construct which would give elapsed 10).
    Spec.ReloadSettled = FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        if (Server == nullptr) { return false; }
        auto Countdown = Timer_ResolveCountdown(Timer_FindProbe(Server));
        if (ck::Is_NOT_Valid(Countdown)) { return false; }
        return FMath::IsNearlyEqual(Timer_ElapsedSeconds(Countdown), Countdown_ExpectedElapsedSec, ElapsedToleranceSec);
    });

    // Assert — SERVER parity: the runtime state survived save -> seamless reload -> hydration (NOT just Construct
    // re-derivation, which would give Countdown elapsed 10 and Done elapsed 0). Runs post-settle each cycle.
    Spec.Assert = FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
    {
        auto* Server = ck::auto_test::snapshot::Get_PostTravelServerWorld();
        if (Server == nullptr) { AddError(TEXT("Assert: no post-travel server world")); return false; }
        auto* Probe = Timer_FindProbe(Server);
        if (Probe == nullptr) { AddError(TEXT("Assert: server probe missing post-reload")); return false; }

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

        // Scenario B — terminal count-up timer round-trips as done (and, via the two-cycle rule, stays done: a re-fire
        // between cycles would change cycle-2 state).
        TestTrue(TEXT("Done: elapsed round-tripped (4 == GoalValue, not Construct default 0)"),
            FMath::IsNearlyEqual(Timer_ElapsedSeconds(Done), Done_ExpectedElapsedSec, ElapsedToleranceSec));
        TestTrue(TEXT("Done: terminal state round-tripped (Get_IsDone)"),
            UCk_Utils_Timer_UE::Get_CurrentTimerValue(Done).Get_IsDone());
        TestTrue(TEXT("Done: direction round-tripped (CountUp)"),
            UCk_Utils_Timer_UE::Get_CountDirection(Done) == ECk_Timer_CountDirection::CountUp);
        TestTrue(TEXT("Done: run-state round-tripped (Paused)"),
            UCk_Utils_Timer_UE::Get_CurrentState(Done) == ECk_Timer_State::Paused);
        return true;
    });

    ck::auto_test::snapshot::EnqueueRoundTrip(this, Spec);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
