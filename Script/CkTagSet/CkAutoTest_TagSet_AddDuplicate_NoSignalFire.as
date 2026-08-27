// Language=angelscript

//============================================================================
// CK TAG SET - AUTOMATION TEST: ADD DUPLICATE -> NO SIGNAL FIRE
//============================================================================
//
// Pins the no-op contract: Request_AddTags with a tag that's already present
// must NOT fire OnTagsChanged. Adding an already-present tag is a no-op at
// the set level; downstream consumers shouldn't see a spurious event.
//
// Setup:
//   1. Add a TagSet with initial tag A.
//   2. Wait one frame, bind OnTagsChanged (skip the initial-add signal).
//   3. Request_AddTags(A) - duplicate.
//   4. Wait several ticks; assert OnTagsChanged fire count == 0.
//============================================================================

class UCk_AutoTest_TagSet_AddDuplicate_NoSignalFire : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_TagSet _TagSet;
    private FGameplayTag _TagA;
    private int32 _SignalCount = 0;
    private bool _DuplicateRequested = false;
    private int32 _TicksAfterDuplicate = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.DupA");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(_TagA);
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        // Wait for the initial-add bookkeeping to be observable before binding,
        // so the bind cannot catch the initial-add signal. Waiting on the tag
        // actually being present states the precondition; a hop count would
        // only guess at how many passes the add takes.
        WaitUntil(n"Check_InitialTagPresent", n"OnSettled_BeforeBind");
    }

    UFUNCTION()
    private void Check_InitialTagPresent(
        FCk_Handle InHandle,
        FCk_SharedBool OutResult,
        FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_TagSet) && utils_tag_set::HasTag(_TagSet, _TagA));
    }

    UFUNCTION()
    private void OnSettled_BeforeBind(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        utils_tag_set::BindTo_OnTagsChanged(
            _TagSet,
            FCk_Delegate_TagSet_OnTagsChanged(this, n"OnTagsChanged"));

        // Duplicate add.
        auto Dup = FGameplayTagContainer();
        Dup.AddTag(_TagA);
        utils_tag_set::Request_AddTags(_TagSet, Dup);
        _DuplicateRequested = true;

        utils_timer::Create_Tick(InTimer, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        if (_DuplicateRequested == false) { return; }
        _SignalCount += 1;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_DuplicateRequested == false) { return; }

        _TicksAfterDuplicate += 1;
        if (_TicksAfterDuplicate < 5) { return; }

        Assert_Equals_Int(_SignalCount, 0,
            "OnTagsChanged must NOT fire when Request_AddTags supplies a tag that's already present (no-op)");
        Assert_True(utils_tag_set::HasTag(_TagSet, _TagA),
            "TagA must still be present after the duplicate-add no-op");

        FinishSuccess();
    }
}
