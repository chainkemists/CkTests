// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: ON_STATE_CHANGED PAYLOAD OLD + NEW
//============================================================================
//
// Pins the FCk_Sm_Payload_OnStateChanged shape on a real Idle->Patrol
// transition:
//   - Get_PreviousStateClass returns the OLD state class (UCk_SmTest_State_Idle).
//   - Get_NewStateClass returns the NEW state class (UCk_SmTest_State_Patrol).
//
// Note: OnStateChanged fires on the initial state entry too, with
// PreviousStateClass == nullptr (see the existing
// CkAutoTest_StateMachine_TransitionExitBeforeEnter banner for the pattern).
// We filter for the Idle->Patrol transition explicitly so the initial entry
// doesn't confuse the assertion.
//============================================================================

class UCk_AutoTest_StateMachine_OnStateChanged_PayloadHasOldAndNew : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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

        // The initial entry into Idle fires OnStateChanged with no previous state;
        // skip that and wait for the real Idle -> Patrol transition.
        if (InPayload.Get_NewStateClass() != UCk_SmTest_State_Patrol) { return; }

        Assert_True(InPayload.Get_PreviousStateClass() == UCk_SmTest_State_Idle,
            "OnStateChanged payload's Get_PreviousStateClass must report the OLD state class (Idle) on the Idle->Patrol transition");
        Assert_True(InPayload.Get_NewStateClass() == UCk_SmTest_State_Patrol,
            "OnStateChanged payload's Get_NewStateClass must report the NEW state class (Patrol)");

        FinishSuccess();
    }
}
