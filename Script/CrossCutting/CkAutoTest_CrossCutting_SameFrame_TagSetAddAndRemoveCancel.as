// Language=angelscript

//============================================================================
// CK CROSS-CUTTING — AUTOMATION TEST: SAME-FRAME TagSet ADD + REMOVE CANCEL
//============================================================================
//
// Pins the documented same-frame request cancellation contract for TagSet:
//   Add tag X same tick as Remove tag X → final state holds NO X.
//
// The audit allows either of two acceptable signal-side outcomes (zero
// broadcasts, or one with empty add+remove). This test pins the END STATE
// — the tag must not survive — and counts signal fires to surface whichever
// outcome the framework chose so a regression that changes it is visible
// in the assertion message.
//
// Setup:
//   - Add a TagSet with NO initial tags.
//   - Bind OnTagsChanged with a counter.
//   - Issue Request_AddTags(X) then Request_RemoveTags(X) in one tick.
//   - WaitOneFrame for the processor to drain.
//
// Pass: TagSet does NOT contain X; HasTag(X) == false; Get_NumTags == 0.
// Fail: tag survived (regression in same-frame cancel), or NumTags wrong.
//============================================================================

class UCk_AutoTest_CrossCutting_SameFrame_TagSetAddAndRemoveCancel : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_TagSet _TagSet;
    private FGameplayTag _Tag;
    private int32 _SignalCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Tag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Buff");

        auto Initial = FGameplayTagContainer();
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        utils_tag_set::BindTo_OnTagsChanged(
            _TagSet,
            FCk_Delegate_TagSet_OnTagsChanged(this, n"OnTagsChanged"));

        auto AddContainer = FGameplayTagContainer();
        AddContainer.AddTag(_Tag);
        auto RemoveContainer = FGameplayTagContainer();
        RemoveContainer.AddTag(_Tag);

        // Add then remove in same frame — final state must have no tag.
        utils_tag_set::Request_AddTags(_TagSet, AddContainer);
        utils_tag_set::Request_RemoveTags(_TagSet, RemoveContainer);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        _SignalCount++;
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!utils_tag_set::HasTag(_TagSet, _Tag),
            f"After same-frame Add+Remove of the same tag, HasTag must return false (signals observed: {_SignalCount})");
        Assert_Equals_Int(utils_tag_set::Get_NumTags(_TagSet), 0,
            f"After same-frame Add+Remove of the same tag, TagSet must hold zero tags (signals observed: {_SignalCount})");

        FinishSuccess();
    }
}
