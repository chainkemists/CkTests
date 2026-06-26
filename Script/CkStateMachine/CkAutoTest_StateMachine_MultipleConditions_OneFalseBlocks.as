// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: MULTIPLE CONDITIONS ARE ANDed
//============================================================================
//
// Pins the AND semantics of multiple conditions on a single transition: a
// transition with two polled conditions (one true, one false) must NOT fire —
// every condition must Pass for the transition to be taken.
//
// Topology: A -> B gated by [PolledTrue, PolledFalse]. Across a settle window
// the SM must remain in A.
//
// PASS: no transition to B observed during the settle window.
//============================================================================

UCLASS()
class UCk_SmMultiCondTest_Cond_True : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const { return true; }
};

UCLASS()
class UCk_SmMultiCondTest_Cond_False : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const { return false; }
};

UCLASS()
class UCk_SmMultiCondTest_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_SmMultiCondTest_State_B);
        AddCondition(Trans, UCk_SmMultiCondTest_Cond_True);
        AddCondition(Trans, UCk_SmMultiCondTest_Cond_False); // AND -> blocks
    }
};

UCLASS()
class UCk_SmMultiCondTest_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink — should not be reached */ }
};

class UCk_AutoTest_StateMachine_MultipleConditions_OneFalseBlocks : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private bool _ReachedB = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmMultiCondTest_State_A));

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
        if (InPayload.Get_NewStateClass() != UCk_SmMultiCondTest_State_B) { return; }

        _ReachedB = true;
        FinishFailure("Transition fired with a false condition present — multiple conditions must all Pass (AND)");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_ReachedB == false,
            "A transition with a failing condition must stay suppressed — SM remains in A");
        FinishSuccess();
    }
}
