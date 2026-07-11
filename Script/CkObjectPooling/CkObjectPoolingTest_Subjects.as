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
