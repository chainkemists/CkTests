// Language=angelscript

//============================================================================
// CK ENTITY TAG — AUTOMATION TEST: FRAGMENT CLEANUP ON EMPTY
//============================================================================
//
// After fully removing every tag, Get_AllTags must return an empty array
// (the underlying FFragment_EntityTag_Current is removed when both the
// FName _Tags array and the gameplay-tag _GameplayTagCounts array empty).
//
// Re-adding a tag afterward must work — the fragment must come back
// cleanly, not be left in some half-removed state.
//============================================================================

class UCk_AutoTest_EntityTag_FragmentCleanupOnEmpty : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;
        const FName TagA = n"AutoTestEt_Cleanup_A";
        const FName TagB = n"AutoTestEt_Cleanup_B";

        utils_entity_tag::Add(_Entity, TagA);
        utils_entity_tag::Add(_Entity, TagB);

        WaitOneFrame(n"AfterAdds");
    }

    UFUNCTION()
    private void AfterAdds(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const FName TagA = n"AutoTestEt_Cleanup_A";
        const FName TagB = n"AutoTestEt_Cleanup_B";

        Assert_Equals_Int(utils_entity_tag::Get_AllTags(_Entity).Num(), 2,
            "Get_AllTags must list two tags after two distinct Adds");

        utils_entity_tag::Request_TryRemove(_Entity, TagA);
        utils_entity_tag::Request_TryRemove(_Entity, TagB);

        WaitOneFrame(n"AfterRemoves");
    }

    UFUNCTION()
    private void AfterRemoves(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const FName TagA = n"AutoTestEt_Cleanup_A";
        const FName TagB = n"AutoTestEt_Cleanup_B";

        Assert_Equals_Int(utils_entity_tag::Get_AllTags(_Entity).Num(), 0,
            "Get_AllTags must be empty after removing every tag");
        Assert_True(!utils_entity_tag::Has(_Entity, TagA),
            "Has(TagA) must be false after all removes");
        Assert_True(!utils_entity_tag::Has(_Entity, TagB),
            "Has(TagB) must be false after all removes");

        // Re-add must work — fragment must come back cleanly.
        utils_entity_tag::Add(_Entity, TagA);

        WaitOneFrame(n"AfterReAdd");
    }

    UFUNCTION()
    private void AfterReAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const FName TagA = n"AutoTestEt_Cleanup_A";

        Assert_True(utils_entity_tag::Has(_Entity, TagA),
            "Re-Add after cleanup must work — Has(TagA) true again");
        Assert_Equals_Int(utils_entity_tag::Get_AllTags(_Entity).Num(), 1,
            "Get_AllTags must report exactly one tag after re-Add");

        FinishSuccess();
    }
}
