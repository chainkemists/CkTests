// ============================================================================
// HIERARCHICAL STATE MACHINE TEST STATES
// ============================================================================
//
// Tests UCk_SmTask_SubStateMachine with multiple sub-state machines and a
// complex parent graph for debugger compound-block testing.
//
// Parent SM (6 states, branching):
//
//   Spawn --> Approach --> Engage --> Retreat --> Heal --> Approach ...
//                |           |                     |
//                |           +-- Sub-SM A:         +-- Sub-SM B:
//                |               WindUp->Strike    |   Gather->Channel
//                |               ->Recover->WindUp |   ->Restore->Gather
//                |                                 |
//                +--> Flee (from Approach, short-circuits to Heal)
//
// Sub-SM A (on Engage): Combat cycle — WindUp -> Strike -> Recover -> WindUp
// Sub-SM B (on Heal):   Healing cycle — Gather -> Channel -> Restore -> Gather
//
// Features exercised:
//   - Two separate sub-state machines on different parent states
//   - Branching parent graph (Approach can go to Engage OR Flee)
//   - One parent state (Spawn) with no outgoing sub-SM
//   - Sub-SMs with different topologies and timing
//   - Debugger: compound blocks placed below parent graph, no overlap
//   - Debugger: fade when parent state is inactive
//   - Debugger: cached topology persists across state changes

// ============================================================================
// SUB-SM TASKS (configured subclasses)
// ============================================================================

UCLASS()
class UCk_SmTest_Hier_SubSmTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmTest_Hier_Child_WindUp;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::KeepRunning;
};

UCLASS()
class UCk_SmTest_Hier_HealSubSmTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmTest_Hier_Heal_Gather;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::KeepRunning;
};

// ============================================================================
// CHILD STATES — Sub-SM A (Combat: WindUp -> Strike -> Recover)
// ============================================================================

UCLASS()
class UCk_SmTest_Hier_Child_WindUp : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Child_Strike);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("  [Combat SM] WindUp", n"SmHier", 2.0f, FLinearColor(0.26f, 0.65f, 0.96f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Child_Strike : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Child_Recover);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("  [Combat SM] Strike", n"SmHier", 2.0f, FLinearColor::Red);
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Child_Recover : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Child_WindUp);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("  [Combat SM] Recover", n"SmHier", 2.0f, FLinearColor(0.3f, 0.69f, 0.31f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ============================================================================
// CHILD STATES — Sub-SM B (Healing: Gather -> Channel -> Restore)
// ============================================================================

UCLASS()
class UCk_SmTest_Hier_Heal_Gather : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Heal_Channel);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("  [Heal SM] Gather", n"SmHier", 2.0f, FLinearColor(0.56f, 0.26f, 0.96f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Heal_Channel : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Heal_Restore);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("  [Heal SM] Channel", n"SmHier", 2.0f, FLinearColor(0.96f, 0.26f, 0.96f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Heal_Restore : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Heal_Gather);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("  [Heal SM] Restore", n"SmHier", 2.0f, FLinearColor(0.26f, 0.96f, 0.56f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ============================================================================
// PARENT STATES (6 states, branching graph)
// ============================================================================

UCLASS()
class UCk_SmTest_Hier_Parent_Spawn : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Parent_Approach);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Spawn", n"SmHier", 3.0f, FLinearColor(0.5f, 0.5f, 0.5f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Parent_Approach : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Branch 1: Approach -> Engage (normal flow)
        auto TransEngage = AddTransition(InHandle, UCk_SmTest_Hier_Parent_Engage);
        auto Cond0 = AddCondition(TransEngage, UCk_SmTest_Condition_AfterDelay);

        // Branch 2: Approach -> Flee (short-circuit)
        auto TransFlee = AddTransition(InHandle, UCk_SmTest_Hier_Parent_Flee);
        auto Cond1 = AddCondition(TransFlee, UCk_SmTest_Condition_LongDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Approach", n"SmHier", 3.0f, FLinearColor(0.0f, 0.5f, 1.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Parent_Engage : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Parent_Retreat);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_PolledTimer);

        AddTask(InHandle, UCk_SmTest_Hier_SubSmTask);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Engage (Combat SM active)", n"SmHier", 3.0f, FLinearColor::Red);
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Exiting Engage (Combat SM destroyed)", n"SmHier", 2.0f);
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Parent_Retreat : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Parent_Heal);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_AfterDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Retreat", n"SmHier", 3.0f, FLinearColor(1.0f, 1.0f, 0.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Parent_Heal : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Parent_Approach);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_PolledTimer);

        AddTask(InHandle, UCk_SmTest_Hier_HealSubSmTask);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Heal (Heal SM active)", n"SmHier", 3.0f, FLinearColor(0.3f, 0.9f, 0.3f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Exiting Heal (Heal SM destroyed)", n"SmHier", 2.0f);
    }
};

// ----------------------------------------------------------------------------

UCLASS()
class UCk_SmTest_Hier_Parent_Flee : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Flee short-circuits to Heal
        auto Trans = AddTransition(InHandle, UCk_SmTest_Hier_Parent_Heal);
        auto Cond = AddCondition(Trans, UCk_SmTest_Condition_ShortDelay);
    }

    UFUNCTION(BlueprintOverride)
    void DoEnterState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
        ck::Trace("[Parent SM] Flee!", n"SmHier", 3.0f, FLinearColor(1.0f, 0.4f, 0.0f));
    }

    UFUNCTION(BlueprintOverride)
    void DoExitState(FCk_Handle_SmState InHandle, ECk_Sm_NetContext InNetContext)
    {
    }
};

// ============================================================================
