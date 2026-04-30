// ============================================================================
// SM EVENT-DRIVEN MULTI-CONDITION — REGRESSION TEST STATES
// ============================================================================
//
// Guards the "event-driven condition Pass results are preserved across
// transition Reset cycles" invariant. A transition with multiple event-
// driven conditions must fire exactly when ALL of them resolve Pass, even
// when those events resolve at different times — and even though the
// state evaluator's Fail/Reset cycle runs many iterations between the
// first and last events arriving.
//
// Topology:
//
//     Idle -> Finish    (one transition, TWO event-driven conditions)
//
// Conditions:
//   - FastEvent (timer): MarkSatisfied at FastDelaySeconds (~0.1s).
//   - SlowEvent (timer): MarkSatisfied at SlowDelaySeconds (~0.4s).
//
// Sequence of interest:
//   t=0    : Idle entered. Both conds Fail (auto-Fail resting state).
//            transition.Evaluate sees Fail → trans Fail. state.Evaluate
//            cycles trans through Reset.
//   t≈0.1s : FastEvent → MarkSatisfied. Cond Pass.
//            transition.Evaluate walks: FastEvent Pass → SlowEvent Fail
//            (still) → trans Fail. State keeps cycling.
//   t≈0.1–0.4s : multiple Reset cycles. FastEvent's Pass MUST be
//            preserved across these cycles (event-driven cond results
//            stick across Reset by framework design).
//   t≈0.4s : SlowEvent → MarkSatisfied. Cond Pass.
//            transition.Evaluate walks: both Pass → trans Pass → fire.
//            SM transitions to Finish.
//
// PASS criterion: Counter_Finish == 1 (SM transitioned exactly once).
// FAIL: Counter_Finish == 0 means FastEvent's Pass got clobbered during
//       the Reset cycle, so when SlowEvent eventually fired the transition
//       still saw a Fail condition (the previously-Pass FastEvent) and
//       never resolved to Pass.

namespace SmEventDrivenMultiCondition_Registry
{
    void Increment_Finish()
    {
        auto OutActors = TArray<ACk_SmTest_EventDrivenMultiCondition_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_EventDrivenMultiCondition_GymActor, OutActors);
        for (auto Actor : OutActors)
        { Actor.Counter_Finish += 1; }
    }

    float Get_FastDelaySeconds()
    {
        auto OutActors = TArray<ACk_SmTest_EventDrivenMultiCondition_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_EventDrivenMultiCondition_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.FastDelaySeconds; }
        return 0.1f;
    }

    float Get_SlowDelaySeconds()
    {
        auto OutActors = TArray<ACk_SmTest_EventDrivenMultiCondition_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_EventDrivenMultiCondition_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.SlowDelaySeconds; }
        return 0.4f;
    }
}

// ============================================================================
// CONDITIONS — both are event-driven timer gates that arm at EnterCondition
// and call MarkSatisfied when their timer fires. Different delays so they
// resolve at different points in the Reset cycle.
// ============================================================================

UCLASS()
class UCk_SmTest_EventDrivenMultiCondition_Condition_FastEvent : UCk_SmCondition_EventDriven
{
    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle)
    {
        auto Delay = SmEventDrivenMultiCondition_Registry::Get_FastDelaySeconds();
        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(Delay));
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
class UCk_SmTest_EventDrivenMultiCondition_Condition_SlowEvent : UCk_SmCondition_EventDriven
{
    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle)
    {
        auto Delay = SmEventDrivenMultiCondition_Registry::Get_SlowDelaySeconds();
        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(Delay));
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

// ============================================================================
// COUNTER TASK — bumps the Finish counter on entry to the terminal state.
// ============================================================================

UCLASS()
class UCk_SmTest_EventDrivenMultiCondition_Task_Finish : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmEventDrivenMultiCondition_Registry::Increment_Finish(); }
};

// ============================================================================
// STATES
// ============================================================================

UCLASS()
class UCk_SmTest_EventDrivenMultiCondition_State_Finish : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    { AddTask(InHandle, UCk_SmTest_EventDrivenMultiCondition_Task_Finish); }
};

UCLASS()
class UCk_SmTest_EventDrivenMultiCondition_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Single transition with TWO event-driven conditions. The transition
        // must fire exactly once — when both conditions have resolved Pass.
        // The framework's contract is that event-driven conditions preserve
        // their last-known result across transition Reset (so FastEvent's
        // Pass survives the cycling between t=0.1s and t=0.4s).
        auto ToFinish = AddTransition(InHandle, UCk_SmTest_EventDrivenMultiCondition_State_Finish);
        AddCondition(ToFinish, UCk_SmTest_EventDrivenMultiCondition_Condition_FastEvent);
        AddCondition(ToFinish, UCk_SmTest_EventDrivenMultiCondition_Condition_SlowEvent);
    }
};

// ============================================================================
