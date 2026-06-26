// Language=angelscript

//============================================================================
// CK EQS — AUTOMATION TEST: ONCIRCLE GENERATOR
//============================================================================
//
// Verifies ECk_Eqs_GeneratorType::OnCircle produces the correct ring geometry:
//   1. OnCircle: Radius=300, NumPoints=8, ArcAngle=360 → 8 evenly-spaced
//      candidates on a flat ring at the querier's Z.
//   2. AllMatching with a neutral Score-only Distance test returns all 8.
//   3. Each candidate must be within 1cm of radius 300 from the querier.
//   4. Partial arc: ArcAngle=180 → 8 candidates across a half-ring. The
//      generator uses ArcAngle/NumPoints (= 22.5deg step here, matching the
//      Donut convention); points span [-90,90] less one final step.
//============================================================================

class UCk_AutoTest_Eqs_OnCircle : UCk_AutoTest_Base
{
    private FCk_Handle _SelfEntity;
    private FVector    _QuerierLocation;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SelfEntity = LocalHandle;

        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        _QuerierLocation = FVector(0.0f, 0.0f, 0.0f);

        Issue_FullCircle();
    }

    private void Issue_FullCircle()
    {
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::OnCircle);
        Generator.Set_CircleRadius(300.0f);
        Generator.Set_NumPointsOnCircle(8);
        Generator.Set_CircleArcAngle(360.0f);

        auto DistanceTest = FCk_Eqs_TestParams();
        DistanceTest.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(DistanceTest);

        auto Params = FCk_Eqs_QueryParams(_SelfEntity, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnFullCircleComplete"));
        Request.Set_AutoDestroy(true);
        utils_eqs::Request_RunQuery(_SelfEntity, Request);
    }

    UFUNCTION()
    private void OnFullCircleComplete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        Assert_True(InResults.Get_HasResults(),
            "OnCircle (radius=300, 8 points, 360deg) should produce 8 candidates");

        Assert_Equals_Int(InResults.Get_Candidates().Num(), 8,
            f"OnCircle 360deg should produce exactly 8 candidates (got {InResults.Get_Candidates().Num()})");

        // Every candidate must be on the ring — distance from querier ≈ 300cm.
        auto Candidates = InResults.Get_Candidates();
        for (int32 i = 0; i < Candidates.Num(); i++)
        {
            auto Loc = Candidates[i].Get_Location();
            auto Dist2D = FVector2D(Loc.X - _QuerierLocation.X, Loc.Y - _QuerierLocation.Y).Size();
            Assert_True(Math::Abs(Dist2D - 300.0f) < 1.0f,
                f"Candidate {i} should be 300cm from querier (got {Dist2D}cm)");
        }

        // Phase 2: half-arc.
        Issue_HalfArc();
    }

    private void Issue_HalfArc()
    {
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::OnCircle);
        Generator.Set_CircleRadius(300.0f);
        Generator.Set_NumPointsOnCircle(8);
        Generator.Set_CircleArcAngle(180.0f);   // half arc

        auto DistanceTest = FCk_Eqs_TestParams();
        DistanceTest.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(DistanceTest);

        auto Params = FCk_Eqs_QueryParams(_SelfEntity, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::AllMatching);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnHalfArcComplete"));
        Request.Set_AutoDestroy(true);
        utils_eqs::Request_RunQuery(_SelfEntity, Request);
    }

    UFUNCTION()
    private void OnHalfArcComplete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        Assert_True(InResults.Get_HasResults(),
            "OnCircle half-arc should produce candidates");

        Assert_Equals_Int(InResults.Get_Candidates().Num(), 8,
            f"OnCircle 180deg arc with NumPoints=8 should still produce 8 candidates (got {InResults.Get_Candidates().Num()})");

        // All should still be on the ring.
        auto Candidates = InResults.Get_Candidates();
        for (int32 i = 0; i < Candidates.Num(); i++)
        {
            auto Loc = Candidates[i].Get_Location();
            auto Dist2D = FVector2D(Loc.X - _QuerierLocation.X, Loc.Y - _QuerierLocation.Y).Size();
            Assert_True(Math::Abs(Dist2D - 300.0f) < 1.0f,
                f"Half-arc candidate {i} should be 300cm from querier (got {Dist2D}cm)");
        }

        FinishSuccess();
    }
}
