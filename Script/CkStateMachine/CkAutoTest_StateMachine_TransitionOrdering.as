// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: TASK ORDERING ON TRANSITION
//============================================================================
//
// Verifies that on a state transition, the OLD state's tasks run
// DoExitTask BEFORE the NEW state's tasks run DoEnterTask:
//
//   1. Add SM with State_A as initial. State_A has Task_A; on a short
//      event-driven delay, transitions to State_B (which has Task_B).
//   2. Bind OnStateChanged.
//   3. When the NewStateClass is State_B, read the
//      FCk_Fragment_SmTest_TransitionOrdering events log from the SM
//      entity.
//   4. Verify the order:
//        Events[0] == "EnterTask_A"
//        Events[1] == "ExitTask_A"
//        Events[2] == "EnterTask_B"
//      Critically: ExitTask_A appears BEFORE EnterTask_B.
//
// Reuses the gym's transition-ordering test states from
// CkStateMachine_TestStates_TransitionOrdering.as.
//
// FINDING: OnStateChanged fires BETWEEN ExitTask_A and EnterTask_B, not
// after EnterTask_B. Discovered via this test's first revision (failed
// with 2 events instead of 3). The actual SM event order is:
//   EnterTask_A → ExitTask_A → OnStateChanged signal → EnterTask_B
// So we mark when State_B has been observed via OnStateChanged, then
// poll the events log on subsequent ticks until EnterTask_B has been
// logged.
//============================================================================

class UCk_AutoTest_StateMachine_TransitionOrdering : UCk_AutoTest_Base
{
    private FCk_Handle_StateMachine _SmHandle;
    private bool _StateBObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, UCk_SmTest_Ordering_State_A);

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (InPayload.Get_NewStateClass() == UCk_SmTest_Ordering_State_B)
        {
            _StateBObserved = true;
        }
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (!_StateBObserved) { return; }

        auto SmRaw = _SmHandle.H();
        const auto& Log = SmRaw.Get_Fragment(FCk_Fragment_SmTest_TransitionOrdering);
        if (Log.Events.Num() < 3) { return; }

        Assert_Equals_String(Log.Events[0], "EnterTask_A",
            "First event should be EnterTask_A on initial state entry");
        Assert_Equals_String(Log.Events[1], "ExitTask_A",
            "Second event should be ExitTask_A on transition out of State_A");
        Assert_Equals_String(Log.Events[2], "EnterTask_B",
            "Third event should be EnterTask_B on transition into State_B (AFTER ExitTask_A)");

        FinishSuccess();
    }
}
