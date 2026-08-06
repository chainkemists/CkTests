// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: POLLED CONDITION DRIVES TRANSITION
//============================================================================
//
// Pins the polled-condition evaluation path (FProcessor_SmCondition_Polled):
// a UCk_SmCondition_Polled subclass whose DoEvaluate returns true is evaluated
// each frame and, on Pass, drives the gated transition A -> B.
//
// Distinct from the vacuous-transition test (which has no condition at all) and
// from the event-driven AlwaysTrue test (which uses the event-driven path):
// this exercises the polled processor specifically.
//============================================================================

UCLASS()
class UCk_SmPolledTest_Cond_Pass : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return true;
    }
};

UCLASS()
class UCk_SmPolledTest_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Trans = AddTransition(InHandle, UCk_SmPolledTest_State_B);
        AddCondition(Trans, UCk_SmPolledTest_Cond_Pass);
    }
};

UCLASS()
class UCk_SmPolledTest_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Sink.
    }
};

class UCk_AutoTest_StateMachine_PolledCondition_DrivesTransition : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_StateMachine_Spec(UCk_SmPolledTest_State_A));

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
        if (InPayload.Get_NewStateClass() != UCk_SmPolledTest_State_B) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmPolledTest_State_B,
            "A passing polled condition should drive the SM A -> B");
        FinishSuccess();
    }
}
