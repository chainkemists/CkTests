// Language=angelscript

//============================================================================
// CK A-STAR — AUTOMATION TEST: NO PATH (GOAL FULLY BLOCKED)
//============================================================================
//
// Verifies the failure path:
//   1. Add a 5x5 search from (0,0) to (4,4).
//   2. Block every cell adjacent to the goal so no approach is possible:
//      (3,4), (4,3), (3,3) — three blockers wall off the (4,4) corner.
//   3. Request_StartSearch.
//   4. Poll until terminal.
//   5. Status == Failed; Get_Path is empty.
//
// API surface verified: Request_BlockCell, Failed status path.
//============================================================================

class UCk_AutoTest_AStar_NoPath : UCk_AutoTest_Base
{
    private FCk_Handle_AStarTest _Search;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Search = utils_a_star_test::Add(LocalHandle, 5, 5, 0, 0, 4, 4, 0);

        // Wall off the goal corner: every neighbour of (4,4) is blocked.
        utils_a_star_test::Request_BlockCell(_Search, 3, 4);
        utils_a_star_test::Request_BlockCell(_Search, 4, 3);
        utils_a_star_test::Request_BlockCell(_Search, 3, 3);

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

        Assert_True(Status == ECk_AStarSearchStatus::Failed,
            f"Search with goal fully walled-off should report Failed (got {Status})");

        auto Path = utils_a_star_test::Get_Path(_Search);
        Assert_Equals_Int(Path.Num(), 0,
            "Path should be empty when no route exists");

        FinishSuccess();
    }
}
