// Language=angelscript

//============================================================================
// CK A-STAR — AUTOMATION TEST: BASIC SEARCH ON OPEN GRID
//============================================================================
//
// Smoke test for the A* search API:
//   1. Add a 5x5 search from (0,0) to (4,4), no blocked cells.
//   2. Request_StartSearch.
//   3. Poll Get_SearchStatus on each tick until it reaches a terminal
//      state (anything other than Idle / InProgress).
//   4. Verify status == Complete, path is non-empty, total cost > 0.
//
// API surface verified: utils_a_star_test::Add, Request_StartSearch,
// Get_SearchStatus, Get_Path, Get_TotalCost.
//
// Reuses the gym's utils_a_star_test::* utility namespace (the production
// CkAStar API may be exposed differently — this test uses the same path
// the gym uses, so it follows whatever surface the gym is built against).
//============================================================================

class UCk_AutoTest_AStar_BasicSearch : UCk_AutoTest_Base
{
    private FCk_Handle_AStarTest _Search;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Search = utils_a_star_test::Add(LocalHandle, 5, 5, 0, 0, 4, 4, 0);
        utils_a_star_test::Request_StartSearch(_Search);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Status = utils_a_star_test::Get_SearchStatus(_Search);
        if (Status == ECk_AStarSearchStatus::Idle ||
            Status == ECk_AStarSearchStatus::InProgress) { return; }

        Assert_True(Status == ECk_AStarSearchStatus::Complete,
            f"Search on a 5x5 open grid should complete with status Complete (got {Status})");

        auto Path = utils_a_star_test::Get_Path(_Search);
        Assert_True(Path.Num() >= 2,
            f"Path should contain at least start+goal (got {Path.Num()} nodes)");

        auto TotalCost = utils_a_star_test::Get_TotalCost(_Search);
        Assert_True(TotalCost > 0.0f,
            f"TotalCost on a non-trivial path should be > 0 (got {TotalCost})");

        FinishSuccess();
    }
}
