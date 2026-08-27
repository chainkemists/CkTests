// Language=angelscript

//============================================================================
// CK A-STAR - AUTOMATION TEST: COST THRESHOLD TERMINATION
//============================================================================
//
// Verifies the cost-threshold early-termination path:
//   1. Add a 10x10 search from (0,0) to (9,9) - natural path cost is
//      roughly the Manhattan distance ~18 (depending on diagonal cost).
//   2. Set_CostThreshold to 1.0f - any non-trivial path will exceed this.
//   3. Request_StartSearch.
//   4. Poll until terminal.
//   5. Status == CostThresholdReached.
//
// API surface verified: Set_CostThreshold, CostThresholdReached status path.
//============================================================================

class UCk_AutoTest_AStar_CostThreshold : UCk_AutoTest_Base
{
    private FCk_Handle_AStarTest _Search;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Search = utils_a_star_test::Add(LocalHandle, 10, 10, 0, 0, 9, 9, 0);
        utils_a_star_test::Set_CostThreshold(_Search, 1.0f);
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

        Assert_True(Status == ECk_AStarSearchStatus::CostThresholdReached,
            f"Search with low cost threshold should terminate as CostThresholdReached (got {Status})");

        FinishSuccess();
    }
}
