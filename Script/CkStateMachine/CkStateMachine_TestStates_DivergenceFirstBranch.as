// ============================================================================
// SM DIVERGENCE-FIRST-BRANCH DUPLICATE-TASK REGRESSION — TEST STATES
// ============================================================================
//
// What this test guards against:
//
// In a sub-SM, when a state has more than one outgoing transition (a
// divergence point), the FIRST-ADDED transition's target state-task chain
// would get constructed *twice* if the chosen branch happened to be the
// first-added one. Two distinct state entities and two distinct task
// entities, both bound to the real context, both firing DoEnterTask. The
// doubling tracks AddTransition order — swap the order of AddTransition
// calls and the doubling follows the new first-added branch. This makes
// per-state side effects (signal broadcasts, attribute writes, request
// enqueues) fire twice and leaves orphaned state entities behind.
//
// Mechanism the test exercises:
//
// 1. A divergence state with two outgoing transitions, gated by polled
//    conditions whose results are pinned by the gym actor (deterministic
//    branch selection — no RNG, no flake).
// 2. The transition order is read from the gym actor at DefineState time,
//    so a single PIE session can run the SM twice with swapped add-orders
//    by toggling AddOrderLeftFirst between Pass A and Pass B.
// 3. Per-state task entities increment a label-keyed counter when their
//    DoEnterTask fires. The bug manifests as a counter reading 2 (instead
//    of 1) for the first-added-and-chosen branch.
//
// Topology:
//
//     Enter -> Idle -> Branch -+-> Left  -> Finish
//                              `-> Right -/
//
// Why both AddTransition orders are exercised:
//
// The bug only doubles when the chosen branch == the first-added branch.
// Pass A pins (AddLeftFirst, ChooseLeft) — would double Left.
// Pass B pins (AddRightFirst, ChooseRight) — would double Right.
// Running both proves the doubling tracks add-order, not the state class
// or the choice direction.
//
// PASS = each per-state task fires exactly once per full traversal,
// regardless of add-order.
// FAIL = first-added-and-chosen branch's task counter == 2.
//
// This variant uses VACUOUS transitions (no conditions on linear hops);
// see the *Timed* variant for a timer-gated equivalent. The two together
// cover both fast-path (vacuous Pass on first evaluation) and timed-path
// (Pass after a delayed event) divergence-point handling.

UENUM()
enum ECk_SmTest_DivergenceFirstBranch_PaymentChoice
{
    Left,
    Right,
}

// ============================================================================
// COUNTER REGISTRY (stateless helpers)
// ============================================================================
//
// Same approach as the graph-walk regression: AS disallows mutable
// namespace globals, so we resolve the (single) live gym actor via
// GetAllActorsOfClass and forward the increment / setting reads. One-actor-
// at-a-time is enforced by the SM gym's PlayerController spawning exactly
// one instance.

namespace SmDivergenceFirstBranch_Regression
{
    void Increment(FName InLabel)
    {
        auto OutActors = TArray<ACk_SmTest_DivergenceFirstBranch_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergenceFirstBranch_GymActor, OutActors);
        for (auto Actor : OutActors)
        { Actor.Increment_Counter(InLabel); }
    }

    bool Get_AddOrderLeftFirst()
    {
        auto OutActors = TArray<ACk_SmTest_DivergenceFirstBranch_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergenceFirstBranch_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.AddOrderLeftFirst; }
        return true;
    }

    ECk_SmTest_DivergenceFirstBranch_PaymentChoice Get_PaymentChoice()
    {
        auto OutActors = TArray<ACk_SmTest_DivergenceFirstBranch_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_DivergenceFirstBranch_GymActor, OutActors);
        for (auto Actor : OutActors)
        { return Actor.PaymentChoice; }
        return ECk_SmTest_DivergenceFirstBranch_PaymentChoice::Left;
    }
}

// ============================================================================
// CONDITIONS
// ============================================================================

// Polled — true when PaymentChoice == Left.
UCLASS()
class UCk_SmTest_Divergence_Condition_PaymentIsLeft : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return SmDivergenceFirstBranch_Regression::Get_PaymentChoice()
            == ECk_SmTest_DivergenceFirstBranch_PaymentChoice::Left;
    }
};

// Polled — true when PaymentChoice == Right.
UCLASS()
class UCk_SmTest_Divergence_Condition_PaymentIsRight : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        auto _CkPerfScope = ck::ScopedStat();
        return SmDivergenceFirstBranch_Regression::Get_PaymentChoice()
            == ECk_SmTest_DivergenceFirstBranch_PaymentChoice::Right;
    }
};

// ============================================================================
// COUNTER TASKS
// ============================================================================
//
// Distinct task class per state — a single shared task class would collapse
// attribution. EnterExitOnly mode: DoEnterTask fires once per state entry.
// Counter increments are observable from the gym actor's Counter_<Label>
// fields; the framework bug shows up as Counter_Left or Counter_Right == 2
// after a single cycle through the divergence (depending on add-order +
// PaymentChoice).

UCLASS()
class UCk_SmTest_Divergence_Task_Enter : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceFirstBranch_Regression::Increment(n"Enter"); }
};

UCLASS()
class UCk_SmTest_Divergence_Task_Idle : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceFirstBranch_Regression::Increment(n"Idle"); }
};

UCLASS()
class UCk_SmTest_Divergence_Task_Branch : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceFirstBranch_Regression::Increment(n"Branch"); }
};

UCLASS()
class UCk_SmTest_Divergence_Task_Left : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceFirstBranch_Regression::Increment(n"Left"); }
};

UCLASS()
class UCk_SmTest_Divergence_Task_Right : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    { SmDivergenceFirstBranch_Regression::Increment(n"Right"); }
};

UCLASS()
class UCk_SmTest_Divergence_Task_Finish : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle, ECk_Sm_NetContext InNetContext)
    {
        auto _CkPerfScope = ck::ScopedStat();
        SmDivergenceFirstBranch_Regression::Increment(n"Finish");

        // Stop the owning sub-SM so the gym's verify pass sees a settled
        // state. The sub-SM task wrapping our Enter state has
        // SucceedOnStop completion behaviour — it bubbles the stop up as
        // task success to the parent SM.
        auto OwningSm = Get_OwningStateMachine();
        if (ck::IsValid(OwningSm))
        { utils_state_machine::Request_Stop(OwningSm); }
    }
};

// ============================================================================
// SUB-SM STATES
// ============================================================================

UCLASS()
class UCk_SmTest_Divergence_State_Enter : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Divergence_Task_Enter);

        // Vacuous transition (no conditions) — passes on first evaluation,
        // so the SM hops Enter -> Idle on the next frame.
        AddTransition(InHandle, UCk_SmTest_Divergence_State_Idle);
    }
};

UCLASS()
class UCk_SmTest_Divergence_State_Idle : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Divergence_Task_Idle);
        AddTransition(InHandle, UCk_SmTest_Divergence_State_Branch);
    }
};

// The divergence point. AddTransition order is read from the gym actor at
// DefineState time so a single PIE session can exercise both orders by
// re-spawning the actor with AddOrderLeftFirst flipped.
//
// Each branch's transition is gated by exactly one polled condition — the
// payment-method check — so the framework picks deterministically. With
// PaymentChoice == Left and AddOrderLeftFirst == true, ToLeft passes
// immediately on Branch entry and the SM transitions to Left. The bug
// shows up as Counter_Left == 2 after the cycle. Flip
// AddOrderLeftFirst to put Right first; if the bug doesn't track the
// add-order swap, it's not the bug we think it is.
UCLASS()
class UCk_SmTest_Divergence_State_Branch : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Divergence_Task_Branch);

        if (SmDivergenceFirstBranch_Regression::Get_AddOrderLeftFirst())
        {
            auto ToLeft = AddTransition(InHandle, UCk_SmTest_Divergence_State_Left);
            AddCondition(ToLeft, UCk_SmTest_Divergence_Condition_PaymentIsLeft);

            auto ToRight = AddTransition(InHandle, UCk_SmTest_Divergence_State_Right);
            AddCondition(ToRight, UCk_SmTest_Divergence_Condition_PaymentIsRight);
        }
        else
        {
            auto ToRight = AddTransition(InHandle, UCk_SmTest_Divergence_State_Right);
            AddCondition(ToRight, UCk_SmTest_Divergence_Condition_PaymentIsRight);

            auto ToLeft = AddTransition(InHandle, UCk_SmTest_Divergence_State_Left);
            AddCondition(ToLeft, UCk_SmTest_Divergence_Condition_PaymentIsLeft);
        }
    }
};

UCLASS()
class UCk_SmTest_Divergence_State_Left : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Divergence_Task_Left);
        AddTransition(InHandle, UCk_SmTest_Divergence_State_Finish);
    }
};

UCLASS()
class UCk_SmTest_Divergence_State_Right : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Divergence_Task_Right);
        AddTransition(InHandle, UCk_SmTest_Divergence_State_Finish);
    }
};

UCLASS()
class UCk_SmTest_Divergence_State_Finish : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Divergence_Task_Finish);
    }
};

// ============================================================================
// SUB-SM WRAPPER — the divergence states are hosted as a sub-SM under a
// parent state. This shape (multi-branch SM running inside a sub-SM task) is
// the configuration where the bug actually surfaces; testing the same states
// as a top-level SM does NOT reproduce it. The wrapper parent-state holds a
// single SubStateMachine task whose initial state is the Enter state above.
// ============================================================================

UCLASS()
class UCk_SmTest_Divergence_SubSmTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmTest_Divergence_State_Enter;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::SucceedOnStop;
};

UCLASS()
class UCk_SmTest_Divergence_ParentState : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        AddTask(InHandle, UCk_SmTest_Divergence_SubSmTask);
    }
};

// ============================================================================
