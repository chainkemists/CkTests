// Language=angelscript

//============================================================================
// CK STATE MACHINE — NET SUB-SM TICK-GATED PROGRESSION (topology only)
//============================================================================
//
// Topology authored in AngelScript because DoDefineState is a
// BlueprintImplementableEvent (no C++ override). Driven by the C++ spec
// Ck.StateMachine.Net.OwningClientAuth_SubSmTickGated, which bridges an
// OwningClientAuthoritative + Replicates parent SM onto a client-possessed
// pawn (initial state = UCk_SmNetSubTest_Parent_Hold, resolved by path).
//
//   Parent_Hold [ SubTask -> sub-SM ]                       (KeepRunning)
//     sub-SM:  Sub_Wait [ Delay 0.3s ] --(TaskResults)--> Sub_Reached
//
// The sub-SM advances ONLY through the tick-gated Delay task. The sub-SM
// entity is created detached from the pawn, so it carries no owning-actor
// fragment: before FFragment_Sm_NetIdentity it misresolved to NonOwningClient
// on the owning client, FProcessor_SmTask_Tick gated the Delay off, and
// Sub_Wait never completed. With the SubStateMachine task stamping the parent's
// resolved identity onto the sub-SM, it resolves OwningClient /
// OwningClientAuthoritative on the owning client, the Delay ticks, and the
// sub-SM reaches Sub_Reached.
//
// The parent never transitions (KeepRunning, no parent transition) so the test
// stays surgical to the sub-SM net-identity fix and never enqueues a
// replicated-SM transition. The sub-SM is DoesNotReplicate, so its own
// Sub_Wait -> Sub_Reached transition is self-authoritative on every machine and
// never touches the authority gate. The spec asserts the OWNING CLIENT's sub-SM
// reaches Sub_Reached.
//============================================================================

UCLASS()
class UCk_SmNetSubTest_DelayShort : UCk_SmTask_Delay
{
    default _Duration = FCk_Time(0.3f);
}

UCLASS()
class UCk_SmNetSubTest_Sub_Reached : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle) { /* sub-SM sink */ }
}

UCLASS()
class UCk_SmNetSubTest_Sub_Wait : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        AddTask(InHandle, UCk_SmNetSubTest_DelayShort);
        auto Trans = AddTransition(InHandle, UCk_SmNetSubTest_Sub_Reached);
        AddCondition(Trans, UCk_SmCondition_TaskResults); // default AllSucceeded
    }
}

UCLASS()
class UCk_SmNetSubTest_SubTask : UCk_SmTask_SubStateMachine
{
    default _InitialStateClass = UCk_SmNetSubTest_Sub_Wait;
    default _CompletionBehavior = ECk_SmTask_SubSm_CompletionBehavior::KeepRunning;
}

UCLASS()
class UCk_SmNetSubTest_Parent_Hold : UCk_SmState_EntityScript
{
    UFUNCTION(BlueprintOverride)
    void DoDefineState(FCk_Handle_SmState_UnderConstruction& InHandle)
    {
        // Host the sub-SM; the parent intentionally has no outgoing transition — the
        // assertion reads the sub-SM's current state directly.
        AddTask(InHandle, UCk_SmNetSubTest_SubTask);
    }
}
