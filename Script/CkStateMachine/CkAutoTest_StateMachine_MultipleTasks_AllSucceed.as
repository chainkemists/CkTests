// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: MULTIPLE TASKS, ALL SUCCEED
//============================================================================
//
// Pins the multi-task aggregate contract: a state with TWO Tick-mode tasks both
// reporting Succeeded satisfies the AllSucceeded Task-Results condition, driving
// A -> B. Catches regressions where the aggregate only observes one task, or the
// bound-task count is miscomputed.
//============================================================================

UCLASS()
class UCk_SmMultiTask_Task_A : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::Tick;

    UFUNCTION(BlueprintOverride)
    ECk_SmTaskResult DoTick(FCk_Handle_SmTask InHandle, FCk_Time InDeltaT, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        return ECk_SmTaskResult::Succeeded;
    }
};

UCLASS()
class UCk_SmMultiTask_Task_B : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::Tick;

    UFUNCTION(BlueprintOverride)
    ECk_SmTaskResult DoTick(FCk_Handle_SmTask InHandle, FCk_Time InDeltaT, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        return ECk_SmTaskResult::Succeeded;
    }
};

UCLASS()
class UCk_SmMultiTask_State_Start : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmMultiTask_Task_A);
        AddTask(InHandle, UCk_SmMultiTask_Task_B);
        auto Trans = AddTransition(InHandle, UCk_SmMultiTask_State_Done);
        AddCondition(Trans, UCk_SmCondition_TaskResults); // default AllSucceeded
    }
};

UCLASS()
class UCk_SmMultiTask_State_Done : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Sink.
    }
};

class UCk_AutoTest_StateMachine_MultipleTasks_AllSucceed : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmMultiTask_State_Start));

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
        if (InPayload.Get_NewStateClass() != UCk_SmMultiTask_State_Done) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmMultiTask_State_Done,
            "Both tasks succeeding should satisfy AllSucceeded and drive Start -> Done");
        FinishSuccess();
    }
}
