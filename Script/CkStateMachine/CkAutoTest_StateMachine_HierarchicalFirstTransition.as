// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: HIERARCHICAL SM FIRST TRANSITION
//============================================================================
//
// Verifies a state machine with hierarchical (sub-state-machine) parent
// states constructs cleanly and progresses past its initial state.
//
//   1. Add an SM with UCk_SmTest_Hier_Parent_Spawn as the initial state.
//      The full graph (defined in CkStateMachine_TestStates_Hierarchical.as)
//      reaches sub-SM-bearing parent states (Engage, Heal) further along.
//   2. Bind OnStateChanged.
//   3. Expect the first transition to reach Approach (the linear successor
//      to Spawn).
//
// This is the hierarchical analogue of CkAutoTest_StateMachine_BasicTransition:
// it doesn't drive the sub-SM activation specifically, but it proves that
// adding an SM that *contains* sub-SM tasks elsewhere in the graph does not
// regress the basic Add/initial-transition path.
//============================================================================

class UCk_AutoTest_StateMachine_HierarchicalFirstTransition : UCk_AutoTest_Base
{
    private FCk_Handle_StateMachine _SmHandle;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_Fragment_StateMachine_ParamsData(UCk_SmTest_Hier_Parent_Spawn));

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

        // OnStateChanged fires for the initial Spawn entry too — skip that
        // and wait for the real Spawn->Approach transition.
        if (InPayload.Get_NewStateClass() != UCk_SmTest_Hier_Parent_Approach) { return; }

        Assert_True(InPayload.Get_NewStateClass() == UCk_SmTest_Hier_Parent_Approach,
            "First transition from Spawn in the hierarchical SM should reach Approach");
        FinishSuccess();
    }
}
