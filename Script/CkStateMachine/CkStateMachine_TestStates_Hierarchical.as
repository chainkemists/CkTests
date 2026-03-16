// ============================================================================
// HIERARCHICAL STATE MACHINE TEST STATES
// ============================================================================
//
// Tests UCk_SmTask_SubStateMachine: a parent SM that spawns a child SM.
//
// Parent SM:
//   Approach (2s) --> Engage (3s) --> Retreat (2s) --> Approach ...
//                       |
//                       +-- Sub-SM: WindUp (1s) --> Strike (1s) --> Recover (1s) --> WindUp ...
//
// While in Engage, a child SM cycles WindUp -> Strike -> Recover independently.
// When the parent exits Engage, the child SM is destroyed via lifetime cascade.
//
// Features exercised:
//   - UCk_SmTask_SubStateMachine task
//   - Sub-SM creation and lifetime tied to parent state
//   - Context propagation (child SM receives parent's game entity)
//   - Viewer: same-canvas sub-SM rendering (select Engage)
//   - Viewer: drill-down navigation (double-click Engage)
//   - Viewer: breadcrumb navigation back to parent

// ============================================================================
// SUB-SM TASK (configured subclass)
// ============================================================================

// AngelScript subclass that sets the initial state for the sub-SM.
// DoAddTask only takes a class, so we configure via CDO defaults.
UCLASS()
class UCk_SmTest_Hier_SubSmTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmTest_Hier_Child_WindUp;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::KeepRunning;
};

// ============================================================================
// CHILD STATES (Sub-SM)
// ============================================================================

UCLASS()
class UCk_SmTest_Hier_Child_WindUp : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_Hier_Child_Strike);
        DoAddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("  [Child SM] WindUp", n"SmHier", 2.0f, FLinearColor(0.26f, 0.65f, 0.96f));
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Child_Strike : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_Hier_Child_Recover);
        DoAddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("  [Child SM] Strike", n"SmHier", 2.0f, FLinearColor::Red);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Child_Recover : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_Hier_Child_WindUp);
        DoAddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("  [Child SM] Recover", n"SmHier", 2.0f, FLinearColor(0.3f, 0.69f, 0.31f));
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
    }
};

// ============================================================================
// PARENT STATES
// ============================================================================

UCLASS()
class UCk_SmTest_Hier_Parent_Approach : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_Hier_Parent_Engage);
        DoAddCondition(Trans, UCk_SmTest_Condition_AfterDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("[Parent SM] Approach", n"SmHier", 3.0f, FLinearColor(0.0f, 0.5f, 1.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Parent_Engage : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_Hier_Parent_Retreat);
        DoAddCondition(Trans, UCk_SmTest_Condition_PolledTimer);

        DoAddTask(UCk_SmTest_Hier_SubSmTask);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("[Parent SM] Engage (Sub-SM active)", n"SmHier", 3.0f, FLinearColor::Red);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
        ck::Trace("[Parent SM] Exiting Engage (Sub-SM destroyed)", n"SmHier", 2.0f);
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Parent_Retreat : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle& InHandle)
    {
        auto Trans = DoAddTransition(UCk_SmTest_Hier_Parent_Approach);
        DoAddCondition(Trans, UCk_SmTest_Condition_AfterDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateEnter(FCk_Handle InHandle)
    {
        ck::Trace("[Parent SM] Retreat", n"SmHier", 3.0f, FLinearColor(1.0f, 1.0f, 0.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoOnStateExit(FCk_Handle InHandle)
    {
    }
};

// ============================================================================
