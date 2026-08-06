// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: TASK-RESULTS AnyFailed CHECK
//============================================================================
//
// Pins the AnyFailed aggregate variant of the Task-Results condition: with two
// tasks on a state (one Succeeds, one Fails), a condition configured with
// _Check = AnyFailed is satisfied (failed count > 0) and drives the transition.
// Complements the default AllSucceeded coverage.
//============================================================================

UCLASS()
class UCk_SmAnyFailTest_Cond : UCk_SmCondition_TaskResults
{
    default _Check = ECk_SmCondition_TaskResultsCheck::AnyFailed;
};

UCLASS()
class UCk_SmAnyFailTest_Task_Good : UCk_SmTask_EntityScript
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
class UCk_SmAnyFailTest_Task_Bad : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::Tick;

    UFUNCTION(BlueprintOverride)
    ECk_SmTaskResult DoTick(FCk_Handle_SmTask InHandle, FCk_Time InDeltaT, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        return ECk_SmTaskResult::Failed;
    }
};

UCLASS()
class UCk_SmAnyFailTest_State_Start : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmAnyFailTest_Task_Good);
        AddTask(InHandle, UCk_SmAnyFailTest_Task_Bad);
        auto Trans = AddTransition(InHandle, UCk_SmAnyFailTest_State_Done);
        AddCondition(Trans, UCk_SmAnyFailTest_Cond);
    }
};

UCLASS()
class UCk_SmAnyFailTest_State_Done : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink */ }
};

class UCk_AutoTest_StateMachine_TaskResults_AnyFailed : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_StateMachine_Spec(UCk_SmAnyFailTest_State_Start));

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
        if (InPayload.Get_NewStateClass() != UCk_SmAnyFailTest_State_Done) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmAnyFailTest_State_Done,
            "AnyFailed should be satisfied by the failing task and drive Start -> Done");
        FinishSuccess();
    }
}
