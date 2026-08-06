// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: TRANSITION EXIT BEFORE ENTER
//============================================================================
//
// Verifies the framework invariant: on a transition, the OLD state's
// tasks must run DoExitTask BEFORE the NEW state's tasks run DoEnterTask.
//
// Without this guarantee, any consumer that uses task lifecycle to manage
// a shared resource (refcount, exclusive lock, audio handle, etc.) sees
// stale state interleaved with fresh state. The shelf outline in
// BusterBlock hit this exact issue — an old task's Hide ran AFTER the new
// task's Show, dropping the shared source out of the Set on every click.
//
// The test:
//   1. Adds StateA -> StateB SM to the test entity.
//   2. Waits for OnStateChanged to fire (the A->B transition).
//   3. After a short settling window (allowing pump passes to drain old
//      state's task exits and new state's task enters), reads the
//      FCk_Fragment_SmTest_TransitionOrdering.Events array and asserts
//      ExitTask_A appears BEFORE EnterTask_B.
//============================================================================

class UCk_AutoTest_StateMachine_TransitionExitBeforeEnter : UCk_AutoTest_Base
{
    private FCk_Handle_StateMachine _SmHandle;
    private FCk_Handle _TestEntity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _TestEntity = InHandle;
        auto LocalHandle = InHandle;

        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_StateMachine_Spec(UCk_SmTest_Ordering_State_A));

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished())
        { return; }

        // We only care about the A -> B transition. Initial start fires
        // OnStateChanged too (with PreviousStateClass == nullptr), so gate
        // on the target class explicitly.
        if (InPayload.Get_NewStateClass() != UCk_SmTest_Ordering_State_B)
        { return; }

        // Allow a brief settling window so all pump passes drain — the OLD
        // state's task exit and the NEW state's task enter must both have
        // landed in the Events array before we read it.
        System::SetTimer(this, n"VerifyOrdering", 0.5f, false);
    }

    UFUNCTION()
    private void VerifyOrdering()
    {
        if (IsFinished())
        { return; }

        if (_TestEntity.Has_Fragment(FCk_Fragment_SmTest_TransitionOrdering) == false)
        {
            FinishFailure("Ordering log fragment missing — test states never recorded any events");
            return;
        }

        const auto& Log = _TestEntity.Get_Fragment(FCk_Fragment_SmTest_TransitionOrdering);

        int32 ExitA_Idx = -1;
        int32 EnterB_Idx = -1;
        for (int i = 0; i < Log.Events.Num(); ++i)
        {
            if (Log.Events[i] == "ExitTask_A")  { ExitA_Idx = i; }
            if (Log.Events[i] == "EnterTask_B") { EnterB_Idx = i; }
        }

        // Build a single readable string of recorded events for the failure messages.
        FString EventsDump = "";
        for (int i = 0; i < Log.Events.Num(); ++i)
        {
            if (i > 0) { EventsDump += ", "; }
            EventsDump += Log.Events[i];
        }

        Assert_True(ExitA_Idx >= 0,
            f"ExitTask_A was never recorded — events: [{EventsDump}]");
        Assert_True(EnterB_Idx >= 0,
            f"EnterTask_B was never recorded — events: [{EventsDump}]");

        if (ExitA_Idx >= 0 && EnterB_Idx >= 0)
        {
            Assert_True(ExitA_Idx < EnterB_Idx,
                f"OLD state's task DoExitTask must run BEFORE NEW state's task DoEnterTask " +
                f"(got ExitTask_A at index {ExitA_Idx}, EnterTask_B at index {EnterB_Idx}). " +
                f"Events: [{EventsDump}]");
        }

        FinishSuccess();
    }
}
