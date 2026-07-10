// Language=angelscript

//============================================================================
// CK POOL — TEST SUBJECT (pooled EntityScript)
//============================================================================
//
// The pooled instance for the CkPool AutoTests (CkTests). Opts into pooling hooks via
// an FCk_Pool_PoolableReceiver property (the AS-reachable path — AS cannot
// implement ICk_ObjectPool_Poolable) and records evidence the tests can read
// through public API only.
//
// Evidence rides CkVariables (Set/Get are IMMEDIATE — same-frame readable
// from the acquire promise; CkEntityTag Add is deferred and would not be).
// Variable slots are the AutoTest.Pool.* gameplay tags (auto-registered by
// ResolveGameplayTag in-editor — "Added via code" — no ini shipping needed):
//   - int32 AutoTest.Pool.NumAcquired / NumReleased prove the receiver hooks
//     fired (counts → recycling proof).
//   - FName AutoTest.Pool.LastMarker proves per-use params flow through the
//     receiver.
//   - VetoNextRelease flips _CanBePooled, exercising the release-time veto.
//============================================================================

struct FCk_PoolTest_PerUse
{
    UPROPERTY()
    FName Marker;

    UPROPERTY()
    bool VetoNextRelease = false;
}

class UCk_PoolTest_PooledReceiver_EntityScript : UCk_GenericEntityScript_UE
{
    // EntityPool v1 requirement
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY()
    FCk_Pool_PoolableReceiver Poolable;

    // authored-template probe for archetype pools: an archetype instance overrides this and pooled
    // instances constructed from it must inherit the value (class CDO default is 0)
    UPROPERTY()
    int32 ArchetypeMarker = 0;

    // injection target: per-use payloads carrying a 'Marker' field stomp this property on every
    // acquire (spawn-param injection semantics) — published separately from the payload's Marker
    UPROPERTY()
    FName Marker;

    private FCk_Handle MyEntity;
    private int32 _NumAcquired = 0;
    private int32 _NumReleased = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        MyEntity = InHandle;

        Poolable.BindTo_OnAcquiredFromPool(
            FCk_Delegate_PoolableReceiver_OnAcquired(this, n"OnAcquiredFromPool"));
        Poolable.BindTo_OnReleasedToPool(
            FCk_Delegate_PoolableReceiver_OnReleased(this, n"OnReleasedToPool"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    UFUNCTION()
    private void OnAcquiredFromPool(FInstancedStruct InPerUseParams)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _NumAcquired++;

        auto E = MyEntity;
        utils_variables_int32::Set(E, utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Pool.NumAcquired"), _NumAcquired);
        utils_variables_int32::Set(E, utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Pool.ArchetypeMarker"), ArchetypeMarker);
        utils_variables_name::Set(E, utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Pool.InjectedMarker"), Marker);

        if (!InPerUseParams.IsValid())
        { return; }

        FCk_PoolTest_PerUse Data = InPerUseParams.Get(FCk_PoolTest_PerUse);

        utils_variables_name::Set(E, utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Pool.LastMarker"), Data.Marker);

        if (Data.VetoNextRelease)
        { Poolable.Set_CanBePooled(false); }
    }

    UFUNCTION()
    private void OnReleasedToPool()
    {
        auto _CkPerfScope = ck::ScopedStat();
        _NumReleased++;

        auto E = MyEntity;
        utils_variables_int32::Set(E, utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Pool.NumReleased"), _NumReleased);
    }
}

// Default pools are keyed by exact class — one subclass per test isolates pool state
// (hit/miss stats, live instances) even if tests ever share a PIE world
class UCk_PoolTest_PooledReceiverRoundTrip_EntityScript : UCk_PoolTest_PooledReceiver_EntityScript {}
class UCk_PoolTest_PooledReceiverVeto_EntityScript : UCk_PoolTest_PooledReceiver_EntityScript {}

// Dedicated subject for the perf-comparison test — its own class = its own isolated pool,
// keeping timings uncontaminated by the functional tests' pools
class UCk_PoolTest_PerfSubject_EntityScript : UCk_PoolTest_PooledReceiver_EntityScript {}

// Dedicated subject for the grow-batch test — isolated pool
class UCk_PoolTest_GrowBatchSubject_EntityScript : UCk_PoolTest_PooledReceiver_EntityScript {}

// Dedicated subject for the demand-ramp stress test — isolated pool
class UCk_PoolTest_RampSubject_EntityScript : UCk_PoolTest_PooledReceiver_EntityScript {}

// Dedicated subject for the per-use property-injection test — isolated pool
class UCk_PoolTest_InjectSubject_EntityScript : UCk_PoolTest_PooledReceiver_EntityScript {}
