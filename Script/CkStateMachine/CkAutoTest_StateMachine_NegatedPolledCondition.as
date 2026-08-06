// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: NEGATED POLLED CONDITION INVERTS
//============================================================================
//
// Complements NegatedEventDrivenCondition (which pins that negating an
// event-driven condition keeps it "never fires"). For a POLLED condition,
// negation genuinely inverts the evaluated result: a DoEvaluate that returns
// false, with _NegateResult = true, yields a final Pass and drives the
// transition.
//
// Topology: A -> B, gated by a polled condition that returns false but is
// negated. PASS: the SM transitions A -> B (negate inverted false -> Pass).
//============================================================================

UCLASS()
class UCk_SmNegPolledTest_Cond_FalseNegated : UCk_SmCondition_Polled
{
    default _NegateResult = true;

    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return false; // negated -> Pass
    }
};

UCLASS()
class UCk_SmNegPolledTest_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_SmNegPolledTest_State_B);
        AddCondition(Trans, UCk_SmNegPolledTest_Cond_FalseNegated);
    }
};

UCLASS()
class UCk_SmNegPolledTest_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sink */ }
};

class UCk_AutoTest_StateMachine_NegatedPolledCondition : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_StateMachine_Spec(UCk_SmNegPolledTest_State_A));

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
        if (InPayload.Get_NewStateClass() != UCk_SmNegPolledTest_State_B) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmNegPolledTest_State_B,
            "A negated polled condition returning false should invert to Pass and drive A -> B");
        FinishSuccess();
    }
}
