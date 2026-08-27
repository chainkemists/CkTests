// Language=angelscript

//============================================================================
// CK EQS - AUTOMATION TEST: CANCEL MID-QUERY (Pass-3.1 E3)
//============================================================================
//
// Verifies Request_CancelAllQueries flow:
//   1. Build a deferred query with TWO tests on a 441-candidate grid.
//      Two tests at 441 each (882 evaluations) exceeds the per-frame budget
//      of 256, so the query yields between tests - guaranteed multi-frame.
//   2. Bind OnComplete via the request's _OnComplete delegate.
//   3. On every OnTick, attempt CancelAll until it succeeds. Frame N (the
//      enqueue frame) returns 0 because HandleRequests hasn't spawned the
//      query entity yet. Frame N+1 finds the query mid-pipeline (between
//      its first and second test, after the budget yield) and tags it.
//   4. OnComplete fires with empty results + IsFailed == true.
//
// API surface verified: utils_eqs::Request_CancelAllQueries, the FProcessor_
// Eqs_Test cancel-tag handling, and the OnComplete-with-Failed broadcast.
//============================================================================

class UCk_AutoTest_Eqs_Cancel : UCk_AutoTest_Base
{
    private FCk_Handle _Self;
    private int32 _CancelCount = 0;
    private int32 _TickCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Self = LocalHandle;
        utils_transform::Add(LocalHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // 21x21 = 441 candidates - large enough that a 2-test query exceeds
        // the per-frame candidate budget (256) and yields at least once.
        auto Generator = FCk_Eqs_GeneratorParams();
        Generator.Set_GeneratorType(ECk_Eqs_GeneratorType::SimpleGrid);
        Generator.Set_SpaceBetween(50.0f);
        Generator.Set_GridHalfSize(500.0f);

        // Two cheap score tests - Distance + Dot. The pipeline:
        //   Frame N+1 OnTick: cancel issued
        //   Frame N+1 PostTransform: Test sees Cancelled, fails+broadcasts.
        // Without two tests, the budget anti-deadlock would run everything
        // on frame N and OnComplete would fire before our OnTick gets a chance.
        auto Distance = FCk_Eqs_TestParams();
        Distance.Set_TestType(ECk_Eqs_TestType::Distance);
        Distance.Set_Purpose(ECk_Eqs_TestPurpose::Score);

        auto Dot = FCk_Eqs_TestParams();
        Dot.Set_TestType(ECk_Eqs_TestType::Dot);
        Dot.Set_Purpose(ECk_Eqs_TestPurpose::Score);

        auto Tests = TArray<FCk_Eqs_TestParams>();
        Tests.Add(Distance);
        Tests.Add(Dot);

        auto Params = FCk_Eqs_QueryParams(LocalHandle, Generator, Tests);
        Params.Set_RunMode(ECk_Eqs_RunMode::SingleBest);

        auto Request = FCk_Request_Eqs_RunQuery(Params);
        Request.Set_OnComplete(FCk_Delegate_EqsQuery_OnComplete(this, n"OnQueryComplete"));
        Request.Set_AutoDestroy(true);
        utils_eqs::Request_RunQuery(LocalHandle, Request);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _TickCount++;

        // Already cancelled - wait for OnComplete.
        if (_CancelCount > 0) { return; }

        // Try every tick. On the enqueue frame, HandleRequests hasn't run yet
        // and CancelAll returns 0. The next frame the query exists mid-yield
        // and the tag lands.
        _CancelCount = utils_eqs::Request_CancelAllQueries(_Self);

        // Defensive bail-out: if we somehow can't find the query after several
        // ticks, the query likely completed too fast (budget changed?). Failing
        // the test surfaces the timing assumption rather than hanging on the
        // 5-second wrapper timeout.
        if (_TickCount > 10 && _CancelCount == 0)
        {
            FinishFailure(f"CancelAll returned 0 after {_TickCount} ticks - query completed before cancel could land");
        }
    }

    UFUNCTION()
    private void OnQueryComplete(FCk_Handle_EqsQuery InQueryHandle, FCk_Eqs_QueryResults InResults)
    {
        if (IsFinished()) { return; }

        Assert_True(_CancelCount > 0,
            f"Test should have issued a cancel before OnComplete fired (CancelCount={_CancelCount}, TickCount={_TickCount})");

        Assert_True(utils_eqs::Get_IsFailed(InQueryHandle),
            "Cancelled query should have FTag_EqsQuery_Failed");

        Assert_True(InResults.Get_HasResults() == false,
            "Cancelled query should broadcast empty results");

        FinishSuccess();
    }
}
