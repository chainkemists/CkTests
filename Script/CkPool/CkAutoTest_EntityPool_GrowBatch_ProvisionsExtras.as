// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: GROW BATCH PROVISIONS EXTRA DORMANT INSTANCES
//============================================================================
//
// Covers _GrowBatchCount: with GrowBatchCount=4, ONE acquire against an empty
// pool delivers its instance AND provisions 3 extras through the amortized
// prewarm budget — so the pool settles at 4 live / 3 dormant, and the next
// acquire is a HIT (no construction).
//
// The extras are budget-amortized (PrewarmBudgetPerTick), so the test polls
// frame-by-frame via the base's WaitOneFrame helper rather than asserting
// immediately.
//============================================================================

class UCk_AutoTest_EntityPool_GrowBatch_ProvisionsExtras : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private int32 _FramesWaited = 0;
    private FCk_Handle_EntityPool _Pool;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto PoolParams = FCk_Fragment_EntityPool_ParamsData(UCk_PoolTest_GrowBatchSubject_EntityScript);
        PoolParams.Set_GrowBatchCount(4);
        PoolParams.Set_PrewarmBudgetPerTick(8);

        auto Pending = utils_entity_pool::Request_Acquire_WithPoolParams(PoolParams, FInstancedStruct());
        Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnAcquired"));
    }

    UFUNCTION()
    private void OnAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "acquire fulfilled with Succeeded");

        _Pool = UCk_Utils_EntityPool_UE::TryGet_Pool_ByClass(UCk_PoolTest_GrowBatchSubject_EntityScript);
        Assert_True(ck::IsValid(_Pool), "pool discoverable by class");
        if (IsFinished()) { return; }

        WaitOneFrame(n"CheckExtrasProvisioned");
    }

    UFUNCTION()
    private void CheckExtrasProvisioned(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        auto Stats = _Pool.Get_Stats();

        // extras flow: prewarm tick spawns → construct pipeline → parked dormant. Poll until settled
        if (Stats.Get_NumLiveInstances() < 4 || Stats.Get_NumDormant() < 3)
        {
            _FramesWaited++;
            if (_FramesWaited > 120)
            {
                Assert_True(false, f"grow batch never settled: live={Stats.Get_NumLiveInstances()} dormant={Stats.Get_NumDormant()} after {_FramesWaited} frames");
                return;
            }
            WaitOneFrame(n"CheckExtrasProvisioned");
            return;
        }

        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 4, "one delivered + 3 batch extras = 4 live");
        Assert_Equals_Int(Stats.Get_NumDormant(), 3, "the 3 extras parked dormant");
        Assert_Equals_Int(Stats.Get_NumInUse(), 1, "only the delivered instance is in use");

        // the payoff: the NEXT acquire is a hit — no construction
        auto Pool = _Pool;
        auto Pending = Pool.Request_Acquire_OnPool(FInstancedStruct());
        Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnSecondAcquired"));
    }

    UFUNCTION()
    private void OnSecondAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "second acquire fulfilled");

        auto Stats = _Pool.Get_Stats();
        Assert_Equals_Int(Stats.Get_NumHits(), 1, "second acquire was a pool HIT (served from batch extras)");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), 4, "no growth on the second acquire");

        FinishSuccess();
    }
}
