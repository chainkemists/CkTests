// ============================================================================
// SM GRAPH-WALK GHOST-TASK REGRESSION — TEST STATES
// ============================================================================
//
// Guards CkFoundation PR #643. The debug graph-walk processor
// (FProcessor_Sm_Debug_GraphWalk, guarded by CK_BUILD_SM_GRAPH_WALK —
// defined for editor/development builds) constructs temp state / condition /
// task entities at SM-add time to cache the reachable graph for the HFSM
// viewer. Those temp entities are stamped with FTag_Sm_Debug_GraphWalkEntity;
// UCk_Sm*_EntityScript::BeginPlay short-circuits on that tag so their
// Enter* bodies never run.
//
// Without the short-circuit, every reachable state's task DoEnterTask fires
// at construction. Side-effecting tasks (signal broadcasts, Request_Stop on
// the owning SM — see UBb_Hfsm_Task_TerminateOwningSm) then corrupt real
// state before the SM has started.
//
// This file defines a 5-state linear chain A -> B -> C -> D -> E gated by a
// polled-false condition (the real SM never advances past A). Each state's
// task increments a label-keyed counter on DoEnterTask. If the short-circuit
// regresses, counters B..E become nonzero at construction and the gym's
// station reports FAIL. A terminal-state Request_Stop variant is used on E
// in the sub-SM build so a regression additionally stops the real sub-SM
// immediately — matching the original CheckoutCounter failure mode.
//
// In non-graph-walk builds (CK_BUILD_SM_GRAPH_WALK=0) this test trivially
// passes since no ghost entities are ever created. The regression guard
// only has teeth in editor/development.

// ============================================================================
// COUNTER REGISTRY (stateless helpers)
// ============================================================================
//
// AngelScript disallows mutable namespace globals, so counter state lives as
// a TMap<FName,int32> UPROPERTY on ACk_SmTest_GraphWalkRegression_GymActor.
// Tasks call SmGraphWalk_Regression::Increment(Label) — this resolves the
// (single) live gym actor via GetAllActorsOfClass and forwards to its
// Increment_Counter method. One-gym-actor-at-a-time is enforced by the SM
// gym's GameMode spawning exactly one instance.

namespace SmGraphWalk_Regression
{
    void Increment(FName InLabel)
    {
        auto OutActors = TArray<ACk_SmTest_GraphWalkRegression_GymActor>();
        GetAllActorsOfClass(ACk_SmTest_GraphWalkRegression_GymActor, OutActors);
        for (auto Actor : OutActors)
        { Actor.Increment_Counter(InLabel); }
    }
}

// ============================================================================
// POLLED-FALSE CONDITION
// ============================================================================

// DoEvaluate returns false unconditionally — no real transition can ever fire.
// The real SM stays in its initial state forever; any counter increment
// beyond the initial state is proof of a graph-walk ghost regression.
UCLASS()
class UCk_SmTest_Condition_PolledFalse : UCk_SmCondition_Polled
{
    UFUNCTION(BlueprintOverride)
    bool DoEvaluate(FCk_Handle_SmCondition InHandle, FCk_Time InDeltaT) const
    {
        return false;
    }
};

// ============================================================================
// COUNTER TASKS — TOP-LEVEL SM (EnterExitOnly)
// ============================================================================
//
// Distinct classes per state (not one parameterised class). The graph-walk
// processor instantiates a temp entity per task-in-state; reusing a single
// class across all five states would collapse attribution — any increment
// could have come from any ghost. Distinct classes preserve per-state
// attribution so a FAIL report pinpoints which ghost(s) ran.

UCLASS()
class UCk_SmTest_Task_EnterCount_Top_A : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"TopA"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

UCLASS()
class UCk_SmTest_Task_EnterCount_Top_B : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"TopB"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

UCLASS()
class UCk_SmTest_Task_EnterCount_Top_C : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"TopC"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

UCLASS()
class UCk_SmTest_Task_EnterCount_Top_D : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"TopD"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

// Terminal state task for the top-level SM — Request_Stop on the owning SM.
// This is the sharpest regression signal: if a ghost runs, the real SM dies
// at construction and the station's OnSmStopped handler fires before the
// first Verify() tick.
UCLASS()
class UCk_SmTest_Task_RequestStopOwning_Top : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    {
        SmGraphWalk_Regression::Increment(n"TopStopE");

        auto OwningSm = Get_OwningStateMachine();
        if (ck::IsValid(OwningSm))
        { utils_state_machine::Request_Stop(OwningSm); }

        Mark_Result(ECk_SmTaskResult::Succeeded);
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

// ============================================================================
// COUNTER TASKS — SUB-SM
// ============================================================================

UCLASS()
class UCk_SmTest_Task_EnterCount_Sub_A : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"SubA"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

UCLASS()
class UCk_SmTest_Task_EnterCount_Sub_B : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"SubB"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

UCLASS()
class UCk_SmTest_Task_EnterCount_Sub_C : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"SubC"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

UCLASS()
class UCk_SmTest_Task_EnterCount_Sub_D : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    { SmGraphWalk_Regression::Increment(n"SubD"); }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

UCLASS()
class UCk_SmTest_Task_RequestStopOwning_Sub : UCk_SmTask_EntityScript
{
    default _TaskMode = ECk_SmTaskMode::EnterExitOnly;

    UFUNCTION(BlueprintOverride)
    void DoEnterTask(FCk_Handle_SmTask InHandle)
    {
        SmGraphWalk_Regression::Increment(n"SubStopE");

        auto OwningSm = Get_OwningStateMachine();
        if (ck::IsValid(OwningSm))
        { utils_state_machine::Request_Stop(OwningSm); }

        Mark_Result(ECk_SmTaskResult::Succeeded);
    }

    UFUNCTION(BlueprintOverride)
    void DoExitTask(FCk_Handle_SmTask InHandle) {}
};

// ============================================================================
// TOP-LEVEL LINEAR CHAIN: A -> B -> C -> D -> E
// ============================================================================
//
// Every transition is gated by PolledFalse, so the real SM stays in A
// forever. Per-state tasks record entry in the counter registry. State E
// uses RequestStopOwning so a ghost-run tests both the counter signal and
// the owning-SM-stopped signal.

UCLASS()
class UCk_SmTest_GraphWalk_Top_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToB = AddTransition(InHandle, UCk_SmTest_GraphWalk_Top_State_B);
        auto Cond = AddCondition(ToB, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Top_A);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

UCLASS()
class UCk_SmTest_GraphWalk_Top_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToC = AddTransition(InHandle, UCk_SmTest_GraphWalk_Top_State_C);
        auto Cond = AddCondition(ToC, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Top_B);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

UCLASS()
class UCk_SmTest_GraphWalk_Top_State_C : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToD = AddTransition(InHandle, UCk_SmTest_GraphWalk_Top_State_D);
        auto Cond = AddCondition(ToD, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Top_C);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

UCLASS()
class UCk_SmTest_GraphWalk_Top_State_D : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToE = AddTransition(InHandle, UCk_SmTest_GraphWalk_Top_State_E);
        auto Cond = AddCondition(ToE, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Top_D);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

// Terminal state: no outgoing transitions, RequestStopOwning task. If
// ghost-run regresses, this stops the real SM at construction.
UCLASS()
class UCk_SmTest_GraphWalk_Top_State_E : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_Task_RequestStopOwning_Top);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

// ============================================================================
// SUB-SM LINEAR CHAIN: A -> B -> C -> D -> E
// ============================================================================
//
// Same topology as the top-level chain, different task classes so attribution
// (top vs sub) survives a regression. Wrapped by the parent state below via
// UCk_SmTask_SubStateMachine.

UCLASS()
class UCk_SmTest_GraphWalk_Sub_State_A : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToB = AddTransition(InHandle, UCk_SmTest_GraphWalk_Sub_State_B);
        auto Cond = AddCondition(ToB, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Sub_A);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

UCLASS()
class UCk_SmTest_GraphWalk_Sub_State_B : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToC = AddTransition(InHandle, UCk_SmTest_GraphWalk_Sub_State_C);
        auto Cond = AddCondition(ToC, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Sub_B);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

UCLASS()
class UCk_SmTest_GraphWalk_Sub_State_C : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToD = AddTransition(InHandle, UCk_SmTest_GraphWalk_Sub_State_D);
        auto Cond = AddCondition(ToD, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Sub_C);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

UCLASS()
class UCk_SmTest_GraphWalk_Sub_State_D : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto ToE = AddTransition(InHandle, UCk_SmTest_GraphWalk_Sub_State_E);
        auto Cond = AddCondition(ToE, UCk_SmTest_Condition_PolledFalse);

        AddTask(InHandle, UCk_SmTest_Task_EnterCount_Sub_D);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

UCLASS()
class UCk_SmTest_GraphWalk_Sub_State_E : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_Task_RequestStopOwning_Sub);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

// ============================================================================
// SUB-SM WRAPPER — parent state hosting the sub-SM as a SubStateMachine task
// ============================================================================

UCLASS()
class UCk_SmTest_GraphWalk_SubSmTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmTest_GraphWalk_Sub_State_A;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::KeepRunning;
};

// Parent wrapper state for the sub-SM variant. Polled-false self-loop would
// require a second state, so we keep this as a terminal state holding only
// the SubStateMachine task — the parent SM stays here indefinitely while
// the sub-SM is the system under test.
UCLASS()
class UCk_SmTest_GraphWalk_SubSmWrapper_State : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmTest_GraphWalk_SubSmTask);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext) {}
};

// ============================================================================
