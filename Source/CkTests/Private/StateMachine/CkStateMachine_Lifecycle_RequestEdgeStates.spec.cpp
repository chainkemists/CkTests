// Lifecycle-request edge states — pins the request handlers' behavior on the paths that fall
// outside the happy Start→Transition→Stop flow. Each scenario reproduces a corruption found by
// the 2026-07 CkStateMachine audit:
//
//   1. PauseDroppedTransitionDoesNotWedgeEvaluator — a Request_Transition dropped while Paused
//      must not leave a stale FTag_Sm_TransitionQueued that blocks the evaluator forever.
//   2. StartWhilePausedIsRejected — Request_Start on a Paused SM must not corrupt run-state
//      (duplicate FTag_Sm_Running + spurious initial re-entry); Resume is the way back.
//   3. StopMidTransitionDestroysDeferredPreviousState — Request_Stop with a transition mid-flight
//      must destroy the deferred-alive previous state entity the pending fragment stashed.
//   4. RapidDoubleTransitionCoalescesAndDestroysPreviousState — two Request_Transitions in one
//      drain batch coalesce (A→C); the kept-alive previous state must still be destroyed and the
//      never-entered intermediate target must never fire EnterState.
//   5. NullTargetTransitionIsRejectedAndSmSurvives — a null target class is rejected at enqueue;
//      the SM stays in its current state and keeps evaluating (no stateless limbo).
//   6. PausedSmDoesNotEvaluatePolledConditions — the pause contract is "no ticking": user
//      Evaluate predicates must not be CALLED while Paused (a latched pause-time Pass could
//      otherwise commit on Resume; predicates may have observable side effects).
//
// The SM under test is DoesNotReplicate (self-authoritative on every machine), built directly on
// a transient-owned entity in the server PIE world — no subject actor needed. Multi-client PIE
// (2 worlds) is used only because it is the suite's proven harness topology.
//
// Surface in Session Frontend: Ck.StateMachine.Lifecycle.*

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "CkAutoTest_Sm_LifecycleFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_lifecycle_test
{
    // Cross-latent-command state. Latent commands run as separate callbacks over multiple frames;
    // file-scope statics are the suite's established way to thread handles between them. Reset()
    // at the top of every RunTest — PIE worlds (and thus these handles) do not outlive a test.
    static FCk_Handle_StateMachine GSm;
    static FCk_Handle              GSmOwner;
    static FCk_Handle_SmState      GCapturedStateHandle;
    static int32                   GEvaluateCountAtPause = 0;

    auto Reset() -> void
    {
        GSm                  = {};
        GSmOwner             = {};
        GCapturedStateHandle = {};
        GEvaluateCountAtPause = 0;
        UCk_AutoTest_Sm_GateCondition_UE::Gate = false;
        UCk_AutoTest_Sm_GateCondition_UE::EvaluateCallCount = 0;
    }

    // Builds a DoesNotReplicate / AutoStart-Disabled SM on a fresh transient-owned entity in
    // InWorld and starts it. Returns false (with no SM) on any failure.
    auto BuildAndStartSm(
        UWorld* InWorld,
        const TSubclassOf<UCk_SmState_EntityScript>& InInitialState) -> bool
    {
        GSmOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InWorld, {});
        if (ck::Is_NOT_Valid(GSmOwner))
        { return false; }

        auto Params = FCk_Fragment_StateMachine_ParamsData{InInitialState};
        Params.Set_AutoStart(ECk_SmAutoStart::Disabled);

        GSm = UCk_Utils_StateMachine_UE::Add(GSmOwner, Params);
        if (ck::Is_NOT_Valid(GSm))
        { return false; }

        UCk_Utils_StateMachine_UE::Request_Start(GSm);
        return true;
    }

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};
}

// --------------------------------------------------------------------------------------------------------------------
// 1. A transition request dropped while Paused must not wedge the evaluator.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineLifecycle_PauseDroppedTransitionDoesNotWedgeEvaluator,
    "Ck.StateMachine.Lifecycle.PauseDroppedTransitionDoesNotWedgeEvaluator",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineLifecycle_PauseDroppedTransitionDoesNotWedgeEvaluator::RunTest(const FString& Parameters)
{
    using namespace ck_sm_lifecycle_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT BuildAndStartSm(InServer, UCk_AutoTest_Sm_GatedIdleState_UE::StaticClass()))
            { AddError(TEXT("failed to build/start the gated SM on the server world")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(15));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid after settle")); return false; }

            TestEqual(TEXT("PRECONDITION: SM is Running in GatedIdle"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_GatedIdleState_UE::StaticClass()));
            return true;
        }),
        TEXT("precondition — SM running in gated idle state")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Pause(ck_sm_lifecycle_test::GSm);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    // The wedge injection: a transition request that the handler drops (SM is Paused). Before the
    // fix, the FTag_Sm_TransitionQueued added at enqueue was never cleared on this path, blocking
    // FProcessor_SmState_Evaluate forever after.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Transition(ck_sm_lifecycle_test::GSm,
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_AutoTest_Sm_GateCondition_UE::Gate = true;
            UCk_Utils_StateMachine_UE::Request_Resume(ck_sm_lifecycle_test::GSm);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { return false; }
            return UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get()
                == UCk_AutoTest_Sm_RecordingState_B::StaticClass();
        }),
        8.0,
        TEXT("post-Resume the polled condition drives GatedIdle -> B (no stale TransitionQueued wedge)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid at final assertion")); return false; }

            TestEqual(TEXT("SM evaluated its gated transition after Resume"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_RecordingState_B::StaticClass()));
            return true;
        }),
        TEXT("dropped-while-paused transition request does not wedge the evaluator")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 2. Request_Start while Paused is rejected (Resume is the way back).
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineLifecycle_StartWhilePausedIsRejected,
    "Ck.StateMachine.Lifecycle.StartWhilePausedIsRejected",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineLifecycle_StartWhilePausedIsRejected::RunTest(const FString& Parameters)
{
    using namespace ck_sm_lifecycle_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT BuildAndStartSm(InServer, UCk_AutoTest_Sm_RecordingState_A::StaticClass()))
            { AddError(TEXT("failed to build/start the SM on the server world")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(15));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Pause(ck_sm_lifecycle_test::GSm);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    // Start on a Paused SM. Before the fix this fell through the Running-only guard: duplicate
    // FTag_Sm_Running add (ensure) + DoEnterState overwrote the paused current state.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Start(ck_sm_lifecycle_test::GSm);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid after Start-while-Paused")); return false; }

            TestEqual(TEXT("SM stays Paused after a rejected Start"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(GSm)),
                static_cast<int32>(ECk_SmRunStatus::Paused));
            TestEqual(TEXT("SM still in its pre-pause state"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_RecordingState_A::StaticClass()));
            return true;
        }),
        TEXT("Start while Paused is rejected without corrupting run-state")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Resume(ck_sm_lifecycle_test::GSm);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(5));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid after Resume")); return false; }

            TestEqual(TEXT("SM resumes normally after the rejected Start"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(GSm)),
                static_cast<int32>(ECk_SmRunStatus::Running));
            return true;
        }),
        TEXT("SM is healthy after the rejected Start (Resume works)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 3. Stop with a transition mid-flight destroys the deferred-alive previous state.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineLifecycle_StopMidTransitionDestroysDeferredPreviousState,
    "Ck.StateMachine.Lifecycle.StopMidTransitionDestroysDeferredPreviousState",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineLifecycle_StopMidTransitionDestroysDeferredPreviousState::RunTest(const FString& Parameters)
{
    using namespace ck_sm_lifecycle_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT BuildAndStartSm(InServer, UCk_AutoTest_Sm_RecordingState_A::StaticClass()))
            { AddError(TEXT("failed to build/start the SM on the server world")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(15));

    // Transition + Stop in the same request batch: the transition handler exits A and stashes its
    // still-alive entity in FFragment_Sm_PendingTransition; the Stop handler must destroy it when
    // it discards the pending transition (before the fix it only removed the fragment — leak).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid at transition+stop time")); return; }

            GCapturedStateHandle = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(GSm);
            if (ck::Is_NOT_Valid(GCapturedStateHandle))
            { AddError(TEXT("could not capture the current state handle before the transition")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(GSm,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
            UCk_Utils_StateMachine_UE::Request_Stop(GSm);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid at final assertion")); return false; }

            TestEqual(TEXT("SM is Stopped"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(GSm)),
                static_cast<int32>(ECk_SmRunStatus::Stopped));
            TestFalse(TEXT("the deferred-alive previous state entity was destroyed (no leak)"),
                ck::IsValid(GCapturedStateHandle));
            return true;
        }),
        TEXT("Stop mid-transition destroys the deferred-alive previous state entity")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 4. Two transitions in one drain batch coalesce; the previous state is destroyed, the
//    never-entered intermediate target never fires EnterState.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineLifecycle_RapidDoubleTransitionCoalescesAndDestroysPreviousState,
    "Ck.StateMachine.Lifecycle.RapidDoubleTransitionCoalescesAndDestroysPreviousState",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineLifecycle_RapidDoubleTransitionCoalescesAndDestroysPreviousState::RunTest(const FString& Parameters)
{
    using namespace ck_sm_lifecycle_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT BuildAndStartSm(InServer, UCk_AutoTest_Sm_RecordingState_A::StaticClass()))
            { AddError(TEXT("failed to build/start the SM on the server world")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(15));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid at double-transition time")); return; }

            GCapturedStateHandle = UCk_Utils_StateMachine_UE::Get_CurrentStateHandle(GSm);
            if (ck::Is_NOT_Valid(GCapturedStateHandle))
            { AddError(TEXT("could not capture the current state handle before the transitions")); return; }

            UCk_Utils_StateMachine_UE::Request_Transition(GSm,
                UCk_AutoTest_Sm_RecordingState_B::StaticClass());
            UCk_Utils_StateMachine_UE::Request_Transition(GSm,
                UCk_AutoTest_Sm_RecordingState_C::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("server world / SM unavailable at final assertion")); return false; }

            TestEqual(TEXT("SM landed on the LAST requested target (A -> C coalesce)"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_RecordingState_C::StaticClass()));
            TestFalse(TEXT("the kept-alive previous state entity (A) was destroyed (no leak)"),
                ck::IsValid(GCapturedStateHandle));

            if (auto* Recorder = Server->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>())
            {
                const auto EventsForB = Recorder->Get_EventsForState(
                    UCk_AutoTest_Sm_RecordingState_B::StaticClass());
                auto EnterCountB = 0;
                for (const auto& Event : EventsForB)
                {
                    if (Event.Kind == ECk_AutoTest_Sm_EventKind::EnterState)
                    { ++EnterCountB; }
                }
                TestEqual(TEXT("the overwritten intermediate target (B) never fired EnterState"),
                    EnterCountB, 0);
            }
            else
            { AddError(TEXT("server recorder subsystem missing")); }

            return true;
        }),
        TEXT("rapid double transition coalesces to the last target without leaking the previous state")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 5. A null-target transition request is rejected at enqueue; the SM survives and keeps evaluating.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineLifecycle_NullTargetTransitionIsRejectedAndSmSurvives,
    "Ck.StateMachine.Lifecycle.NullTargetTransitionIsRejectedAndSmSurvives",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineLifecycle_NullTargetTransitionIsRejectedAndSmSurvives::RunTest(const FString& Parameters)
{
    using namespace ck_sm_lifecycle_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT BuildAndStartSm(InServer, UCk_AutoTest_Sm_GatedIdleState_UE::StaticClass()))
            { AddError(TEXT("failed to build/start the gated SM on the server world")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(15));

    // Null target. Before the fix this ran the exit cascade, then DoEnterState ensure-returned,
    // leaving a Running SM with no current state and no way to ever evaluate again.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Transition(ck_sm_lifecycle_test::GSm,
                TSubclassOf<UCk_SmState_EntityScript>{});
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(10));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid after null-target request")); return false; }

            TestEqual(TEXT("SM is still Running"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(GSm)),
                static_cast<int32>(ECk_SmRunStatus::Running));
            TestEqual(TEXT("SM is still in GatedIdle (no stateless limbo)"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_GatedIdleState_UE::StaticClass()));
            return true;
        }),
        TEXT("null-target request rejected without exiting the current state")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_AutoTest_Sm_GateCondition_UE::Gate = true;
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { return false; }
            return UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get()
                == UCk_AutoTest_Sm_RecordingState_B::StaticClass();
        }),
        8.0,
        TEXT("SM keeps evaluating after the rejected null-target request (GatedIdle -> B)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid at final assertion")); return false; }

            TestEqual(TEXT("SM transitioned normally after the rejected request"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_RecordingState_B::StaticClass()));
            return true;
        }),
        TEXT("SM survives a null-target transition request fully functional")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 6. A Paused SM must not call user Evaluate predicates at all.
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineLifecycle_PausedSmDoesNotEvaluatePolledConditions,
    "Ck.StateMachine.Lifecycle.PausedSmDoesNotEvaluatePolledConditions",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineLifecycle_PausedSmDoesNotEvaluatePolledConditions::RunTest(const FString& Parameters)
{
    using namespace ck_sm_lifecycle_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            if (NOT BuildAndStartSm(InServer, UCk_AutoTest_Sm_GatedIdleState_UE::StaticClass()))
            { AddError(TEXT("failed to build/start the gated SM on the server world")); }
        })));

    // Running: the polled condition must actually be evaluating (gate stays false, so no
    // transition — just proof the evaluator visits the predicate).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GSm)
                && UCk_AutoTest_Sm_GateCondition_UE::EvaluateCallCount > 3;
        }),
        8.0,
        TEXT("polled condition evaluates while Running")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Pause(ck_sm_lifecycle_test::GSm);
        })));

    // Snapshot the call count only once the pause has actually landed (the request drains
    // deferred, so up to a frame of legitimate evaluation can follow the request).
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm)
                || UCk_Utils_StateMachine_UE::Get_RunStatus(GSm) != ECk_SmRunStatus::Paused)
            { return false; }

            GEvaluateCountAtPause = UCk_AutoTest_Sm_GateCondition_UE::EvaluateCallCount;
            return true;
        }),
        8.0,
        TEXT("SM reports Paused (snapshot the evaluate count)")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            TestEqual(TEXT("user Evaluate was never called while Paused"),
                UCk_AutoTest_Sm_GateCondition_UE::EvaluateCallCount, GEvaluateCountAtPause);
            return true;
        }),
        TEXT("paused SM does not run polled-condition predicates")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_Utils_StateMachine_UE::Request_Resume(ck_sm_lifecycle_test::GSm);
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return UCk_AutoTest_Sm_GateCondition_UE::EvaluateCallCount > GEvaluateCountAtPause;
        }),
        8.0,
        TEXT("evaluation resumes after Request_Resume")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_EndPIE());

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([]() -> bool
        {
            FAutomationTestBase::bSuppressLogErrors = false;
            FAutomationTestBase::bSuppressLogWarnings = false;
            return true;
        }),
        TEXT("restore log suppression statics")));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
