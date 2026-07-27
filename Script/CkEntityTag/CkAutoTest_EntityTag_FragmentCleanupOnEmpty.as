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
//
// Every phase crosses a real observable transition (0→2 tags, 2→0, 0→1), so
// all three settles are condition waits rather than fixed delays.
//============================================================================

class UCk_AutoTest_EntityTag_FragmentCleanupOnEmpty : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle _Entity;
    private FName _TagA = n"AutoTestEt_Cleanup_A";
    private FName _TagB = n"AutoTestEt_Cleanup_B";

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Entity = InHandle;

        utils_entity_tag::Add(_Entity, _TagA);
        utils_entity_tag::Add(_Entity, _TagB);

        Add_Step_WaitUntil("both tags become listed",              n"Check_BothListed");
        Add_Step(          "remove both tags",                     n"Step_RemoveBoth");
        Add_Step_WaitUntil("the tag set empties",                  n"Check_NoTags");
        Add_Step(          "assert the cleanup, then re-add TagA", n"Step_AssertCleanupAndReAdd");
        Add_Step_WaitUntil("the re-added tag becomes present",     n"Check_TagAPresent");
        Add_Step(          "assert the fragment came back clean",  n"Step_AssertReAdd");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RemoveBoth(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_entity_tag::Get_AllTags(_Entity).Num(), 2,
            "Get_AllTags must list two tags after two distinct Adds");

        utils_entity_tag::Request_TryRemove(_Entity, _TagA);
        utils_entity_tag::Request_TryRemove(_Entity, _TagB);
    }

    UFUNCTION()
    private void Step_AssertCleanupAndReAdd(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(!utils_entity_tag::Has(_Entity, _TagA),
            "Has(TagA) must be false after all removes");
        Assert_True(!utils_entity_tag::Has(_Entity, _TagB),
            "Has(TagB) must be false after all removes");

        utils_entity_tag::Add(_Entity, _TagA);
    }

    UFUNCTION()
    private void Step_AssertReAdd(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_entity_tag::Get_AllTags(_Entity).Num(), 1,
            "Get_AllTags must report exactly one tag after re-Add");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_BothListed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Get_AllTags(_Entity).Num() >= 2);
    }

    UFUNCTION()
    private void Check_NoTags(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Get_AllTags(_Entity).Num() == 0);
    }

    UFUNCTION()
    private void Check_TagAPresent(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_entity_tag::Has(_Entity, _TagA));
    }
}
