// Language=angelscript

//============================================================================
// CK TAG SET — AUTOMATION TEST: bulk-remove fires OnTagsChanged once
//============================================================================
//
// Pins the "clear-all signal count" contract: bulk-removing every tag
// on a TagSet via a single Request_RemoveTags(allTagsContainer) fires
// OnTagsChanged ONCE — not once per tag — with InTagsRemoved carrying
// all previously-held tags.
//
// CkTagSet has no dedicated `Request_Clear` / `RemoveAll`; the canonical
// way to clear is to pass an FGameplayTagContainer of every current tag
// to Request_RemoveTags. The processor coalesces all removes in the
// frame's request batch into a single OnTagsChanged broadcast
// (CkTagSet_Processor.cpp:27–48).
//
// Flow:
//   1. Add a TagSet pre-populated with 3 tags.
//   2. Bind OnTagsChanged.
//   3. Build a container with the 3 tags + Request_RemoveTags(it).
//   4. WaitOneFrame.
//   5. Assert: fired exactly once, InTagsRemoved contains all 3.
//============================================================================

class UCk_AutoTest_TagSet_ClearAll_FiresSignalOnce : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private FCk_Handle_TagSet _TagSet;
    private FGameplayTag _TagA;
    private FGameplayTag _TagB;
    private FGameplayTag _TagC;
    private int32 _FireCount = 0;
    private int32 _RemovedCount = 0;
    private bool _SawA = false;
    private bool _SawB = false;
    private bool _SawC = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.ClearAll.A");
        _TagB = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.ClearAll.B");
        _TagC = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.ClearAll.C");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(_TagA);
        Initial.AddTag(_TagB);
        Initial.AddTag(_TagC);
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        utils_tag_set::BindTo_OnTagsChanged(
            _TagSet,
            FCk_Delegate_TagSet_OnTagsChanged(this, n"OnTagsChanged"));

        auto AllTags = FGameplayTagContainer();
        AllTags.AddTag(_TagA);
        AllTags.AddTag(_TagB);
        AllTags.AddTag(_TagC);
        utils_tag_set::Request_RemoveTags(_TagSet, AllTags);

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        _FireCount += 1;
        _RemovedCount = InTagsRemoved.Num();
        if (InTagsRemoved.HasTagExact(_TagA)) { _SawA = true; }
        if (InTagsRemoved.HasTagExact(_TagB)) { _SawB = true; }
        if (InTagsRemoved.HasTagExact(_TagC)) { _SawC = true; }
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_FireCount, 1,
            "OnTagsChanged should fire exactly once for a bulk Request_RemoveTags clearing all 3 tags");
        Assert_Equals_Int(_RemovedCount, 3,
            "InTagsRemoved should carry all 3 previously-held tags in a single payload");
        Assert_True(_SawA && _SawB && _SawC,
            "InTagsRemoved should contain each of the three cleared tags (A, B, C)");

        FinishSuccess();
    }
}
