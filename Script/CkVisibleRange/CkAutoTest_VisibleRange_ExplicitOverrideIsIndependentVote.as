// Language=angelscript

//============================================================================
// CK VISIBLE RANGE — AUTOMATION TEST: explicit override is an independent vote
//============================================================================
//
// FTag_VisibleRange_Hidden is reference-counted (CK_DEFINE_ECS_TAG_COUNTED)
// specifically because "hidden" has two independent sources: the entity's
// own out-of-range state, and an explicit Request_SetVisibility(Hide). This
// test activates BOTH, clears only ONE, and asserts the entity is STILL
// hidden — the exact case a plain (non-counted) tag would get wrong, since
// one source's clear would silently wipe the other source's still-active
// vote. If this test passes with a plain tag substituted in, the contract
// is broken and this assertion is the one that should catch it.
//============================================================================

class UCk_AutoTest_VisibleRange_ExplicitOverrideIsIndependentVote : UCk_AutoTest_Base
{
    private FCk_Handle_VisibleRange _VR;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // MaxRange = 0 (unlimited far); MinRange = 500 means the default distance (0) already
        // violates MinRange — the own-range vote is active from the first evaluated tick, no
        // Update_Distance call needed to arm it.
        auto Params = FCk_Fragment_VisibleRange_ParamsData(0.0f);
        Params.Set_MinRange(500.0f);
        _VR = utils_visible_range::Add(LocalHandle, Params);

        utils_visible_range::Request_SetVisibility(_VR, ECk_VisibleRange_ShowHide::Hide);
        WaitUntil(n"Check_BecameHidden", n"OnBothVotesActive");
    }

    UFUNCTION()
    private void Check_BecameHidden(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_visible_range::Get_IsHidden(_VR));
    }

    UFUNCTION()
    private void OnBothVotesActive(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_True(utils_visible_range::Get_IsHidden(_VR),
            "Should be hidden: own-range (distance 0 < MinRange 500) AND explicit Hide both active");

        // Clear ONLY the explicit vote. The own-range vote (distance still 0) is untouched.
        utils_visible_range::Request_SetVisibility(_VR, ECk_VisibleRange_ShowHide::Show);
        WaitFrames(2, n"OnExplicitVoteCleared");
    }

    UFUNCTION()
    private void OnExplicitVoteCleared(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_visible_range::Get_IsHidden(_VR),
            "Should STILL be hidden — the own-range vote was never cleared. A plain tag would " +
            "incorrectly report visible here since the explicit source's clear would wipe both.");

        // Now clear the own-range vote too (bring distance back inside MinRange).
        utils_visible_range::Update_Distance(_VR, 1000.0f);
        WaitUntil(n"Check_BecameVisible", n"OnBothVotesCleared");
    }

    // Decisive: the entity is hidden on entry (both votes active, then only the
    // explicit one cleared), so this is false until the own-range vote lifts.
    UFUNCTION()
    private void Check_BecameVisible(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_visible_range::Get_IsHidden(_VR) == false);
    }

    UFUNCTION()
    private void OnBothVotesCleared(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_visible_range::Get_IsHidden(_VR),
            "Should be visible now that both independent votes are cleared");
        FinishSuccess();
    }
}
