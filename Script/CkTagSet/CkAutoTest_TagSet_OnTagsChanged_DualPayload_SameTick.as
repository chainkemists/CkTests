// Language=angelscript

//============================================================================
// CK TAG SET — AUTOMATION TEST: OnTagsChanged dual-payload (add + remove same tick)
//============================================================================
//
// Pins the coalesce contract on FProcessor_TagSet_HandleRequests
// (CkTagSet_Processor.cpp:27–48): when Request_AddTags AND Request_RemoveTags
// land in the same frame, the processor accumulates both into a single
// OnTagsChanged broadcast carrying:
//   - InTagsAdded — the union of newly-added tags.
//   - InTagsRemoved — the union of newly-removed tags.
//
// Closes two audit gaps in one test:
//   - "OnTagsChanged dual-payload" — both payload sides populated in one fire.
//   - "AddRemove same-tick" — same-frame requests coalesce.
//
// Flow:
//   1. Add a TagSet pre-populated with tag A.
//   2. Bind OnTagsChanged with a counter + payload-capture delegate.
//   3. Same frame: Request_AddTags({B}) AND Request_RemoveTags({A}).
//   4. WaitOneFrame for the processor pass.
//   5. Assert: signal fired exactly once, InTagsAdded contains B,
//      InTagsRemoved contains A.
//============================================================================

class UCk_AutoTest_TagSet_OnTagsChanged_DualPayload_SameTick : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private FCk_Handle_TagSet _TagSet;
    private FGameplayTag _TagA;
    private FGameplayTag _TagB;
    private int32 _FireCount = 0;
    private bool _SawAddedB = false;
    private bool _SawRemovedA = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Dual.A");
        _TagB = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.Dual.B");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(_TagA);
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        utils_tag_set::BindTo_OnTagsChanged(
            _TagSet,
            FCk_Delegate_TagSet_OnTagsChanged(this, n"OnTagsChanged"));

        // Same-frame add B + remove A — the processor coalesces these into
        // one broadcast with both payload sides populated.
        auto AddContainer = FGameplayTagContainer();
        AddContainer.AddTag(_TagB);
        utils_tag_set::Request_AddTags(_TagSet, AddContainer);

        auto RemoveContainer = FGameplayTagContainer();
        RemoveContainer.AddTag(_TagA);
        utils_tag_set::Request_RemoveTags(_TagSet, RemoveContainer);

        WaitUntil(n"Check_SignalFired", n"OnSettled");
    }

    UFUNCTION()
    private void Check_SignalFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FireCount >= 1);
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        _FireCount += 1;
        if (InTagsAdded.HasTagExact(_TagB)) { _SawAddedB = true; }
        if (InTagsRemoved.HasTagExact(_TagA)) { _SawRemovedA = true; }
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        Assert_Equals_Int(_FireCount, 1,
            "OnTagsChanged should fire exactly once for same-frame Add+Remove (processor coalesces)");
        Assert_True(_SawAddedB,
            "OnTagsChanged InTagsAdded should contain B (added this frame)");
        Assert_True(_SawRemovedA,
            "OnTagsChanged InTagsRemoved should contain A (removed this frame)");

        FinishSuccess();
    }
}
