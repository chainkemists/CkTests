// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: TASK SUCCEEDS DRIVES TRANSITION
//============================================================================
//
// Pins the task lifecycle + task-result condition contract:
//   - State A declares a task that marks itself Succeeded on enter.
//   - A's only transition to B is gated by a Task-Results (aggregate) condition
//     defaulting to AllSucceeded.
//   - When the task succeeds, the condition passes and the SM moves A -> B.
//
// Catches regressions where EnterTask never fires, Mark_Result is ignored, or
// the task-result condition doesn't observe the task's completion.
//============================================================================

UCLASS()
class UCk_SmTaskTest_Task_Succeed : UCk_SmTask_EntityScript
{
    // Tick mode: the task processor calls DoTick each frame and feeds the result
    // into the task's LastResult, broadcasting OnSmTaskFinished. Ticking (vs a
    // one-shot Mark_Result in enter) guarantees the Task-Results condition observes
    // the completion after it has bound to the task, avoiding a missed-broadcast race.
    default _TaskMode = ECk_SmTaskMode::Tick;

    UFUNCTION(BlueprintOverride)
    ECk_SmTaskResult DoTick(FCk_Handle_SmTask InHandle, FCk_Time InDeltaT, ECk_Sm_NetContext InNetContext)
    {
        return ECk_SmTaskResult::Succeeded;
    }
};

UCLASS()
class UCk_SmTaskTest_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTaskTest_Task_Succeed);
        auto Trans = AddTransition(InHandle, UCk_SmTaskTest_State_B);
        AddCondition(Trans, UCk_SmCondition_TaskResults);
    }
};

UCLASS()
class UCk_SmTaskTest_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Sink.
    }
};

class UCk_AutoTest_StateMachine_TaskSucceeds_DrivesTransition : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmTaskTest_State_A));

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }

        // Skip the initial entry into A (PreviousStateClass == nullptr).
        if (InPayload.Get_NewStateClass() != UCk_SmTaskTest_State_B) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmTaskTest_State_B,
            "Task succeeding should drive the SM A -> B via the Task-Results condition");
        FinishSuccess();
    }
}
