// Language=angelscript

//============================================================================
// CK EQS — AUTOMATION TEST: TRACE TEST BLOCKS LOS + FIRES NO OVERLAP EVENTS
//============================================================================
//
// First coverage of the Trace test type (DoRunTest_Trace), plus a pin on the
// side-effect contract of EQS physics casts:
//   1. A large static box probe ("blocker") stands at X=+300, spanning Y/Z.
//   2. OnCircle generator: 8 candidates on a 600uu circle around the querier.
//      Rays to the 3 +X-side candidates cross the blocker; the other 5 don't.
//   3. Trace test (LineTrace, Filter, FilterMin=0.5) must drop exactly the 3
//      LOS-blocked candidates.
//   4. EQS queries SCORE the world — they must NOT enqueue Begin/EndOverlap
//      events into the probes their casts hit. The blocker binds
//      OnBeginOverlap and the test asserts zero events after the query
//      completes (+1 settle frame so Probe_HandleRequests had its tick).
//============================================================================

namespace ck_eqs_trace_test
{
    asset Asset_EqsTraceTest_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.Eqs.TraceBlocker");
    }
}

class UCk_AutoTest_Eqs_Trace_BlocksLosAndStaysSilent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfEntity;
    private int32 _BlockerOverlapEvents = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfEntity = InHandle;

        // Querier needs a transform — Generate validates this.
        utils_transform::Add(_SelfEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // ---- Blocker: static box probe wall at X=+300, spanning Y/Z ----
        auto BlockerEntity = utils_entity_lifetime::Request_CreateEntity(_SelfEntity);
        BlockerEntity.Request_OverrideToSelf();
        auto BlockerTransform = utils_transform::Add(
            BlockerEntity, FTransform(FRotator::ZeroRotator, FVector(300.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);

        auto BlockerProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Eqs.TraceBlocker"));
        BlockerProbeParams.Set_MotionType(ECk_MotionType::Static);
        // Notify + empty filter: the blocker WOULD receive overlap events if anything fired
        // them — which is exactly what this test asserts EQS casts do not do.
        BlockerProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto BlockerProbe = utils_probe::Add_Box(
            BlockerTransform, FVector(10.0, 800.0, 800.0), BlockerProbeParams, FCk_Probe_DebugInfo());

        utils_probe::BindTo_OnBeginOverlap(BlockerProbe,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnBlockerBeginOverlap"));

        // Let probe setup (Jolt body creation) settle before the query casts against it.
        WaitOneFrame(n"OnWorldSettled");
    }

    UFUNCTION()
    private void OnWorldSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::OnCircle);
        Generator.Set_NumPointsOnCircle(8);
        Generator.Set_CircleRadius(600.0f);
        Generator.Set_CircleArcAngle(360.0f);

        auto Trace = FCk_Eqs_TestParams();
        Trace.Set_TestType(ECk_Eqs_TestType::Trace);
        Trace.Set_Purpose(ECk_Eqs_TestPurpose::Filter);
        Trace.Set_TraceMode(ECk_Eqs_TraceMode::LineTrace);

        auto TraceFilter = FGameplayTagContainer();
        TraceFilter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Eqs.TraceBlocker"));
        Trace.Set_TraceFilter(TraceFilter);

        // Raw is 1.0 (LOS clear) or 0.0 (blocked) — Minimum 0.5 drops the blocked candidates.
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

        Assert_True(InResults.Get_HasResults(),
            "Candidates on the far side of the blocker should survive the Trace filter");

        // 8 points on the circle; rays to the 3 +X-side points cross the wall at X=300.
        auto Candidates = InResults.Get_Candidates();
        Assert_Equals_Int(Candidates.Num(), 5,
            "Trace filter should drop exactly the 3 LOS-blocked candidates");

        for (int32 i = 0; i < Candidates.Num(); i++)
        {
            auto Location = Candidates[i].Get_Location();
            Assert_True(Location.X < 290.0,
                f"Surviving candidate should be on the querier's side of the wall (X={Location.X})");
        }

        // Overlap requests (if any were erroneously enqueued by the query's casts) are drained
        // by Probe_HandleRequests on a later tick — settle one frame before asserting silence.
        WaitOneFrame(n"OnPostQuerySettled");
    }

    UFUNCTION()
    private void OnPostQuerySettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_BlockerOverlapEvents, 0,
            "EQS trace casts must not fire overlap events into the probes they hit");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnBlockerBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        _BlockerOverlapEvents++;
    }
}
