// Determinism-fault quarantine gate (spec §9): a state that enters while its owning SM is faulted
// must NOT run its EnterState side effects — the whole point of the fence is that a structurally
// divergent state's gameplay logic never fires. This pins the 2026-07 fix to
// UCk_SmState_EntityScript::BeginPlay, which now skips EnterState when the owner carries
// FTag_Sm_DeterminismFault (previously it ran EnterState once before the fault-requested exit landed).
//
// The fault is stamped directly via Test_ForceDeterminismFault rather than driven through the
// replicated fingerprint-verify path: that end-to-end path (fingerprint known at publish time for
// a freshly-instantiated class) is a documented, separately-tracked gap — a first-ever class
// instantiation publishes fingerprint 0, so the wire mismatch can't be synthesized in a
// single-transition test. This test isolates exactly the gate that was fixed.
//
// Single server world, DoesNotReplicate SM (self-authoritative locally) — no possession or
// replication dependency, so it is immune to the multi-client possession-degradation flake.
//
// Surface in Session Frontend: Ck.StateMachine.Net.DeterminismFault_GateSkipsEnter
// (Enter-despite-fault gate regression guard — see 2026-07 CkStateMachine audit.)

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkStateMachine/Net/CkStateMachine_TestSupport.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_Sm_Recorder.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_fault_gate_test
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
    FCkStateMachineNet_DeterminismFault_GateSkipsEnter,
    "Ck.StateMachine.Net.DeterminismFault_GateSkipsEnter",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineNet_DeterminismFault_GateSkipsEnter::RunTest(const FString& Parameters)
{
    using namespace ck_sm_fault_gate_test;

    bSuppressLogErrors = true;
    bSuppressLogWarnings = true;
    Reset();

    constexpr auto NumPIEClients = 2;
    constexpr auto ExpectedTotalWorlds = 2;
    constexpr auto ReadyTimeoutSeconds = 30.0f;
    const auto MapPath = FString{TEXT("/Engine/Maps/Entry")};

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_StartPIEMultiClient(NumPIEClients, MapPath));
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitForPIEReady(ExpectedTotalWorlds, ReadyTimeoutSeconds));

    // Build a local-only (DoesNotReplicate) SM on the server world so it runs its full lifecycle
    // here with no possession/replication dependency.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld* InServer) -> void
        {
            GSmOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity_TransientOwner(InServer, {});
            if (ck::Is_NOT_Valid(GSmOwner))
            { AddError(TEXT("failed to create the transient owner entity")); return; }

            auto Params = FCk_Fragment_StateMachine_ParamsData{UCk_AutoTest_Sm_RecordingState_A::StaticClass()};
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

    // Precondition: A's Enter DID fire (recorder saw it) — proving the gate isn't just globally off.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            auto* Recorder = Server != nullptr ? Server->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>() : nullptr;
            if (Recorder == nullptr)
            { AddError(TEXT("server recorder subsystem missing at precondition")); return false; }

            auto EnterCountA = 0;
            for (const auto& Event : Recorder->Get_EventsForState(UCk_AutoTest_Sm_RecordingState_A::StaticClass()))
            {
                if (Event.Kind == ECk_AutoTest_Sm_EventKind::EnterState)
                { ++EnterCountA; }
            }
            TestEqual(TEXT("PRECONDITION: initial state A ran EnterState (gate is not globally suppressing)"),
                EnterCountA, 1);
            return true;
        }),
        TEXT("precondition — A entered normally before the fault")));

    // Fault the SM, then drive a transition A -> B. The commit still runs (fault quarantines
    // future *side effects*, not the bookkeeping), but B's BeginPlay must skip EnterState.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([this](UWorld*) -> void
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM invalid at fault-injection time")); return; }

            UCk_Utils_StateMachine_Test_UE::Test_ForceDeterminismFault(GSm);
            UCk_Utils_StateMachine_UE::Request_Transition(GSm, UCk_AutoTest_Sm_RecordingState_B::StaticClass());
        })));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_TickWorlds(20));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            auto* Server = ck::auto_test::net::Get_ServerWorld();
            if (Server == nullptr || ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("server world / SM unavailable at assertion time")); return false; }

            TestTrue(TEXT("SM reports the determinism fault"),
                UCk_Utils_StateMachine_Test_UE::Test_Get_HasDeterminismFault(GSm));

            auto* Recorder = Server->GetSubsystem<UCk_AutoTest_Sm_RecorderSubsystem>();
            if (Recorder == nullptr)
            { AddError(TEXT("server recorder subsystem missing at assertion")); return false; }

            auto EnterCountB = 0;
            for (const auto& Event : Recorder->Get_EventsForState(UCk_AutoTest_Sm_RecordingState_B::StaticClass()))
            {
                if (Event.Kind == ECk_AutoTest_Sm_EventKind::EnterState)
                { ++EnterCountB; }
            }
            TestEqual(TEXT("state entering under a faulted SM did NOT run EnterState side effects"),
                EnterCountB, 0);
            return true;
        }),
        TEXT("Enter-despite-fault gate: no EnterState side effects on a quarantined SM")));

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
