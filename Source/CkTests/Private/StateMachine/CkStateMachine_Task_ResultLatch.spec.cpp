// Task terminal-result latch — a terminal result reported via Mark_Result must survive a
// same-frame Tick that returns Running. The tick processor runs before FireFinishedSignal, so
// before the 2026-07 fix the tick's Request_UpdateTaskResult(Running) overwrote the
// not-yet-broadcast terminal result: OnSmTaskFinished fired with "finished: Running" and the
// completion was lost to every consumer.
//
// The fixture reproduces the race deterministically: UCk_AutoTest_Sm_SelfClobberTask_UE's Tick
// calls Mark_Result(Succeeded) then returns Running, and it always returns Running — so the one
// broadcast triggered by the mark is the only completion signal that will ever exist. The
// observer is the REAL consumer: a TaskResult(Succeeded) condition gating a transition to B.
// Latched broadcast (Succeeded) → the SM transitions; clobbered broadcast (Running) → it never
// does. (LastResult itself is deliberately not asserted across frames: post-broadcast
// Running/terminal oscillation is legal by design.)
//
// Surface in Session Frontend: Ck.StateMachine.Task.TerminalResultSurvivesSameFrameTick

#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "Engine/World.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"

#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"
#include "CkTests/Net/CkNetAutomation_Common.h"

#include "CkAutoTest_Sm_LifecycleFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck_sm_task_latch_test
{
    static FCk_Handle_StateMachine GSm;
    static FCk_Handle              GSmOwner;

    auto Reset() -> void
    {
        GSm      = {};
        GSmOwner = {};
        UCk_AutoTest_Sm_SelfClobberTask_UE::MarkSucceededOnNextTick = false;
        UCk_AutoTest_Sm_SelfClobberTask_UE::TickCount = 0;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkStateMachineTask_TerminalResultSurvivesSameFrameTick,
    "Ck.StateMachine.Task.TerminalResultSurvivesSameFrameTick",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::ClientContext | EAutomationTestFlags::EngineFilter)

bool FCkStateMachineTask_TerminalResultSurvivesSameFrameTick::RunTest(const FString& Parameters)
{
    using namespace ck_sm_task_latch_test;

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

            auto Params = FCk_Fragment_StateMachine_ParamsData{UCk_AutoTest_Sm_TaskLatchIdleState_UE::StaticClass()};
            // Defaults: AutoStart OnSetup, DoesNotReplicate.
            GSm = UCk_Utils_StateMachine_UE::Add(GSmOwner, Params);
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("failed to add the SM")); }
        })));

    // The task must be live and ticking (several Running ticks with NO transition) before the
    // race is armed — this also pins "no premature completion broadcast".
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GSm)
                && UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get()
                    == UCk_AutoTest_Sm_TaskLatchIdleState_UE::StaticClass()
                && UCk_AutoTest_Sm_SelfClobberTask_UE::TickCount > 3;
        }),
        8.0,
        TEXT("self-clobber task is live and ticking in the idle state")));

    // Arm the race: the next Tick marks Succeeded then returns Running in the same frame.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_RunOnServer(
        FCk_NetAutoTest_ServerAction::CreateLambda([](UWorld*) -> void
        {
            UCk_AutoTest_Sm_SelfClobberTask_UE::MarkSucceededOnNextTick = true;
        })));

    // Latched broadcast (Succeeded) satisfies the TaskResult condition and drives Idle -> B.
    // A clobbered broadcast (Running) never satisfies it — this WaitUntil times out.
    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_WaitUntil(this,
        FCk_NetAutoTest_Condition::CreateLambda([]() -> bool
        {
            return ck::IsValid(GSm)
                && UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get()
                    == UCk_AutoTest_Sm_RecordingState_B::StaticClass();
        }),
        8.0,
        TEXT("OnSmTaskFinished carried Succeeded (not the clobbered Running) — Idle -> B fired")));

    ADD_LATENT_AUTOMATION_COMMAND(FCk_Latent_AssertCondition(this,
        FCk_NetAutoTest_Assertion::CreateLambda([this]() -> bool
        {
            if (ck::Is_NOT_Valid(GSm))
            { AddError(TEXT("SM handle invalid at final assertion")); return false; }

            TestEqual(TEXT("SM transitioned on the task's terminal broadcast"),
                UCk_Utils_StateMachine_UE::Get_CurrentStateClass(GSm).Get(),
                static_cast<UClass*>(UCk_AutoTest_Sm_RecordingState_B::StaticClass()));
            return true;
        }),
        TEXT("Mark_Result(Succeeded) is not clobbered back to Running before broadcast")));

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
