// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: PERF COMPARISON, SPAWN vs POOL REUSE
//============================================================================
//
// A/B stress comparison requested in review: N EntityScripts spawned fresh
// (Request_SpawnEntity, spawn → constructed) vs N acquired from an EntityPool
// (acquire → delivered), cold and warm:
//
//   Phase A (baseline): spawn N fresh instances, wait for all to construct.
//   Phase B (pool COLD): acquire N from an empty pool — grows N instances,
//     so this includes the same construction cost plus pool bookkeeping.
//   Phase C (pool WARM): release all N, acquire N again — pure recycling,
//     construction never runs (the pooling win).
//
// Timings are logged for humans to compare, NOT asserted — wall-clock in a
// headless PIE tick loop is frame-quantized and machine-dependent, so a
// threshold assertion would flake (perf doctrine: measure, don't gate).
// The test asserts only functional correctness: counts, and that warm
// acquires recycled (UseGeneration == 2, NumHits == N).
//============================================================================

class UCk_AutoTest_EntityPool_Perf_SpawnVsPoolReuse : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private int32 N = 32;

    private int32 _Step = 0;
    private int32 _Count = 0;
    private TArray<FCk_Handle> _Entities;
    private FCk_Handle _TestEntity;

    private float64 _PhaseStart = 0.0;
    private float64 _BaselineSeconds = 0.0;
    private float64 _ColdSeconds = 0.0;
    private float64 _WarmSeconds = 0.0;

    // sub-frame real clock (FDateTime ticks = 100ns) — game time is frame-quantized and the processor
    // pump system drains an entire spawn/acquire cascade within ONE frame, which reads as 0.0 on any
    // game-time clock
    private float64 Get_NowSeconds()
    {
        return float64(FDateTime::Now().GetTicks()) / 10000000.0;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _TestEntity = InHandle;

        // Phase A — baseline: N fresh spawns
        _Step = 1;
        _PhaseStart = Get_NowSeconds();

        for (int32 Index = 0; Index < N; ++Index)
        {
            auto Owner = _TestEntity;
            auto Pending = utils_entity_script::Request_SpawnEntity(Owner, UCk_PoolTest_PerfSubject_EntityScript, FInstancedStruct());
            utils_pending_entity_script::Promise_OnConstructed(
                Pending, FCk_Delegate_EntityScript_Constructed(this, n"OnBaselineConstructed"));
        }
    }

    UFUNCTION()
    private void OnBaselineConstructed(FCk_Handle_EntityScript InEntityScript)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished() || _Step != 1) { return; }

        _Count++;
        if (_Count < N) { return; }

        _BaselineSeconds = Get_NowSeconds() - _PhaseStart;

        // baseline instances are lifetime children of the test entity — teardown cascades them at
        // test end. Leaving them alive keeps the cold-phase timing free of destruction noise; the
        // comparison is spawn→constructed vs acquire→delivered, the paths a consumer actually waits on

        // Phase B — pool cold: N acquires against an empty pool (grows N instances)
        _Step = 2;
        _Count = 0;
        _Entities.Empty();
        _PhaseStart = Get_NowSeconds();

        for (int32 Index = 0; Index < N; ++Index)
        {
            auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_PerfSubject_EntityScript, FInstancedStruct());
            Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnColdAcquired"));
        }
    }

    UFUNCTION()
    private void OnColdAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished() || _Step != 2) { return; }

        Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "cold acquire fulfilled with Succeeded");
        _Entities.Add(InResult.Get_AcquiredEntity());

        _Count++;
        if (_Count < N) { return; }

        _ColdSeconds = Get_NowSeconds() - _PhaseStart;

        // Phase C — pool warm: release everything, acquire the same N again (pure recycling)
        _Step = 3;
        _Count = 0;

        for (auto Entity : _Entities)
        {
            auto ToRelease = Entity;
            utils_entity_pool::Request_ReleaseToPool(ToRelease);
        }
        _Entities.Empty();

        _PhaseStart = Get_NowSeconds();

        for (int32 Index = 0; Index < N; ++Index)
        {
            auto Pending = utils_entity_pool::Request_Acquire(UCk_PoolTest_PerfSubject_EntityScript, FInstancedStruct());
            Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnWarmAcquired"));
        }
    }

    UFUNCTION()
    private void OnWarmAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished() || _Step != 3) { return; }

        Assert_True(InResult.Get_Result() == ECk_SucceededFailed::Succeeded, "warm acquire fulfilled with Succeeded");
        Assert_Equals_Int(UCk_Utils_EntityPool_UE::Get_UseGeneration(InResult.Get_AcquiredEntity()), 2,
            "warm acquire recycled an existing instance");

        _Count++;
        if (_Count < N) { return; }

        _WarmSeconds = Get_NowSeconds() - _PhaseStart;

        auto Pool = UCk_Utils_EntityPool_UE::TryGet_Pool_ByClass(UCk_PoolTest_PerfSubject_EntityScript);
        auto Stats = Pool.Get_Stats();
        Assert_Equals_Int(Stats.Get_NumHits(), N, "every warm acquire was a pool hit (zero construction)");
        Assert_Equals_Int(Stats.Get_NumLiveInstances(), N, "warm round reused instances instead of growing");

        Log(f"[CkPool Perf] N={N} EntityScripts | baseline spawn→constructed: {_BaselineSeconds * 1000.0} ms | "
            + f"pool COLD acquire→delivered: {_ColdSeconds * 1000.0} ms | pool WARM acquire→delivered: {_WarmSeconds * 1000.0} ms "
            + f"(accurate real time; whole cascades can resolve within one frame via processor pumps — compare relative magnitudes, not absolutes)");

        FinishSuccess();
    }
}
