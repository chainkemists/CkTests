// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: TASK FAILURE SUPPRESSES TRANSITION
//============================================================================
//
// Complement to TaskSucceeds_DrivesTransition. A Tick-mode task that returns
// Failed must NOT satisfy an AllSucceeded Task-Results condition, so the gated
// transition A -> B never fires and the SM stays in A.
//
// PASS criterion: across a settle window the SM never transitions to B.
//============================================================================

UCLASS()
class UCk_SmTaskFailTest_Task_Fail : UCk_SmTask_EntityScript
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
class UCk_SmTaskFailTest_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTaskFailTest_Task_Fail);
        auto Trans = AddTransition(InHandle, UCk_SmTaskFailTest_State_B);
        AddCondition(Trans, UCk_SmCondition_TaskResults); // default AllSucceeded
    }
};

UCLASS()
class UCk_SmTaskFailTest_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Sink — should never be reached.
    }
};

class UCk_AutoTest_StateMachine_TaskFailure_NoTransition : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private bool _ReachedB = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmTaskFailTest_State_A));

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5f));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto SettleTimer = utils_timer::Add(LocalHandle, SettleParams);
        SettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (InPayload.Get_NewStateClass() != UCk_SmTaskFailTest_State_B) { return; }

        _ReachedB = true;
        FinishFailure("SM transitioned to B despite the task Failing — AllSucceeded must not be satisfied by a failed task");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_ReachedB == false,
            "A failed task must leave the AllSucceeded transition suppressed — SM stays in A");
        FinishSuccess();
    }
}
