// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: pools are keyed per archetype and reset to the ARCHETYPE
//
// Pools are keyed (class, archetype): an archetype-keyed pool is fully independent of the CDO
// pool of the same class, a fresh acquire carries the archetype's values, and the recycle reset
// restores the ARCHETYPE's values - not the CDO's.

class UCk_AutoTest_ObjectPooling_ArchetypeKeyedPoolsResetToArchetype : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto Archetype = Cast<UCk_ObjectPoolingTest_PlainObject>(
            NewObject(this, UCk_ObjectPoolingTest_PlainObject));
        Archetype.Value = 7;

        auto PoolParams = FCk_ObjectPooling_PoolParams(); // defaults: Recycle / Unbounded / Grow

        auto Obj = Cast<UCk_ObjectPoolingTest_PlainObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PlainObject, Archetype, PoolParams));
        Assert_True(ck::IsValid(Obj), "acquire #1: pooled create must return an instance");
        Assert_Equals_Int(Obj.Value, 7, "a fresh instance must carry the ARCHETYPE's values (template create)");
        if (IsFinished()) { return; }

        Obj.Value = 42;
        utils_object::TryReleaseToPool(Obj);

        auto Recycled = Cast<UCk_ObjectPoolingTest_PlainObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PlainObject, Archetype, PoolParams));
        Assert_True(Recycled == Obj, "acquire #2: the archetype pool must re-issue the same instance");
        Assert_Equals_Int(Recycled.Value, 7,
            "recycle reset must restore the ARCHETYPE's value (7), not the CDO default (0)");
        if (IsFinished()) { return; }

        // the (class, CDO) pool is a different pool - completely untouched by all of the above
        auto CdoPoolStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, nullptr);
        Assert_Equals_Int(CdoPoolStats.Get_NumLiveInstances(), 0,
            "the CDO-keyed pool of the same class must be independent of the archetype-keyed pool");

        auto ArchetypePoolStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, Archetype);
        Assert_Equals_Int(ArchetypePoolStats.Get_NumHits(), 1, "the archetype pool recorded the recycle hit");
        Assert_Equals_Int(ArchetypePoolStats.Get_NumLiveInstances(), 1, "exactly 1 live instance in the archetype pool");

        FinishSuccess();
    }
}
