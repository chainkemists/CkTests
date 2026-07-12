// Language=angelscript
//
// CK OBJECT POOLING — AUTOMATION TEST: bounded capacity + Fail exhaustion contracts
//
// Bounded/Grow: the pool creates up to MaxSize live instances, then acquire returns null (no
// ensure — capacity is an expected runtime condition) until something is released. Fail: an empty
// pool never creates on demand — acquire returns null and counts a miss.

class UCk_AutoTest_ObjectPooling_BoundedCapacityAndFailExhaustion : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // ---- Bounded / Grow, MaxSize 2 (own pool via dedicated archetype) ----
        auto BoundedArchetype = Cast<UCk_ObjectPoolingTest_PlainObject>(
            NewObject(this, UCk_ObjectPoolingTest_PlainObject));

        auto BoundedParams = FCk_ObjectPooling_PoolParams();
        BoundedParams.Set_CapacityPolicy(ECk_ObjectPooling_CapacityPolicy::Bounded);
        BoundedParams.Set_MaxSize(2);

        auto First = utils_object::Request_CreateNewObject_Pooled(
            this, UCk_ObjectPoolingTest_PlainObject, BoundedArchetype, BoundedParams);
        auto Second = utils_object::Request_CreateNewObject_Pooled(
            this, UCk_ObjectPoolingTest_PlainObject, BoundedArchetype, BoundedParams);
        Assert_True(ck::IsValid(First) && ck::IsValid(Second),
            "bounded: the first MaxSize acquires must return instances");
        Assert_True(First != Second, "bounded: the two acquires must be distinct instances");
        if (IsFinished()) { return; }

        auto Third = utils_object::Request_CreateNewObject_Pooled(
            this, UCk_ObjectPoolingTest_PlainObject, BoundedArchetype, BoundedParams);
        Assert_True(!ck::IsValid(Third), "bounded: acquire past MaxSize must return null");

        auto BoundedStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, BoundedArchetype);
        Assert_Equals_Int(BoundedStats.Get_NumLiveInstances(), 2, "bounded: capacity capped live instances at MaxSize");
        if (IsFinished()) { return; }

        // capacity frees up on release — the parked instance is re-issued
        utils_object::TryReleaseToPool(First);
        auto Reacquired = utils_object::Request_CreateNewObject_Pooled(
            this, UCk_ObjectPoolingTest_PlainObject, BoundedArchetype, BoundedParams);
        Assert_True(Reacquired == First, "bounded: after a release, acquire re-issues the parked instance");
        if (IsFinished()) { return; }

        // ---- Fail exhaustion: empty pool never creates on demand ----
        auto FailArchetype = Cast<UCk_ObjectPoolingTest_PlainObject>(
            NewObject(this, UCk_ObjectPoolingTest_PlainObject));

        auto FailParams = FCk_ObjectPooling_PoolParams();
        FailParams.Set_ExhaustionPolicy(ECk_ObjectPooling_ExhaustionPolicy::Fail);

        auto FailAcquire = utils_object::Request_CreateNewObject_Pooled(
            this, UCk_ObjectPoolingTest_PlainObject, FailArchetype, FailParams);
        Assert_True(!ck::IsValid(FailAcquire), "Fail policy: an empty pool must return null, never create");

        auto FailStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, FailArchetype);
        Assert_Equals_Int(FailStats.Get_NumMisses(), 1, "Fail policy: the empty acquire counts a miss");
        Assert_Equals_Int(FailStats.Get_NumLiveInstances(), 0, "Fail policy: nothing was created");

        FinishSuccess();
    }
}
