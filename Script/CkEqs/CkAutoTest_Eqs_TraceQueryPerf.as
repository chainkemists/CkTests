// Language=angelscript

//============================================================================
// CK EQS — PERF READOUT AUTOTEST (grid + trace-test query throughput)
//============================================================================
//
// Measured (not estimated) readout for the EQS trace-test hot loop:
// four concurrent 51x51 SimpleGrid (2601 candidates) + LineTrace filter
// queries against a blocker probe, each re-issued the moment it completes.
// The per-frame budget (default 256) plus the anti-deadlock clause means
// each query's trace test runs its full 2601 Jolt raycasts inside a single
// tick — exactly the loop DoRunTest_Trace owns.
//
// Warms up, samples per-tick delta for SampleSeconds, then logs avg / max
// frame ms + FPS + completed query count. Numbers are RELATIVE (same
// harness, same machine): compare logs from before/after a change to
// FCk_Eqs_Algorithm's candidate loops.
//
// No pass/fail threshold on timing (machine-dependent); fails only on setup.
//============================================================================

namespace ck_eqs_trace_perf
{
    asset Asset_EqsTracePerf_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Eqs.TracePerf.Blocker");
    }
}

class UCk_AutoTest_Eqs_TraceQueryPerf : UCk_AutoTest_Base
{
    private FCk_Handle _SelfEntity;
    private int32 _QueriesCompleted = 0;
    private bool _Sampling = false;
    private int32 _QueriesInSample = 0;

    private float _Elapsed = 0.0f;
    private float _SampleSum = 0.0f;
    private float _SampleMax = 0.0f;
    private int32 _SampleCount = 0;

    const float WarmupSeconds = 3.0f;
    const float SampleSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfEntity = InHandle;

        System::ExecuteConsoleCommand("t.MaxFPS 0");
        System::ExecuteConsoleCommand("r.VSync 0");

        // Querier needs a transform — Generate validates this.
        utils_transform::Add(_SelfEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Blocker: big static box probe wall so roughly half the grid's LOS rays hit something.
        auto BlockerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfEntity);
        BlockerEntity.Request_OverrideToSelf();
        auto BlockerTransform = utils_transform::Add(
            BlockerEntity, FTransform(FRotator::ZeroRotator, FVector(300.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);

        auto BlockerParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Eqs.TracePerf.Blocker"));
        BlockerParams.Set_MotionType(ECk_MotionType::Static);
        BlockerParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
        utils_probe::Add_Box(BlockerTransform, FVector(10.0, 2000.0, 2000.0), BlockerParams, FCk_Probe_DebugInfo());

        utils_timer::Create_Tick(_SelfEntity, FCk_Delegate_Timer(this, n"OnTick"));

        // Four outstanding queries, each re-issued on completion — sized to SATURATE the
        // headless 120fps frame budget (~8.33 ms) in the serial implementation, so frame
        // deltas measure the trace-loop work rather than the frame cap.
        DoIssueQuery();
        DoIssueQuery();
        DoIssueQuery();
        DoIssueQuery();
    }

    private void DoIssueQuery()
    {
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(2500.0f);   // 51x51 = 2601 candidates

        auto Trace = FCk_Eqs_TestParams();
        Trace.Set_TestType(ECk_Eqs_TestType::Trace);
        Trace.Set_Purpose(ECk_Eqs_TestPurpose::Filter);
        Trace.Set_TraceMode(ECk_Eqs_TraceMode::LineTrace);

        auto TraceFilter = FGameplayTagContainer();
        TraceFilter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Eqs.TracePerf.Blocker"));
        Trace.Set_TraceFilter(TraceFilter);

        auto FilterConfig = FCk_Eqs_FilterConfig();
        FilterConfig.Set_FilterType(ECk_Eqs_FilterType::Minimum);
        FilterConfig.Set_FilterMin(0.5f);
        Trace.Set_FilterConfig(FilterConfig);

        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(Trace);

        auto Params = FCk_Eqs_QueryParams(_SelfEntity, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnQueryComplete"));
        Request.Set_AutoDestroy(true);

        utils_eqs::Request_RunQuery(_SelfEntity, Request);
    }

    UFUNCTION()
    private void OnQueryComplete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        _QueriesCompleted++;
        if (_Sampling) { _QueriesInSample++; }

        DoIssueQuery();
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const float Dt = float(InDeltaT.Get_Seconds());
        _Elapsed += Dt;

        if (_Elapsed <= WarmupSeconds)
        { return; }

        if (_Elapsed <= WarmupSeconds + SampleSeconds)
        {
            _Sampling = true;
            _SampleSum += Dt;
            if (Dt > _SampleMax) { _SampleMax = Dt; }
            ++_SampleCount;
            return;
        }

        if (_SampleCount == 0)
        {
            FinishFailure("no frames sampled");
            return;
        }

        if (_QueriesCompleted == 0)
        {
            FinishFailure("no EQS queries completed — pipeline stalled");
            return;
        }

        const float AvgMs = (_SampleSum / float(_SampleCount)) * 1000.0f;
        const float MaxMs = _SampleMax * 1000.0f;
        const float Fps = float(_SampleCount) / _SampleSum;
        Log(f"[CkEqs PERF][Grid441+Trace] frames={_SampleCount} avg={AvgMs} ms  max={MaxMs} ms  fps={Fps}  queriesInSample={_QueriesInSample}");
        FinishSuccess();
    }
}

class ACk_AutoTest_Eqs_TraceQueryPerf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Eqs_TraceQueryPerf;
    default _TimeoutSeconds = 45.0f;
}
