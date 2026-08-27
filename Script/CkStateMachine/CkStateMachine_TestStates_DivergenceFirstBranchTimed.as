// ============================================================================
// SM DIVERGENCE-FIRST-BRANCH (TIMED) - REGRESSION TEST STATES
// ============================================================================
//
// What this test guards against:
//
// The same divergence-point duplicate-task bug as the *vacuous* variant
// (CkStateMachine_TestStates_DivergenceFirstBranch.as), but exercised
// through a timer-gated transition pattern. Every linear hop here uses an
// event-driven timer condition (transition Pass'es ~50ms after the source
// state is entered), so the duplicate-creation race window opens around
// timer-driven Pass results rather than around vacuous Pass results. This
// is the configuration that originally surfaced the bug in real product
// code, where transitions were gated by dwell timers rather than firing
// vacuously.
//
// Why two variants exist:
//
// - Vacuous variant: transition has zero conditions. Transition_Evaluate
//   returns Pass on the first evaluation. The race window between the
//   transition firing and the source state being torn down is one frame.
// - Timed variant (this one): transition has an event-driven timer
//   condition. The timer's OnDone fires later, then the transition
//   evaluates Pass. The race window is wider in wall-clock time but the
//   logical sequence (state Pending-Exit -> condition still alive ->
//   transition still cached as Pass -> state re-evaluates) is the same.
//
// Both variants run the same divergence-point shape and assertions.
// Together they cover both fast-path and slow-path Pass-cache handling
// during state teardown.
//
// Topology:
//
//     Enter -> Idle -> Branch -+-> Left  -> Finish
//                              `-> Right -/
//
// Each linear transition: gated by FastDelay (timer condition).
// Each divergence transition: FastDelay AND a polled payment-method check
// - gives the SM a deterministic single-branch Pass at the divergence.
//
// PASS criterion: each per-state task fires exactly once per sub-SM cycle,
// regardless of AddTransition order.
// FAIL: first-added-and-chosen branch's task fires twice (cached Pass
// result on the dying source state's transition fires Request_Transition
// a second time).

UENUM()
enum ECk_SmTest_DivergenceTimed_PaymentChoice
{
    Left,
    Right,
}

// ============================================================================
// COUNTER REGISTRY (stateless - same pattern as graph-walk regression)
// ============================================================================

namespace SmDivergenceTimed_Regression
{
    void Increment(FName InLabel)
    {
        auto OutActors = TArray<ACk_SmTest_DivergenceTimed_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergenceTimed_GymActor, OutActors);
        for (auto Actor : OutActors)
        { Actor.Increment_Counter(InLabel); }
    }

    bool Get_AddOrderLeftFirst()
    {
        auto OutActors = TArray<ACk_SmTest_DivergenceTimed_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergenceTimed_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.AddOrderLeftFirst; }
        return true;
    }

    ECk_SmTest_DivergenceTimed_PaymentChoice Get_PaymentChoice()
    {
        auto OutActors = TArray<ACk_SmTest_DivergenceTimed_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergenceTimed_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.PaymentChoice; }
        return ECk_SmTest_DivergenceTimed_PaymentChoice::Left;
    }
}

// ============================================================================
// CONDITIONS
// ============================================================================

// Event-driven timer condition. On EnterCondition it arms a CkTimer for
// DelaySeconds; when the timer's OnDone fires, MarkSatisfied flips the
// condition to Pass. This is the canonical "wait a moment, then proceed"
// transition gate - used by every linear hop in this test SM so each
// transition's Pass result is established asynchronously (mirroring how
// real game-code transitions tend to be timed rather than vacuous).
//
// Default delay is small (0.05s) so a full sub-SM cycle (Enter -> Idle ->
// Branch -> chosen -> Finish, 4-5 transitions) completes in ~0.25s, well
// inside the gym's settle window.
UCLASS()
class UCk_SmTest_DivergenceTimed_Condition_FastDelay : UCk_SmCondition_EventDriven
{
    UPROPERTY(EditAnywhere)
    float32 DelaySeconds = 0.05f;

    UFUNCTION(BlueprintOverride)
    void DoEnterCondition(FCk_Handle_SmCondition InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(DelaySeconds));
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
        MarkSatisfied();
    }
};

// Polled - true when PaymentChoice == Left.
UCLASS()
class UCk_SmTest_DivergenceTimed_Condition_PaymentIsLeft : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return SmDivergenceTimed_Regression::Get_PaymentChoice()
            == ECk_SmTest_DivergenceTimed_PaymentChoice::Left;
    }
};

// Polled - true when PaymentChoice == Right.
UCLASS()
class UCk_SmTest_DivergenceTimed_Condition_PaymentIsRight : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return SmDivergenceTimed_Regression::Get_PaymentChoice()
            == ECk_SmTest_DivergenceTimed_PaymentChoice::Right;
    }
};

// ============================================================================
// COUNTER TASKS (EnterExitOnly)
// ============================================================================

UCLASS()
class UCk_SmTest_DivergenceTimed_Task_Enter : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceTimed_Regression::Increment(n"Enter"); }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_Task_Idle : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceTimed_Regression::Increment(n"Idle"); }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_Task_Branch : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceTimed_Regression::Increment(n"Branch"); }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_Task_Left : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceTimed_Regression::Increment(n"Left"); }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_Task_Right : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceTimed_Regression::Increment(n"Right"); }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_Task_Finish : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        SmDivergenceTimed_Regression::Increment(n"Finish");

        // Stop the owning sub-SM so the gym sees a settled state and can
        // verify counters. The wrapping UCk_SmTest_DivergenceTimed_SubSmTask
        // uses SucceedOnStop completion behaviour.
        auto OwningSm = Get_OwningStateMachine();
        if (ck::IsValid(OwningSm))
        { utils_state_machine::Request_Stop(OwningSm); }
    }
};

// ============================================================================
// SUB-SM STATES - every linear transition gated by FastDelay (timed Pass).
// The divergence transitions additionally have a polled payment-method
// check so exactly one branch wins deterministically.
// ============================================================================

UCLASS()
class UCk_SmTest_DivergenceTimed_State_Enter : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_DivergenceTimed_Task_Enter);

        auto ToIdle = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Idle);
        AddCondition(ToIdle, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
    }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_DivergenceTimed_Task_Idle);

        auto ToBranch = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Branch);
        AddCondition(ToBranch, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
    }
};

// The divergence point - state with two outgoing transitions. AddTransition
// order is read from the gym actor at DefineState time so a single PIE
// session can exercise both orders by re-spawning the SM with a swapped
// flag. Each branch is gated by FastDelay (so it Pass'es timed, not
// vacuously) AND a polled payment-method check (so exactly one wins).
UCLASS()
class UCk_SmTest_DivergenceTimed_State_Branch : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_DivergenceTimed_Task_Branch);

        if (SmDivergenceTimed_Regression::Get_AddOrderLeftFirst())
        {
            auto ToLeft = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Left);
            AddCondition(ToLeft, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
            AddCondition(ToLeft, UCk_SmTest_DivergenceTimed_Condition_PaymentIsLeft);

            auto ToRight = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Right);
            AddCondition(ToRight, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
            AddCondition(ToRight, UCk_SmTest_DivergenceTimed_Condition_PaymentIsRight);
        }
        else
        {
            auto ToRight = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Right);
            AddCondition(ToRight, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
            AddCondition(ToRight, UCk_SmTest_DivergenceTimed_Condition_PaymentIsRight);

            auto ToLeft = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Left);
            AddCondition(ToLeft, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
            AddCondition(ToLeft, UCk_SmTest_DivergenceTimed_Condition_PaymentIsLeft);
        }
    }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_State_Left : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_DivergenceTimed_Task_Left);

        auto ToFinish = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Finish);
        AddCondition(ToFinish, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
    }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_State_Right : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_DivergenceTimed_Task_Right);

        auto ToFinish = AddTransition(InHandle, UCk_SmTest_DivergenceTimed_State_Finish);
        AddCondition(ToFinish, UCk_SmTest_DivergenceTimed_Condition_FastDelay);
    }
};

UCLASS()
class UCk_SmTest_DivergenceTimed_State_Finish : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_DivergenceTimed_Task_Finish);
    }
};

// ============================================================================
// SUB-SM WRAPPER
// ============================================================================

UCLASS()
class UCk_SmTest_DivergenceTimed_SubSmTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmTest_DivergenceTimed_State_Enter;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::SucceedOnStop;
};

UCLASS()
class UCk_SmTest_DivergenceTimed_ParentState : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_DivergenceTimed_SubSmTask);
    }
};

// ============================================================================
