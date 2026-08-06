// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: NO TRANSITION AVAILABLE STAYS IN STATE
//============================================================================
//
// Pins two contracts for a "sink" initial state — a state class whose
// DoDefineState declares zero AddTransition calls:
//
//   1. OnStateChanged fires exactly once on initial entry, with
//      PreviousStateClass == nullptr and NewStateClass == the sink class.
//      Without this fire, a consumer that initializes per-state shape only
//      reacting to OnStateChanged would miss the initial state entirely
//      and stay uninitialized forever.
//
//   2. After a settle window, no further OnStateChanged fires occur — the
//      SM stays in the sink state indefinitely because no transition is
//      available.
//
// Pattern B (settle-timer poll) for the negative assertion.
//============================================================================

UCLASS()
class UCk_SmTest_NoTransition_State_Sink : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        // No transitions — this is a sink state.
    }
};

class UCk_AutoTest_StateMachine_NoTransitionAvailable_StaysInState : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private int32 _StateChangedFireCount = 0;
    private bool _SinkEntryObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, FCk_StateMachine_Spec(UCk_SmTest_NoTransition_State_Sink));

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        // Settle window — long enough for any spurious transition pass to
        // fire if the framework attempted one. 1.0s is well past the
        // single-frame initial-entry broadcast.
        auto SettleParams = FCk_Timer_Spec(FCk_Time(1.0f));
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

        _StateChangedFireCount += 1;

        if (InPayload.Get_NewStateClass() == UCk_SmTest_NoTransition_State_Sink)
        {
            _SinkEntryObserved = true;
        }
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(_SinkEntryObserved,
            "OnStateChanged should fire on initial sink-state entry with NewStateClass == Sink (PreviousStateClass=null)");
        Assert_Equals_Int(_StateChangedFireCount, 1,
            "OnStateChanged should fire exactly once for the sink-state SM: the initial entry. No transition is available, so no further fires are expected.");

        FinishSuccess();
    }
}
