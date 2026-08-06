// Run-status mirror parking — a non-Running mirror that arrives while replayed transitions are
// still queued must be PARKED and applied only after the queue drains. Before the 2026-07 fix,
// mirroring Paused/Stopped immediately made FProcessor_Sm_CommitPendingTransition's not-Running
// branch DISCARD the queued transition and destroy the client's live state entity (the status
// jumped the on-the-wire "transitions then status" ordering).
//
// Driven single-world and deterministically through the same public seams the receive pipeline
// uses: an event is placed on the SM's replay queue (exactly what the rep/relay handlers do),
// then ck::statemachine::MirrorRunStatus_OrDeferWhileReplaying delivers a Paused mirror. The SM
// must stay Running until the replayed transition commits, then land Paused — with the
// transition's EnterState actually fired (not discarded).
//
// Surface in Session Frontend: Ck.StateMachine.Net.RunStatusMirror_DefersWhileReplayInFlight

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkStateMachine/Net/CkStateMachine_NetContextUtils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_mirror_defer_test
{
    static FCk_Handle_StateMachine GSm;
    static FCk_Handle              GSmOwner;

    auto Reset() -> void
    {
        GSm      = {};
        GSmOwner = {};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineNet_RunStatusMirror_DefersWhileReplayInFlight,
    "Ck.StateMachine.Net.RunStatusMirror_DefersWhileReplayInFlight",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_RunStatusMirror_DefersWhileReplayInFlight::RunTest(const FString& Parameters)
{
    using namespace ck_sm_mirror_defer_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GSmOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});
            if (ck::Is_NOT_Valid(GSmOwner))
            { AddError(TEXT("failed to create the transient owner entity")); return; }

            auto Params = FCk_StateMachine_Spec{UCk_AutoTest_Sm_RecordingState_A::StaticClass()};
            // Defaults: AutoStart OnSetup, DoesNotReplicate.
            GSm = UCk_Utils_StateMachine_UE::Add(GSmOwner, Params);
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("failed to add the SM")); }
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GSm)
                && UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get()
                    == UCk_AutoTest_Sm_RecordingState_A::StaticClass();
        }),
        8.0,
        TEXT("SM starts and enters initial state A")));

    // Queue a replayed transition A -> B, then deliver a Paused mirror in the same frame — the
    // exact ordering hazard: status arriving alongside not-yet-applied transition events.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM invalid at replay-injection time")); return; }

            auto Entity = FCk_Handle{GSm};
            Entity.AddOrGet<ck::FFragment_Sm_ReplayQueue>().Get_Queue().Add(
                FCk_Sm_TransitionEvent{
                    UCk_AutoTest_Sm_RecordingState_A::StaticClass(),
                    UCk_AutoTest_Sm_RecordingState_B::StaticClass(),
                    /*Seq*/ 1,
                    /*Fingerprint*/ 0});

            ck::statemachine::MirrorRunStatus_OrDeferWhileReplaying(Entity, ECk_SmRunStatus::Paused);

            // The mirror must have parked, not applied — the queued transition still needs a
            // Running SM to commit.
            if (UCk_Utils_StateMachine_UE::Get_RunStatus(GSm) != ECk_SmRunStatus::Running)
            { AddError(TEXT("Paused mirror applied immediately despite a queued replayed transition (should have parked)")); }
        })));

    // The queued event drains (one per pump), commits B while still Running, then the commit tail
    // applies the parked Paused.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { return false; }
            return UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get()
                    == UCk_AutoTest_Sm_RecordingState_B::StaticClass()
                && UCk_Utils_StateMachine_UE::Get_RunStatus(GSm) == ECk_SmRunStatus::Paused;
        }),
        8.0,
        TEXT("replayed transition commits (A -> B), then the parked Paused mirror applies")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("server world / SM unavailable at final assertion")); return false; }

            TestEqual(TEXT("SM landed on B (replayed transition was NOT discarded)"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_RecordingState_B::StaticClass()));
            TestEqual(TEXT("parked Paused applied after the queue drained"),
                static_cast<int32>(UCk_Utils_StateMachine_UE::Get_RunStatus(GSm)),
                static_cast<int32>(ECk_SmRunStatus::Paused));

            if (auto* Recorder = Server->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>())
            {
                auto EnterCountB = 0;
                for (const auto& Event : Recorder->Get_EventsForState(UCk_AutoTest_Sm_RecordingState_B::StaticClass()))
                {
                    if (Event.Kind == ECk_AutoTest_Sm_EventKind::EnterState)
                    { ++EnterCountB; }
                }
                TestEqual(TEXT("B's EnterState fired exactly once (transition replayed, not dropped)"),
                    EnterCountB, 1);
            }
            else
            { AddError(TEXT("server recorder subsystem missing")); }

            return true;
        }),
        TEXT("non-Running mirror defers until the replayed transition lands")));

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
