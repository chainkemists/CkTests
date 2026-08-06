// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: VACUOUS TRANSITION FIRES IMMEDIATELY
//============================================================================
//
// Pins the zero-condition (vacuous) transition contract: a transition with no
// conditions always evaluates to Pass and fires as soon as the state is
// entered. State A's only transition to B carries no conditions, so the SM
// should move A -> B immediately.
//
// Catches the regression where a guard-less transition is treated as
// Undetermined / never-fires instead of an unconditional Pass.
//============================================================================

UCLASS()
class UCk_SmVacuousTest_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Transition with NO conditions added -> vacuous, always Pass.
        AddTransition(InHandle, UCk_SmVacuousTest_State_B);
    }
};

UCLASS()
class UCk_SmVacuousTest_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // Sink.
    }
};

class UCk_AutoTest_StateMachine_VacuousTransition : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_StateMachine_Spec(UCk_SmVacuousTest_State_A));

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
        if (InPayload.Get_NewStateClass() != UCk_SmVacuousTest_State_B) { return; }

        Assert_True(InHandle.Get_CurrentStateClass() == UCk_SmVacuousTest_State_B,
            "A zero-condition (vacuous) transition should fire immediately, moving A -> B");
        FinishSuccess();
    }
}
