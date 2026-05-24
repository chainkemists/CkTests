// ============================================================================
// SM RACING EVENT-DRIVEN TRANSITIONS — REGRESSION TEST STATES
// ============================================================================
//
// What this test guards against:
//
// FProcessor_SmState_Evaluate walks a state's outgoing transitions in
// declaration order and Break's the moment it sees an Undetermined transition,
// activating that transition's evaluation but never inspecting any later
// sibling. When two event-driven transitions race on the same state, a later
// transition that has already resolved Pass is silently ignored if any
// earlier transition is still Undetermined — and worse, with the bug present
// the second transition's condition never gets activated at all (its timer
// never starts), so the slow-first transition wins by default at its delay.
//
// Topology:
//
//     Idle -+-> DestA   (event-driven timer, slow — added FIRST)
//           `-> DestB   (event-driven timer, fast — added SECOND, should win)
//
// Both transitions are pure event-driven timer conditions. With the fix in
// place, every Undetermined sibling is activated each evaluation pass; the
// fast timer fires first and ToDestB Pass'es first → DestB wins. Without
// the fix, only ToDestA's evaluation ever begins; ToDestA Pass'es at its
// (slower) delay → DestA wins.
//
// PASS criterion: SM lands on DestB exactly once.
// FAIL: SM lands on DestA (the first-declared, slower transition that
//        blocked the evaluator).

namespace SmRacing_Registry
{
    void Increment_DestA()
    {
        auto OutActors = TArray<ACk_SmTest_RacingEventDriven_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_RacingEventDriven_GymActor, OutActors);
        for (auto Actor : OutActors)
        { Actor.Counter_DestA += 1; }
    }

    void Increment_DestB()
    {
        auto OutActors = TArray<ACk_SmTest_RacingEventDriven_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_RacingEventDriven_GymActor, OutActors);
        for (auto Actor : OutActors)
        { Actor.Counter_DestB += 1; }
    }

    float Get_SlowDelaySeconds()
    {
        auto OutActors = TArray<ACk_SmTest_RacingEventDriven_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_RacingEventDriven_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.SlowDelaySeconds; }
        return 0.5f;
    }

    float Get_FastDelaySeconds()
    {
        auto OutActors = TArray<ACk_SmTest_RacingEventDriven_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_RacingEventDriven_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.FastDelaySeconds; }
        return 0.1f;
    }
}

// ============================================================================
// CONDITIONS — event-driven timer Pass after a delay sourced from the gym
// actor (so a single set of state classes can be reused by both the visual
// gym station with watchable timing and the headless autotest with fast
// timing).
// ============================================================================

UCLASS()
class UCk_SmTest_Racing_Condition_SlowTimer : UCk_SmCondition_EventDriven
{
    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto Delay = SmRacing_Registry::Get_SlowDelaySeconds();
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
class UCk_SmTest_Racing_Condition_FastTimer : UCk_SmCondition_EventDriven
{
    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto Delay = SmRacing_Registry::Get_FastDelaySeconds();
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
// COUNTER TASKS
// ============================================================================

UCLASS()
class UCk_SmTest_Racing_Task_DestA : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmRacing_Registry::Increment_DestA(); }
};

UCLASS()
class UCk_SmTest_Racing_Task_DestB : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmRacing_Registry::Increment_DestB(); }
};

// ============================================================================
// STATES
// ============================================================================

UCLASS()
class UCk_SmTest_Racing_State_DestA : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    { AddTask(InHandle, UCk_SmTest_Racing_Task_DestA); }
};

UCLASS()
class UCk_SmTest_Racing_State_DestB : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    { AddTask(InHandle, UCk_SmTest_Racing_Task_DestB); }
};

UCLASS()
class UCk_SmTest_Racing_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // ORDER MATTERS — ToDestA is declared first. With the bug, the state
        // evaluator hits ToDestA's Undetermined transition first, Break's,
        // and never inspects ToDestB. After the fix, every Undetermined
        // sibling is activated each pass and the first Pass wins; ToDestB
        // Pass'es first (faster timer) so it should be the chosen branch.
        auto ToDestA = AddTransition(InHandle, UCk_SmTest_Racing_State_DestA);
        AddCondition(ToDestA, UCk_SmTest_Racing_Condition_SlowTimer);

        auto ToDestB = AddTransition(InHandle, UCk_SmTest_Racing_State_DestB);
        AddCondition(ToDestB, UCk_SmTest_Racing_Condition_FastTimer);
    }
};

// ============================================================================
