// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: OBJECTPOOL ACTOR ROUND TRIP + VETO
//============================================================================
//
// The ObjectPool sibling of CkAutoTest_EntityPool_ReceiverRoundTrip — the
// synchronous pool for actors. Everything asserts inline (no promises):
//   1. Acquire_Actor auto-creates the pool, spawns the subject actor at the
//      requested transform; the receiver's OnAcquiredFromPool fired with the
//      per-use params (NumAcquired==1, Marker delivered), actor is thawed
//      (collision back to CDO default).
//   2. Release → OnReleasedToPool fired (NumReleased==1), actor frozen
//      (collision off), still alive in the free list.
//   3. Re-Acquire → the SAME actor instance is re-vended (NumAcquired==2).
//   4. Set_CanBePooled(false) + Release → the pool DESTROYS the actor
//      instead of storing it (veto path).
//   5. Final stats: 1 live (the post-veto fresh spawn), 1 hit, 2 misses.
//
// The subject actor binds its receiver in BeginPlay (fires once, at hidden
// pool-spawn) and exposes its counters as plain properties — the synchronous
// API hands the test the typed instance directly.
//============================================================================

class ACk_PoolTest_PooledReceiver_Actor : AActor
{
    // bare AActor has no root — SetActorTransform (the pool's thaw placement) is a silent no-op without one
    UPROPERTY(DefaultComponent, RootComponent)
    USceneComponent Root;

    UPROPERTY()
    FCk_Pool_PoolableReceiver Poolable;

    int32 NumAcquired = 0;
    int32 NumReleased = 0;
    FName LastMarker;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto _CkPerfScope = ck::ScopedStat();
        Poolable.BindTo_OnAcquiredFromPool(
            FCk_Delegate_PoolableReceiver_OnAcquired(this, n"OnAcquiredFromPool"));
        Poolable.BindTo_OnReleasedToPool(
            FCk_Delegate_PoolableReceiver_OnReleased(this, n"OnReleasedToPool"));
    }

    UFUNCTION()
    private void OnAcquiredFromPool(FInstancedStruct InPerUseParams)
    {
        auto _CkPerfScope = ck::ScopedStat();
        NumAcquired++;

        if (!InPerUseParams.IsValid())
        { return; }

        FCk_PoolTest_PerUse Data = InPerUseParams.Get(FCk_PoolTest_PerUse);
        LastMarker = Data.Marker;
    }

    UFUNCTION()
    private void OnReleasedToPool()
    {
        auto _CkPerfScope = ck::ScopedStat();
        NumReleased++;
    }
}

class UCk_AutoTest_ObjectPool_ReceiverActorRoundTripAndVeto : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // --- acquire #1: fresh spawn (miss), receiver fires with per-use params
        FCk_PoolTest_PerUse PerUse;
        PerUse.Marker = n"CkObjectPoolTest.MarkerA";

        auto SpawnAt = FTransform(FVector(100.0f, 200.0f, 300.0f));
        auto Actor = Cast<ACk_PoolTest_PooledReceiver_Actor>(
            utils_object_pool::Acquire_Actor(ACk_PoolTest_PooledReceiver_Actor, SpawnAt, PerUse));

        Assert_True(ck::IsValid(Actor), "Acquire_Actor vended a subject actor");
        if (IsFinished()) { return; }

        Assert_True(UCk_Utils_ObjectPool_UE::Get_IsPooledObject(Actor), "actor is pool-tracked");
        Assert_Equals_Int(Actor.NumAcquired, 1, "receiver OnAcquiredFromPool fired on acquire");
        Assert_True(Actor.LastMarker == n"CkObjectPoolTest.MarkerA", "per-use params delivered through the receiver");
        Assert_True(Actor.GetActorLocation().Equals(FVector(100.0f, 200.0f, 300.0f)), "acquire placed the actor at the requested transform");
        Assert_True(Actor.GetActorEnableCollision(), "acquire thawed the actor (collision restored)");

        // --- release: receiver quiescence hook, then generic freeze; instance stays alive in the free list
        UCk_Utils_ObjectPool_UE::Release(Actor);
        Assert_Equals_Int(Actor.NumReleased, 1, "receiver OnReleasedToPool fired on release");
        Assert_True(!Actor.GetActorEnableCollision(), "release froze the actor (collision off)");
        Assert_True(ck::IsValid(Actor), "released actor is stored, not destroyed");

        // --- acquire #2: pool hit — the SAME instance is re-vended
        FCk_PoolTest_PerUse PerUseB;
        PerUseB.Marker = n"CkObjectPoolTest.MarkerB";
        auto Recycled = Cast<ACk_PoolTest_PooledReceiver_Actor>(
            utils_object_pool::Acquire_Actor(ACk_PoolTest_PooledReceiver_Actor, SpawnAt, PerUseB));

        Assert_True(Recycled == Actor, "second acquire re-vended the same instance");
        Assert_Equals_Int(Actor.NumAcquired, 2, "receiver fired again on re-acquire");
        Assert_True(Actor.LastMarker == n"CkObjectPoolTest.MarkerB", "per-use params of the second acquire delivered");

        // --- veto: CanBePooled=false at release destroys instead of storing
        Actor.Poolable.Set_CanBePooled(false);
        UCk_Utils_ObjectPool_UE::Release(Actor);
        Assert_True(ck::Is_NOT_Valid(Actor), "vetoed release destroyed the instance");

        // --- acquire #3: nothing dormant → fresh spawn
        FCk_PoolTest_PerUse PerUseC;
        PerUseC.Marker = n"CkObjectPoolTest.MarkerC";
        auto Fresh = Cast<ACk_PoolTest_PooledReceiver_Actor>(
            utils_object_pool::Acquire_Actor(ACk_PoolTest_PooledReceiver_Actor, SpawnAt, PerUseC));

        Assert_True(ck::IsValid(Fresh), "post-veto acquire vended a fresh instance");
        if (IsFinished()) { return; }
        Assert_Equals_Int(Fresh.NumAcquired, 1, "fresh instance has no acquire history");
        Assert_Equals_Int(Fresh.NumReleased, 0, "fresh instance has no release history");

        // registry entity: the pool mirrors into the world-level RecordOfObjectPools
        auto FoundRegistryEntity = false;
        for (auto PoolEntity : UCk_Utils_ObjectPool_UE::Get_AllPools())
        {
            if (UCk_Utils_ObjectPool_UE::Get_PoolObjectClass(PoolEntity) == ACk_PoolTest_PooledReceiver_Actor)
            { FoundRegistryEntity = true; break; }
        }
        Assert_True(FoundRegistryEntity, "pool has a registry entity in RecordOfObjectPools carrying its class");

        auto Stats = UCk_Utils_ObjectPool_UE::Get_Stats(ACk_PoolTest_PooledReceiver_Actor);
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1, "veto destroy reconciled the live count");
        Assert_Equals_Int(Stats.Get_NumHits(), 1, "one pool hit (the recycle)");
        Assert_Equals_Int(Stats.Get_NumMisses(), 2, "two misses (initial + post-veto)");

        FinishSuccess();
    }
}
