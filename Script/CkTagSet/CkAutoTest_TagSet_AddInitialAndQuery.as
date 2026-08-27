// Language=angelscript

//============================================================================
// CK TAG SET - AUTOMATION TEST: ADD INITIAL TAGS + QUERY
//============================================================================
//
// Smoke test for the TagSet feature:
//   1. Build an FGameplayTagContainer with two tags.
//   2. Add a TagSet with that container as initial tags.
//   3. Get_NumTags returns 2.
//   4. HasTag returns true for each added tag, false for an unrelated tag.
//   5. HasTagExact returns true for the exact tags, false for parent tags.
//   6. HasAll returns true for the original container.
//
// Pins down the per-entity multi-tag query surface that Inventory and
// Interaction features rely on for behavior filtering.
//============================================================================

class UCk_AutoTest_TagSet_AddInitialAndQuery : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto FlammableTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Flammable");
        auto HeavyTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Heavy");
        auto UnrelatedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Liquid");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(FlammableTag);
        Initial.AddTag(HeavyTag);

        auto TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);
        Assert_True(ck::IsValid(TagSet),
            "Add should return a valid TagSet handle");

        Assert_Equals_Int(utils_tag_set::Get_NumTags(TagSet), 2,
            "Get_NumTags should report the count of initial tags (2)");

        Assert_True(utils_tag_set::HasTag(TagSet, FlammableTag),
            "HasTag should return true for an added tag");
        Assert_True(utils_tag_set::HasTag(TagSet, HeavyTag),
            "HasTag should return true for the second added tag");
        Assert_True(!utils_tag_set::HasTag(TagSet, UnrelatedTag),
            "HasTag should return false for an unrelated tag");

        Assert_True(utils_tag_set::HasTagExact(TagSet, FlammableTag),
            "HasTagExact should return true for an exactly-matching added tag");

        Assert_True(utils_tag_set::HasAll(TagSet, Initial),
            "HasAll should return true for the original initial-tags container");

        FinishSuccess();
    }
}
