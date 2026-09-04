// Language=angelscript

//============================================================================
// CK EQS - AUTOMATION TEST: _ProjectOntoNav GENERATOR FLAG
//============================================================================
//
// Verifies FCk_Eqs_GeneratorParams::_ProjectOntoNav flag behavior:
//
// Phase 1 (baseline - projection disabled):
//   SimpleGrid at Z=20000uu (far above any baked navmesh), _ProjectOntoNav=false.
//   Candidates generated normally -> HasResults=true, count > 0.
//
// Phase 2 (projection enabled - no navmesh at altitude):
//   Same SimpleGrid at Z=20000uu, _ProjectOntoNav=true,
//   _NavProjectionSearchHalfExtentUu=200uu.
//   No navmesh tile exists at that altitude, so every candidate fails projection through
//   the provider-neutral facade (utils_nav_surface::Try_ProjectPoint) -> all candidates
//   dropped at generate time -> query fails with 0 candidates -> HasResults=false.
//
// This test is deliberately world-independent: no navmesh bake required.
// Positive projection (candidates snap to navmesh surface) is demonstrated
// by the gym station instead.
//============================================================================

class UCk_AutoTest_Eqs_NavProjection : UCk_AutoTest_Base
{
    private FCk_Handle _SelfEntity;
    private int32      _Phase1CandidateCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SelfEntity = LocalHandle;

        // Querier high above any baked navmesh.
        auto HighAltitudeTransform = FTransform(FVector(0.0f, 0.0f, 20000.0f));
        utils_transform::Add(LocalHandle, HighAltitudeTransform, ECk_Replication::DoesNotReplicate);

        Issue_Phase1();
    }

    private void Issue_Phase1()
    {
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(200.0f);  // 5x5 = 25 candidates
        // _ProjectOntoNav defaults to false - no projection, all candidates kept.

        // Score-only Distance test - satisfies non-empty requirement without filtering.
        auto DistanceTest = FCk_Eqs_TestParams();
        DistanceTest.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(DistanceTest);

        auto Params = FCk_Eqs_QueryParams(_SelfEntity, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnPhase1Complete"));
        Request.Set_AutoDestroy(true);
        utils_eqs::Request_RunQuery(_SelfEntity, Request);
    }

    UFUNCTION()
    private void OnPhase1Complete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        Assert_True(InResults.Get_HasResults(),
            "SimpleGrid without _ProjectOntoNav should produce candidates regardless of altitude");

        _Phase1CandidateCount = InResults.Get_Candidates().Num();
        Assert_True(_Phase1CandidateCount > 0,
            f"Baseline query should have >0 candidates (got {_Phase1CandidateCount})");

        Issue_Phase2();
    }

    private void Issue_Phase2()
    {
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(200.0f);
        Generator.Set_ProjectOntoNav(true);
        Generator.Set_NavProjectionSearchHalfExtentUu(200.0f);

        auto DistanceTest = FCk_Eqs_TestParams();
        DistanceTest.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(DistanceTest);

        auto Params = FCk_Eqs_QueryParams(_SelfEntity, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnPhase2Complete"));
        Request.Set_AutoDestroy(true);
        utils_eqs::Request_RunQuery(_SelfEntity, Request);
    }

    UFUNCTION()
    private void OnPhase2Complete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        // With _ProjectOntoNav=true at Z=20000uu and no navmesh at that altitude,
        // all candidates fail projection and are dropped -> generator returns 0 candidates
        // -> query broadcasts Failed with empty results.
        Assert_True(InResults.Get_HasResults() == false,
            f"_ProjectOntoNav=true at high altitude should produce 0 candidates (baseline had {_Phase1CandidateCount})");

        FinishSuccess();
    }
}
