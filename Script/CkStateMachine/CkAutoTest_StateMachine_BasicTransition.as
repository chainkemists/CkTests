// Language=angelscript

//============================================================================
// CK STATE MACHINE - AUTOMATION TEST: BASIC TRANSITION
//============================================================================
//
// Smoke test for the state machine framework. Builds the simple Idle ->
// Patrol -> Alert SM (states defined in CkStateMachine_TestStates.as) and
// asserts that the first state transition fires within the timeout.
//
// What this catches if it regresses:
//   - SM construction / Add() failing silently
//   - OnStateChanged signal not binding or never firing
//   - The polled-time condition not advancing
//
// Pattern A (signal-driven, single-shot): bind OnStateChanged, finish on
// the first observed transition.
//============================================================================

class UCk_AutoTest_StateMachine_BasicTransition : UCk_AutoTest_Base
{
    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmTest_State_Idle));

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

        // OnStateChanged also fires on the initial state entry into Idle
        // (NewStateClass == Idle, PreviousStateClass == nullptr). Skip that
        // and wait for the real Idle->Patrol transition.
        if (InPayload.Get_NewStateClass() != UCk_SmTest_State_Patrol) { return; }

        Assert_True(InPayload.Get_NewStateClass() == UCk_SmTest_State_Patrol,
            "First transition from Idle should reach Patrol");
        FinishSuccess();
    }
}
