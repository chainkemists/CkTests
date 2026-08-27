// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: external destroy ("steal") stays benign end-to-end
//
// "Dev does not care whether the object is pooled" means teardown code may destroy a tracked
// instance directly (never releasing it), or destroy it and release afterwards - nothing may
// ensure, crash, or corrupt the pool. Uses a pooled UActorComponent subject because
// DestroyComponent is the one AS-reachable external-destroy path. Covers: destroy-then-release
// is a quiet Failed; a stolen parked instance is swept and the next acquire creates fresh; live
// counts reconcile after GC.

class UCk_AutoTest_ObjectPooling_ExternalDestroyStealIsBenign : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private UCk_ObjectPoolingTest_PooledComponent _Parked;
    private UCk_ObjectPoolingTest_PooledComponent _InUse;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto PoolParams = FCk_ObjectPooling_PoolParams(); // defaults: Recycle / Unbounded / Grow

        // steal a PARKED instance: acquire -> release (parks it) -> destroy it externally
        _Parked = Cast<UCk_ObjectPoolingTest_PooledComponent>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PooledComponent, nullptr, PoolParams));
        Assert_True(ck::IsValid(_Parked), "acquire #1 must return an instance");
        if (IsFinished()) { return; }

        utils_object::TryReleaseToPool(_Parked);
        _Parked.DestroyComponent();

        // steal an IN-USE instance: acquire -> destroy externally WITHOUT releasing
        _InUse = Cast<UCk_ObjectPoolingTest_PooledComponent>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PooledComponent, nullptr, PoolParams));
        Assert_True(ck::IsValid(_InUse), "acquire #2 must return an instance");
        if (IsFinished()) { return; }

        _InUse.DestroyComponent();

        // destroy-then-release ordering must be a QUIET no-op (no ensure) - teardown code is
        // allowed to not care whether the object was already gone
        auto LateRelease = utils_object::TryReleaseToPool(_InUse);
        Assert_True(LateRelease == ECk_SucceededFailed::Failed,
            "destroy-then-release must be a benign Failed no-op");
        Assert_True(!utils_object::Get_IsPoolTrackedObject(_InUse),
            "a destroyed instance must no longer be tracked");
        if (IsFinished()) { return; }

        System::CollectGarbage();
        WaitOneFrame(n"OnGCSettled");
    }

    UFUNCTION()
    private void OnGCSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // both stolen instances are gone; the next acquire must skip the dead slot and create fresh
        auto PoolParams = FCk_ObjectPooling_PoolParams();
        auto Fresh = Cast<UCk_ObjectPoolingTest_PooledComponent>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PooledComponent, nullptr, PoolParams));
        Assert_True(ck::IsValid(Fresh), "post-steal acquire must return a valid FRESH instance");
        if (IsFinished()) { return; }

        auto Stats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PooledComponent, nullptr);
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 1,
            "after both steals were swept, exactly the fresh instance is live");
        Assert_Equals_Int(Stats.Get_NumInUse(), 1, "exactly the fresh instance is in use");
        Assert_Equals_Int(Stats.Get_NumFree(), 0, "the stolen parked slot was swept, not re-issued");

        FinishSuccess();
    }
}
