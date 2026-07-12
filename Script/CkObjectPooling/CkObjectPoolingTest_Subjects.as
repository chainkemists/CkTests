// Language=angelscript

//============================================================================
// CK OBJECT POOLING — TEST SUBJECTS
//============================================================================
//
// Subjects for the CkCore ObjectPooling autotests. The instance-level contract
// (pointer identity across recycle, reset-to-archetype, participant hooks, the
// pin + GC model) is proven on PLAIN pooled UObjects, which the direct pooled
// API (utils_object::Request_CreateNewObject_Pooled / TryReleaseToPool) hands
// back by pointer — no reach-into-the-instance accessor needed.
//
// The EntityScript subjects prove only the POLICY WIRING (poolable -> recycles,
// force-new -> never pools), observed through the public pool-stats surface
// (utils_object::Get_ObjectPoolStats). One subclass per test isolates pool
// stats, since pools are keyed by (class, archetype).
//============================================================================

// Plain pooled object with a participant — the recycle + participant test binds
// the participant delegates on the returned instance and reads Value directly
class UCk_ObjectPoolingTest_PlainObject : UObject
{
    UPROPERTY()
    int32 Value = 0;

    UPROPERTY()
    FCk_Handle_ObjectPoolingParticipant Participant;
}

// Separate class for the pinned + GC test (DestroyOnRelease uses the pinned-unique
// path, not a pool — a distinct class keeps it cleanly isolated regardless)
class UCk_ObjectPoolingTest_PinnedObject : UObject
{
    UPROPERTY()
    int32 Value = 0;
}

// EntityScript, poolable policy — proves recycle wiring via pool stats
class UCk_ObjectPoolingTest_PoolableScript : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity_Poolable;
}

// EntityScript, force-new policy — proves no pool is ever created
class UCk_ObjectPoolingTest_ForceNewScript : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

// Pooled-component subject for the external-destroy (steal) tests — a component because
// DestroyComponent is the one AS-reachable way to externally destroy a pooled plain object
class UCk_ObjectPoolingTest_PooledComponent : UActorComponent
{
    UPROPERTY()
    int32 Value = 0;
}

// Poolable EntityScript that OBSERVES its own recycled state: Construct records the pre-Construct
// Scratch value into an entity variable (a recycled instance must observe the archetype default,
// never the previous incarnation's stomp); BeginPlay marks the entity and stomps Scratch
class UCk_ObjectPoolingTest_TransparencyScript : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity_Poolable;

    UPROPERTY()
    int32 Scratch = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto ObservedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.ObservedScratch");
        utils_variables_int32::Set(InHandle, ObservedTag, Scratch);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto BeginPlayTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.ObjectPooling.SawBeginPlay");
        utils_variables_int32::Set(InHandle, BeginPlayTag, 1);
        Scratch = 99;
    }
}
