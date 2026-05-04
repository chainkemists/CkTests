// Language=angelscript

//============================================================================
// CK STATE MACHINE — AUTOMATION TEST: NEGATED EVENT-DRIVEN CONDITION
//============================================================================
//
// Pins the negate-of-event-driven contract from CkStateMachine/CLAUDE.md
// (Event-driven condition resting state -> Trade-offs):
//
//   Negation (`_NegateResult = true`) of an event-driven condition keeps its
//   prior "never fires" semantic. The Fail resting state is set via
//   Request_UpdateConditionResult directly, not via MarkUnsatisfied — so the
//   resting value isn't inverted. After the event fires, MarkSatisfied with
//   negate still maps to Fail, so the transition still doesn't fire.
//
// Topology:
//   Idle -> Finish, condition = NegatedAfterDelay (delay 0.1s, negate=true).
//
//   At t=0:    Condition resting state = Fail.        Transition not taken.
//   At t=0.1:  MarkSatisfied with _NegateResult=true → Fail.  Still no take.
//   At t=Settle (0.5s): SM should still be in Idle. NEVER transitioned.
//
// PASS criterion: OnStateChanged was NEVER fired during the settle window.
//   (Gym-style settle-timer poll, Pattern B.)
//
// FAIL: SM transitioned to Finish (negate semantic broken — MarkSatisfied
//   under negate is mapping to Pass instead of Fail).
//============================================================================

UCLASS()
class UCk_SmTest_Negated_Condition_AfterDelay : UCk_SmCondition_EventDriven
{
    default _NegateResult = true;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle)
    {
        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.1f));
        TimerParams
            .Set_StartingState(ECk_Timer_State::Running)
            .Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        auto Timer = utils_timer::Add(InHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDelayElapsed"));
    }

    UFUNCTION()
    private void OnDelayElapsed(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    { MarkSatisfied(); }
};

UCLASS()
class UCk_SmTest_Negated_State_Finish : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    { /* terminal, no transitions */ }
};

UCLASS()
class UCk_SmTest_Negated_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Negated_State_Finish);
        AddCondition(Trans, UCk_SmTest_Negated_Condition_AfterDelay);
    }
};

class UCk_AutoTest_StateMachine_NegatedEventDrivenCondition : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private FCk_Handle_StateMachine _SmHandle;
    private bool _StateChangeObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _SmHandle = UCk_Utils_StateMachine_UE::Add(LocalHandle, UCk_SmTest_Negated_State_Idle);

        FCk_Delegate_Sm_OnStateChanged Delegate;
        Delegate.BindUFunction(this, n"OnStateChanged");
        _SmHandle.BindTo_OnStateChanged(Delegate);

        // Settle window of 0.5s — well past the 0.1s timer that fires
        // MarkSatisfied. If negation maps Pass back to Fail correctly, the
        // transition will never fire, OnStateChanged will never run, and
        // we'll FinishSuccess on settle. If negate semantic is broken,
        // OnStateChanged fires before settle and the test fails fast.
        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5f));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto SettleTimer = utils_timer::Add(LocalHandle, SettleParams);
        SettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSettled"));
    }

    UFUNCTION()
    private void OnStateChanged(
        FCk_Handle_StateMachine InSmHandle,
        FCk_Sm_Payload_OnStateChanged InPayload)
    {
        if (IsFinished()) { return; }
        _StateChangeObserved = true;
        FinishFailure("SM transitioned despite negated event-driven condition — negate Pass→Fail mapping is broken. Transition fired when it should never fire.");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Assert_True(_StateChangeObserved == false,
            "Negated event-driven condition must keep transition suppressed — OnStateChanged should NEVER have fired.");
        FinishSuccess();
    }
}
