// Language=angelscript

//============================================================================
// CK POOL — AUTOMATION TEST: DEMAND RAMP TO 1000, GROW BATCH PRE-PROVISIONS
//============================================================================
//
// Review-requested stress shape: demand ramps in WAVES of +50 acquires up
// to 1000 outstanding, against a pool with GrowBatchCount=64 ("the wave
// size plus a bit more"). Expected dynamics:
//
//   wave 1  — cold pool: 50 misses (the cold case that matches demand),
//             growth tops the extras up to 63 → next wave pre-provisioned.
//   wave 2  — all 50 served from the batch extras: ZERO misses.
//   wave 3+ — the pattern alternates: a wave that dips into misses re-tops
//             the batch, covering the following wave.
//
// Per-wave hits/misses/latency are LOGGED (never asserted — machine/frame
// dependent). Asserted invariants (deterministic):
//   - every wave fully delivers; 1000 outstanding at the end
//   - at least one wave after the first has ZERO misses (pre-provisioning worked)
//   - total live never exceeds outstanding + GrowBatchCount (top-up semantics:
//     a burst of N misses provisions ONE batch of extras, not N batches)
//============================================================================

class UCk_AutoTest_EntityPool_Perf_RampTo1000_GrowBatchPreProvisions : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 120.0f;

    private int32 WaveSize = 50;
    private int32 MaxOutstanding = 1000;
    private int32 GrowBatch = 64;

    private int32 _Outstanding = 0;
    private int32 _WaveDelivered = 0;
    private int32 _WaveIndex = 0;
    private int32 _SettleFrames = 0;
    private int32 _WavesWithZeroMisses = 0;

    private int32 _HitsAtWaveStart = 0;
    private int32 _MissesAtWaveStart = 0;
    private float64 _WaveStart = 0.0;

    private FCk_Handle_EntityPool _Pool;

    private float64 Get_NowSeconds()
    {
        return float64(FDateTime::Now().GetTicks()) / 10000000.0;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        auto PoolParams = FCk_Fragment_EntityPool_ParamsData(UCk_PoolTest_RampSubject_EntityScript);
        PoolParams.Set_GrowBatchCount(GrowBatch);
        PoolParams.Set_PrewarmBudgetPerTick(256);

        _Pool = UCk_Utils_EntityPool_UE::Request_CreatePool(PoolParams);
        Assert_True(ck::IsValid(_Pool), "pool created");
        if (IsFinished()) { return; }

        StartWave();
    }

    private void StartWave()
    {
        auto _CkPerfScope = ck::ScopedStat();
        _WaveIndex++;
        _WaveDelivered = 0;

        auto Stats = _Pool.Get_Stats();
        _HitsAtWaveStart = Stats.Get_NumHits();
        _MissesAtWaveStart = Stats.Get_NumMisses();
        _WaveStart = Get_NowSeconds();

        for (int32 Index = 0; Index < WaveSize; ++Index)
        {
            auto Pool = _Pool;
            auto Pending = Pool.Request_Acquire_OnPool(FInstancedStruct());
            Pending.Promise_OnAcquired(FCk_Delegate_EntityPool_Acquired(this, n"OnWaveAcquired"));
        }
    }

    UFUNCTION()
    private void OnWaveAcquired(FCk_EntityPool_AcquireResult InResult)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        if (InResult.Get_Result() != ECk_SucceededFailed::Succeeded)
        {
            Assert_True(false, f"wave {_WaveIndex} acquire failed");
            return;
        }

        _WaveDelivered++;
        if (_WaveDelivered < WaveSize) { return; }

        _Outstanding += WaveSize;

        auto WaveMs = (Get_NowSeconds() - _WaveStart) * 1000.0;
        auto Stats = _Pool.Get_Stats();
        auto WaveHits = Stats.Get_NumHits() - _HitsAtWaveStart;
        auto WaveMisses = Stats.Get_NumMisses() - _MissesAtWaveStart;

        if (_WaveIndex > 1 && WaveMisses == 0)
        { _WavesWithZeroMisses++; }

        Log(f"[CkPool Ramp] wave {_WaveIndex}: outstanding={_Outstanding} hits={WaveHits} misses={WaveMisses} acquire→delivered={WaveMs} ms (live={Stats.Get_NumLiveInstances()} dormant={Stats.Get_NumDormant()})");

        // top-up invariant: a 50-miss burst provisions ONE batch of extras, never one batch per miss
        Assert_True(Stats.Get_NumLiveInstances() + Stats.Get_NumPrewarmRemaining() <= _Outstanding + GrowBatch,
            f"live+queued ({Stats.Get_NumLiveInstances()}+{Stats.Get_NumPrewarmRemaining()}) must not exceed outstanding+GrowBatch ({_Outstanding}+{GrowBatch}) — top-up, not add-per-miss");
        if (IsFinished()) { return; }

        _SettleFrames = 0;
        WaitOneFrame(n"OnSettleTick");
    }

    UFUNCTION()
    private void OnSettleTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        // let the amortized batch provisioning finish before the next wave, so each wave
        // observes the pool state the PREVIOUS wave's growth produced
        auto Stats = _Pool.Get_Stats();
        if (Stats.Get_NumPrewarmRemaining() > 0 || Stats.Get_NumSpawnsInFlight() > 0)
        {
            _SettleFrames++;
            if (_SettleFrames > 240)
            {
                Assert_True(false, f"wave {_WaveIndex} provisioning never settled (queued={Stats.Get_NumPrewarmRemaining()} in-flight={Stats.Get_NumSpawnsInFlight()})");
                return;
            }
            WaitOneFrame(n"OnSettleTick");
            return;
        }

        if (_Outstanding < MaxOutstanding)
        {
            StartWave();
            return;
        }

        // ramp complete — invariants
        Assert_Equals_Int(_Outstanding, MaxOutstanding, "ramp reached 1000 outstanding");

        auto FinalStats = _Pool.Get_Stats();
        Assert_Equals_Int(FinalStats.Get_NumInUse(), MaxOutstanding, "all 1000 in use");
        Assert_True(_WavesWithZeroMisses >= 1,
            f"at least one post-cold wave was served entirely from batch extras (got {_WavesWithZeroMisses})");
        Assert_True(FinalStats.Get_NumLiveInstances() <= MaxOutstanding + GrowBatch,
            "final live count bounded by outstanding + one grow batch");

        Log(f"[CkPool Ramp] DONE: 1000 outstanding over {_WaveIndex} waves | zero-miss waves: {_WavesWithZeroMisses} | final live={FinalStats.Get_NumLiveInstances()} hits={FinalStats.Get_NumHits()} misses={FinalStats.Get_NumMisses()}");

        FinishSuccess();
    }
}
