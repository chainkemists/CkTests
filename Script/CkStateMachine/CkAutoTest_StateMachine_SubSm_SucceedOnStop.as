// Language=angelscript

//============================================================================
// CK STATE MACHINE - AUTOMATION TEST: SUB-SM SUCCEEDS-ON-STOP DRIVES PARENT
//============================================================================
//
// Pins the sub-state-machine completion contract: a UCk_SmTask_SubStateMachine
// configured with _CompletionBehavior = SucceedOnStop marks itself Succeeded
// when its sub-SM stops, which satisfies the parent state's Task-Results
// (AllSucceeded) condition and drives the parent transition.
//
// Topology:
//   Parent_Run [SubTask -> sub-SM(Sub_Final)] --(TaskResults AllSucceeded)--> Parent_Done
//   Sub_Final: on enter, stops its own sub-SM (Get_OwnerStateMachine + Request_Stop).
//
// Flow: Parent_Run enters -> SubTask spawns + starts the sub-SM at Sub_Final ->
// Sub_Final stops the sub-SM -> SubTask (SucceedOnStop) marks Succeeded ->
// AllSucceeded satisfied -> Parent_Run -> Parent_Done.
//
// PASS: parent reaches Parent_Done.
//============================================================================

UCLASS()
class UCk_SmSubTest_Sub_Final : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sub-SM sink */ }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Defer the self-stop by a frame via a short timer. Stopping synchronously on enter makes
        // the whole spawn->start->stop->task-succeed->parent-transition cascade resolve in a single
        // frame, which trips the SM's High-pump-count(>8) warning (escalated to a test failure).
        // The timer splits the cascade across frames so no single frame exceeds the pump budget.
        System::SetTimer(this, n"OnStopDelay", 0.1f, false);
    }

    UFUNCTION()
    private void OnStopDelay()
    {
        auto OwnerSm = Get_OwnerStateMachine();
        if (ck::IsValid(OwnerSm))
        { utils_state_machine::Request_Stop(OwnerSm); }
    }
};

UCLASS()
class UCk_SmSubTest_SubTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmSubTest_Sub_Final;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::SucceedOnStop;
};

UCLASS()
class UCk_SmSubTest_Parent_Run : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmSubTest_SubTask);
        auto Trans = AddTransition(InHandle, UCk_SmSubTest_Parent_Done);
        AddCondition(Trans, UCk_SmCondition_TaskResults); // default AllSucceeded
    }
};

UCLASS()
class UCk_SmSubTest_Parent_Done : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink */ }
};

class UCk_AutoTest_StateMachine_SubSm_SucceedOnStop : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmSubTest_Parent_Run));

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
        if (InPayload.Get_NewStateClass() != UCk_SmSubTest_Parent_Done) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmSubTest_Parent_Done,
            "Sub-SM SucceedOnStop should satisfy the parent's AllSucceeded condition and drive Parent_Run -> Parent_Done");
        FinishSuccess();
    }
}
