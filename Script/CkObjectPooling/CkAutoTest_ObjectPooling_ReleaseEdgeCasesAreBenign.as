// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: release edge cases are benign no-ops
//
// "Dev does not care whether the object is pooled" also means teardown code may release in any
// order, any number of times, on anything. Double-release must not double-park; releasing an
// object the subsystem never handed out must be a quiet Failed; the pool must stay coherent
// (re-acquire is a hit on the single parked instance) after all of it.

class UCk_AutoTest_ObjectPooling_ReleaseEdgeCasesAreBenign : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // isolate this test's pool from the other pooling tests via a dedicated archetype instance
        auto Archetype = Cast<UCk_ObjectPoolingTest_PlainObject>(
            NewObject(this, UCk_ObjectPoolingTest_PlainObject));

        auto PoolParams = FCk_ObjectPooling_PoolParams(); // defaults: Recycle / Unbounded / Grow

        auto Obj = Cast<UCk_ObjectPoolingTest_PlainObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PlainObject, Archetype, PoolParams));
        Assert_True(ck::IsValid(Obj), "acquire: pooled create must return an instance");
        if (IsFinished()) { return; }

        auto FirstRelease = utils_object::TryReleaseToPool(Obj);
        Assert_True(FirstRelease == ECk_SucceededFailed::Succeeded, "release #1 must succeed");

        auto SecondRelease = utils_object::TryReleaseToPool(Obj);
        Assert_True(SecondRelease == ECk_SucceededFailed::Failed,
            "release #2 (double release) must be a benign Failed no-op");

        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, Archetype);
        Assert_Equals_Int(Stats.Get_NumFree(), 1, "double release must NOT double-park (exactly 1 free)");
        Assert_Equals_Int(Stats.Get_NumInUse(), 0, "nothing in use after release");
        if (IsFinished()) { return; }

        // an object the subsystem never handed out - release is a quiet no-op
        auto NeverPooled = NewObject(this, UCk_ObjectPoolingTest_PlainObject);
        auto NeverPooledRelease = utils_object::TryReleaseToPool(NeverPooled);
        Assert_True(NeverPooledRelease == ECk_SucceededFailed::Failed,
            "releasing a never-pooled object must be a benign Failed no-op");
        Assert_True(!utils_object::Get_IsPoolTrackedObject(NeverPooled),
            "a never-pooled object must not become tracked by releasing it");
        if (IsFinished()) { return; }

        // the pool stayed coherent through all of the above
        auto Reacquired = Cast<UCk_ObjectPoolingTest_PlainObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PlainObject, Archetype, PoolParams));
        Assert_True(Reacquired == Obj, "re-acquire must re-issue the single parked instance");

        auto StatsAfter = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, Archetype);
        Assert_Equals_Int(StatsAfter.Get_NumHits(), 1, "re-acquire must be a pool HIT");
        Assert_Equals_Int(StatsAfter.Get_NumLiveInstances(), 1, "exactly 1 live instance throughout");

        FinishSuccess();
    }
}
