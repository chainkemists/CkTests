// ============================================================================
// COMPLEX STATE MACHINE TEST STATES
// ============================================================================

// A richer state machine for stress-testing the HFSM Viewer:
//
//   Spawn --> Idle <------------- Flee
//              |  ^                 ^
//              v  |                 |
//           Patrol ---> Chase -----+
//              |          |
//              v          v
//           Search     Attack
//              |          |
//              +----+-----+--> (back to Idle via timeout)
//
// Features exercised:
//   - 6 states with branching transitions
//   - Bidirectional transitions (Idle <-> Patrol)
//   - Multiple conditions per transition (Chase -> Attack)
//   - Polled conditions (evaluated every frame)
//   - Event-driven conditions (timer-based)
//   - Tasks (Tick mode + EnterExit mode)
//   - Configurable delay via condition default property

// ============================================================================
// CONDITIONS
// ============================================================================

// Polled condition that becomes true after enough time has elapsed.
// Uses world time to avoid needing mutable state in DoEvaluate.
UCLASS()
class UCk_SmTest_Condition_PolledTimer : UCk_SmCondition_Polled
{
    UPROPERTY(EditAnywhere)
    float32 DurationSeconds = 3.0f;

    float64 StartTime = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        StartTime = System::GetGameTimeInSeconds();
    }

    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return System::GetGameTimeInSeconds() - StartTime >= DurationSeconds;
    }
};

// ----------------------------------------------------------------------------

// Event-driven condition with configurable delay.
UCLASS()
class UCk_SmTest_Condition_ShortDelay : UCk_SmCondition_EventDriven
{
    UPROPERTY(EditAnywhere)
    float32 DelaySeconds = 1.0f;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TimerParams = FCk_Timer_Spec(FCk_Time(DelaySeconds));
        TimerParams
            .Set_StartingState(ECk_Timer_State::Running)
            .Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        auto Timer = utils_timer::Add(InHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDelayElapsed"));
    }

    UFUNCTION()
    private void OnDelayElapsed(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        auto OwnerSm = Get_OwningStateMachine();
        if (!ck::IsValid(OwnerSm))
        { return; }

        if (OwnerSm.Get_RunStatus() == ECk_SmRunStatus::Paused)
        {
            utils_timer::Request_Reset(InTimer);
            utils_timer::Request_Resume(InTimer);
            return;
        }

        MarkSatisfied();
    }
};

// ----------------------------------------------------------------------------

// Event-driven condition with a long delay — used for timeout/fallback transitions.
UCLASS()
class UCk_SmTest_Condition_LongDelay : UCk_SmCondition_EventDriven
{
    UPROPERTY(EditAnywhere)
    float32 DelaySeconds = 4.0f;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TimerParams = FCk_Timer_Spec(FCk_Time(DelaySeconds));
        TimerParams
            .Set_StartingState(ECk_Timer_State::Running)
            .Set_Behavior(ECk_Timer_Behavior::PauseOnDone);

        auto Timer = utils_timer::Add(InHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnDelayElapsed"));
    }

    UFUNCTION()
    private void OnDelayElapsed(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        auto OwnerSm = Get_OwningStateMachine();
        if (!ck::IsValid(OwnerSm))
        { return; }

        if (OwnerSm.Get_RunStatus() == ECk_SmRunStatus::Paused)
        {
            utils_timer::Request_Reset(InTimer);
            utils_timer::Request_Resume(InTimer);
            return;
        }

        MarkSatisfied();
    }
};

// ----------------------------------------------------------------------------

// Always-true polled condition — used as a second condition in multi-condition transitions.
UCLASS()
class UCk_SmTest_Condition_AlwaysTrue : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return true;
    }
};

// ============================================================================
// TASKS
// ============================================================================

// Tick task — simulates an ongoing behavior (e.g. navigation, animation).
// Reports Running for a few seconds, then Succeeded.
UCLASS()
class UCk_SmTest_Task_TimedWork : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::Tick;

    UPROPERTY(EditAnywhere)
    float32 WorkDuration = 2.0f;

    float32 ElapsedTime = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ElapsedTime = 0.0f;
    }

    UFUNCTION(BlueprintOverride)
    ECk_SmTaskResult DoTick(FCk_Handle_SmTask InHandle, FCk_Time InDeltaT, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ElapsedTime += float32(InDeltaT.Get_Seconds());

        if (ElapsedTime >= WorkDuration)
        {
            return ECk_SmTaskResult::Succeeded;
        }

        return ECk_SmTaskResult::Running;
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// ----------------------------------------------------------------------------

// EnterExit-only task — fires once on enter and once on exit (no ticking).
UCLASS()
class UCk_SmTest_Task_LogOnly : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// ============================================================================
// STATES
// ============================================================================

// --- IDLE ---
// Two outgoing transitions:
//   1. Idle -> Patrol (short delay — fires first)
//   2. Idle -> Chase  (polled timer — lower priority)
UCLASS()
class UCk_SmTest_Complex_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ToPatrol = AddTransition(InHandle, UCk_SmTest_Complex_State_Patrol);
        auto Cond0 = AddCondition(ToPatrol, UCk_SmTest_Condition_ShortDelay);

        auto ToChase = AddTransition(InHandle, UCk_SmTest_Complex_State_Chase);
        auto Cond1 = AddCondition(ToChase, UCk_SmTest_Condition_PolledTimer);

        AddTask(InHandle, UCk_SmTest_Task_LogOnly);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ck::Trace("Complex SM: Entered IDLE", n"SmTest", 3.0f, FLinearColor::Blue);
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// --- PATROL ---
// Three outgoing transitions:
//   1. Patrol -> Chase  (short delay — fires first)
//   2. Patrol -> Idle   (polled timer — bidirectional back to Idle)
//   3. Patrol -> Search (long delay — fallback)
// Has two tasks (ticking + enter/exit).
UCLASS()
class UCk_SmTest_Complex_State_Patrol : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ToChase = AddTransition(InHandle, UCk_SmTest_Complex_State_Chase);
        auto Cond0 = AddCondition(ToChase, UCk_SmTest_Condition_ShortDelay);

        auto ToIdle = AddTransition(InHandle, UCk_SmTest_Complex_State_Idle);
        auto Cond1 = AddCondition(ToIdle, UCk_SmTest_Condition_PolledTimer);

        auto ToSearch = AddTransition(InHandle, UCk_SmTest_Complex_State_Search);
        auto Cond2 = AddCondition(ToSearch, UCk_SmTest_Condition_LongDelay);

        AddTask(InHandle, UCk_SmTest_Task_TimedWork);
        AddTask(InHandle, UCk_SmTest_Task_LogOnly);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ck::Trace("Complex SM: Entered PATROL", n"SmTest", 3.0f, FLinearColor::Green);
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// --- CHASE ---
// Two outgoing transitions:
//   1. Chase -> Attack (requires TWO conditions: short delay AND always-true)
//   2. Chase -> Flee   (long delay — escape timeout)
// Has a ticking task.
UCLASS()
class UCk_SmTest_Complex_State_Chase : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ToAttack = AddTransition(InHandle, UCk_SmTest_Complex_State_Attack);
        auto Cond0 = AddCondition(ToAttack, UCk_SmTest_Condition_ShortDelay);
        auto Cond1 = AddCondition(ToAttack, UCk_SmTest_Condition_AlwaysTrue);

        auto ToFlee = AddTransition(InHandle, UCk_SmTest_Complex_State_Flee);
        auto Cond2 = AddCondition(ToFlee, UCk_SmTest_Condition_LongDelay);

        AddTask(InHandle, UCk_SmTest_Task_TimedWork);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ck::Trace("Complex SM: Entered CHASE", n"SmTest", 3.0f, FLinearColor(1.0f, 0.5f, 0.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// --- ATTACK ---
// Single outgoing transition:
//   Attack -> Idle (short delay — return to idle after attacking)
// Has two tasks.
UCLASS()
class UCk_SmTest_Complex_State_Attack : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ToIdle = AddTransition(InHandle, UCk_SmTest_Complex_State_Idle);
        auto Cond = AddCondition(ToIdle, UCk_SmTest_Condition_ShortDelay);

        AddTask(InHandle, UCk_SmTest_Task_TimedWork);
        AddTask(InHandle, UCk_SmTest_Task_LogOnly);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ck::Trace("Complex SM: Entered ATTACK", n"SmTest", 3.0f, FLinearColor::Red);
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// --- SEARCH ---
// Single outgoing transition:
//   Search -> Idle (short delay — give up and return)
// Has a ticking task.
UCLASS()
class UCk_SmTest_Complex_State_Search : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ToIdle = AddTransition(InHandle, UCk_SmTest_Complex_State_Idle);
        auto Cond = AddCondition(ToIdle, UCk_SmTest_Condition_ShortDelay);

        AddTask(InHandle, UCk_SmTest_Task_TimedWork);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ck::Trace("Complex SM: Entered SEARCH", n"SmTest", 3.0f, FLinearColor(0.5f, 0.0f, 1.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// --- FLEE ---
// Single outgoing transition:
//   Flee -> Idle (short delay — recover and return)
UCLASS()
class UCk_SmTest_Complex_State_Flee : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto ToIdle = AddTransition(InHandle, UCk_SmTest_Complex_State_Idle);
        auto Cond = AddCondition(ToIdle, UCk_SmTest_Condition_ShortDelay);

        AddTask(InHandle, UCk_SmTest_Task_LogOnly);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        ck::Trace("Complex SM: Entered FLEE", n"SmTest", 3.0f, FLinearColor(1.0f, 1.0f, 0.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
    }
};

// ============================================================================
