// Language=angelscript
//
// CK OBJECT POOLING - AUTOMATION TEST: amortized prewarm + grow-batch top-up
//
// Prewarm: pool creation schedules PrewarmCount instances, spawned PrewarmBudgetPerTick per
// subsystem tick - never synchronously. GrowBatch: a demand miss returns exactly one instance
// synchronously and queues (GrowBatchCount - 1) extras through the same amortized tick.

class UCk_AutoTest_ObjectPooling_PrewarmAndGrowBatchProvision : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private UCk_ObjectPoolingTest_PlainObject _PrewarmArchetype;
    private UCk_ObjectPoolingTest_PlainObject _GrowArchetype;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        _PrewarmArchetype = Cast<UCk_ObjectPoolingTest_PlainObject>(
            NewObject(this, UCk_ObjectPoolingTest_PlainObject));
        _GrowArchetype = Cast<UCk_ObjectPoolingTest_PlainObject>(
            NewObject(this, UCk_ObjectPoolingTest_PlainObject));

        // pool creation happens on first acquire - that acquire is the demand miss that also
        // kicks off the prewarm schedule
        auto PrewarmParams = FCk_ObjectPooling_PoolParams();
        PrewarmParams.Set_PrewarmCount(3);
        PrewarmParams.Set_PrewarmBudgetPerTick(2);

        auto PrewarmFirst = utils_object::Request_CreateNewObject_Pooled(
            this, UCk_ObjectPoolingTest_PlainObject, _PrewarmArchetype, PrewarmParams);
        Assert_True(ck::IsValid(PrewarmFirst), "prewarm pool: the creating acquire returns an instance");

        auto PrewarmStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, _PrewarmArchetype);
        Assert_Equals_Int(PrewarmStats.Get_NumFree(), 0, "prewarm is amortized - nothing is spawned synchronously");
        Assert_Equals_Int(PrewarmStats.Get_NumPrewarmRemaining(), 3, "3 prewarm spawns are scheduled");
        if (IsFinished()) { return; }

        auto GrowParams = FCk_ObjectPooling_PoolParams();
        GrowParams.Set_GrowBatchCount(3);

        auto GrowFirst = utils_object::Request_CreateNewObject_Pooled(
            this, UCk_ObjectPoolingTest_PlainObject, _GrowArchetype, GrowParams);
        Assert_True(ck::IsValid(GrowFirst), "grow pool: the demand miss returns exactly one instance");

        auto GrowStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, _GrowArchetype);
        Assert_Equals_Int(GrowStats.Get_NumPrewarmRemaining(), 2,
            "grow-batch tops up (GrowBatchCount - 1) extras through the amortized tick");
        if (IsFinished()) { return; }

        WaitUntil(n"Check_BothPoolsDrained", n"OnFrameSettled");
    }

    // Both amortized schedules having drained is the settling event. The parked /
    // live counts below stay assertions, so a pool that drains to the WRONG shape
    // is reported by them rather than timing out here.
    UFUNCTION()
    private void Check_BothPoolsDrained(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto PrewarmStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, _PrewarmArchetype);
        auto GrowStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, _GrowArchetype);

        auto Res = OutResult;
        Res.Set(PrewarmStats.Get_NumPrewarmRemaining() == 0
             && GrowStats.Get_NumPrewarmRemaining() == 0);
    }

    UFUNCTION()
    private void OnFrameSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto PrewarmStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, _PrewarmArchetype);
        auto GrowStats = utils_object::Get_ObjectPoolStats(this, UCk_ObjectPoolingTest_PlainObject, _GrowArchetype);

        const bool PrewarmDone = PrewarmStats.Get_NumPrewarmRemaining() == 0;
        const bool GrowDone = GrowStats.Get_NumPrewarmRemaining() == 0;

        Assert_True(PrewarmDone, "prewarm must complete within a few subsystem ticks");
        Assert_Equals_Int(PrewarmStats.Get_NumFree(), 3, "prewarm parked exactly PrewarmCount instances");
        Assert_Equals_Int(PrewarmStats.Get_NumLiveInstances(), 4, "prewarm pool: 3 parked + 1 handed out");

        Assert_True(GrowDone, "grow-batch top-up must complete within a few subsystem ticks");
        Assert_Equals_Int(GrowStats.Get_NumFree(), 2, "grow pool parked exactly (GrowBatchCount - 1) extras");
        Assert_Equals_Int(GrowStats.Get_NumLiveInstances(), 3, "grow pool: 2 parked + 1 handed out");

        FinishSuccess();
    }
}
