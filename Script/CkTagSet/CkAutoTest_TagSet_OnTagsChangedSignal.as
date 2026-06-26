// Language=angelscript

//============================================================================
// CK TAG SET — AUTOMATION TEST: ON-TAGS-CHANGED SIGNAL
//============================================================================
//
// Verifies BindTo_OnTagsChanged fires when Request_AddTags lands:
//   1. Add a TagSet with no initial tags.
//   2. Bind OnTagsChanged.
//   3. Request_AddTags with one tag.
//   4. Callback fires with the added tag in InTagsAdded and an empty
//      InTagsRemoved.
//
// Pins down the change-notification contract — gameplay code that
// reacts to behavior-tag changes (status effects, conditional abilities)
// relies on this signal firing.
//============================================================================

class UCk_AutoTest_TagSet_OnTagsChangedSignal : UCk_AutoTest_Base
{
    private FCk_Handle_TagSet _TagSet;
    private FGameplayTag _AddedTag;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _AddedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Buff");

        auto Initial = FGameplayTagContainer();
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        utils_tag_set::BindTo_OnTagsChanged(
            _TagSet,
            FCk_Delegate_TagSet_OnTagsChanged(this, n"OnTagsChanged"));

        auto AddContainer = FGameplayTagContainer();
        AddContainer.AddTag(_AddedTag);
        utils_tag_set::Request_AddTags(_TagSet, AddContainer);
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        if (IsFinished()) { return; }

        Assert_True(InTagsAdded.HasTagExact(_AddedTag),
            "OnTagsChanged InTagsAdded should contain the newly-added tag");
        Assert_True(InTagsRemoved.IsEmpty(),
            "OnTagsChanged InTagsRemoved should be empty when only adding");

        FinishSuccess();
    }
}
