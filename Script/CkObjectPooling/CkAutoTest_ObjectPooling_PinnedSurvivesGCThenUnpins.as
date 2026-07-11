// Language=angelscript
//
// CK OBJECT POOLING — AUTOMATION TEST: DestroyOnRelease pin survives GC, unpins on release
//
// The core proof of the pin-everything ownership model. Acquire a DestroyOnRelease
// object (the subsystem pins it; a holder would keep only a weak ptr). Force a full
// GC: the object must survive purely on the subsystem pin. Release: the subsystem
// unpins it — after the next GC it is no longer tracked. Uses the direct pooled API
// so the test legitimately holds the pointer; no reach-into-EntityScript accessor.

class UCk_AutoTest_ObjectPooling_PinnedSurvivesGCThenUnpins : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private UCk_ObjectPoolingTest_PinnedObject _Obj;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // AS: setters mutate, so they can't be chained on a temporary — declare then set
        auto PoolParams = FCk_ObjectPooling_PoolParams();
        PoolParams.Set_RecyclePolicy(ECk_ObjectPooling_RecyclePolicy::DestroyOnRelease);

        _Obj = Cast<UCk_ObjectPoolingTest_PinnedObject>(
            utils_object::Request_CreateNewObject_Pooled(
                this, UCk_ObjectPoolingTest_PinnedObject, nullptr, PoolParams));

        Assert_True(ck::IsValid(_Obj), "acquire: DestroyOnRelease create must return an instance");
        Assert_True(utils_object::Get_IsPoolTrackedObject(_Obj),
            "acquire: the subsystem must track (pin) the DestroyOnRelease instance");
        if (IsFinished()) { return; }

        System::CollectGarbage();
        WaitOneFrame(n"OnGCSettled");
    }

    UFUNCTION()
    private void OnGCSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(ck::IsValid(_Obj),
            "post-GC: the object must survive a full GC purely on the subsystem pin");
        Assert_True(utils_object::Get_IsPoolTrackedObject(_Obj),
            "post-GC: the subsystem must still track the pinned instance");
        if (IsFinished()) { return; }

        auto ReleaseResult = utils_object::TryReleaseToPool(_Obj);
        Assert_True(ReleaseResult == ECk_SucceededFailed::Succeeded, "release: unpin must succeed");
        Assert_True(!utils_object::Get_IsPoolTrackedObject(_Obj),
            "release: the subsystem must stop tracking the instance immediately after unpin");

        FinishSuccess();
    }
}
