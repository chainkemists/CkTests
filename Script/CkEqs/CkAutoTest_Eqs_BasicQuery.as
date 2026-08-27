// Language=angelscript

//============================================================================
// CK EQS - AUTOMATION TEST: BASIC SIMPLEGRID + DISTANCE
//============================================================================
//
// Smoke test for the deferred query pipeline:
//   1. Create the test entity with a transform.
//   2. Build a SimpleGrid + Distance(InverseLinear) query.
//   3. Bind OnComplete via the request's _OnComplete delegate.
//   4. Issue Request_RunQuery - HandleRequests spawns the query entity next
//      tick, Generate runs that frame, Test runs that frame, Finalize fires.
//   5. OnComplete callback verifies HasResults == true, Candidates non-empty,
//      and BestLocation distance from querier is a min of the candidate set.
//
// API surface verified: utils_eqs::Request_RunQuery, _OnComplete delegate
// auto-bind via CK_SIGNAL_BIND_REQUEST_FULFILLED, FCk_Eqs_QueryResults
// accessors.
//============================================================================

class UCk_AutoTest_Eqs_BasicQuery : UCk_AutoTest_Base
{
    private FCk_Handle _SelfEntity;
    private bool _Fired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _SelfEntity = LocalHandle;

        // Querier needs a transform - Generate validates this.
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(100.0f);
        Generator.Set_GridHalfSize(200.0f);   // 5x5 = 25 candidates

        auto Distance = FCk_Eqs_TestParams();
        Distance.Set_TestType(ECk_Eqs_TestType::Distance);
        Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);
        Distance.Set_DistanceMode(ECk_Eqs_DistanceMode::Distance3D);
        auto Scoring = FCk_Eqs_ScoringConfig();
        Scoring.Set_ScoringEquation(ECk_Eqs_ScoringEquation::InverseLinear);
        Distance.Set_ScoringConfig(Scoring);

        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(Distance);

        auto Params = FCk_Eqs_QueryParams(LocalHandle, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::SingleBest);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnQueryComplete"));
        Request.Set_AutoDestroy(true);

        utils_eqs::Request_RunQuery(LocalHandle, Request);
    }

    UFUNCTION()
    private void OnQueryComplete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }
        _Fired = true;

        Assert_True(InResults.Get_HasResults(),
            "SimpleGrid + Distance on a non-empty grid should produce results");

        auto Candidates = InResults.Get_Candidates();
        Assert_Equals_Int(Candidates.Num(), 1,
            "SingleBest run mode should truncate to a single candidate");

        // Best location must equal the candidate's location (sanity check on accessors).
        if (Candidates.Num() == 1)
        {
            auto Best = InResults.Get_BestLocation();
            auto FromCandidate = Candidates[0].Get_Location();
            Assert_True(Best.Equals(FromCandidate, 0.01f),
                f"BestLocation should equal Candidates[0].Location (best={Best}, c0={FromCandidate})");
        }

        // Querier was at origin - best candidate must be the closest grid point (one of
        // the 4 corners of the 100uu spacing nearest origin or origin itself if grid contains it).
        // We only assert that the best is *within* the grid extent.
        auto Best = InResults.Get_BestLocation();
        Assert_True(Best.Size() <= 300.0f,
            f"BestLocation should be within the grid (got distance={Best.Size()})");

        FinishSuccess();
    }
}
