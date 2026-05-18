// Language=angelscript

//============================================================================
// CK TAG SET — AUTOMATION TEST: REMOVE ABSENT → NO SIGNAL FIRE
//============================================================================
//
// Pins the no-op contract: Request_RemoveTags with a tag that's NOT in the
// set must be a no-op. No OnTagsChanged fires, no warning escalation in
// tests.
//
// Setup:
//   1. Add a TagSet with initial tag A.
//   2. Wait one frame, bind OnTagsChanged.
//   3. Request_RemoveTags(X) — X is not in the set.
//   4. Wait several ticks; assert OnTagsChanged fire count == 0 and TagA
//      is still present.
//============================================================================

class UCk_AutoTest_TagSet_RemoveAbsent_NoSignalFire : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_TagSet _TagSet;
    private FGameplayTag _TagA;
    private FGameplayTag _TagAbsent;
    private int32 _SignalCount = 0;
    private bool _RemoveRequested = false;
    private int32 _TicksAfterRemove = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _TagA = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.PresentA");
        _TagAbsent = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.TagSet.AbsentX");

        auto Initial = FGameplayTagContainer();
        Initial.AddTag(_TagA);
        _TagSet = utils_tag_set::Add(LocalHandle, Initial, ECk_Replication::DoesNotReplicate);

        WaitOneFrame(n"OnSettled_BeforeBind");
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

        auto AbsentContainer = FGameplayTagContainer();
        AbsentContainer.AddTag(_TagAbsent);
        utils_tag_set::Request_RemoveTags(_TagSet, AbsentContainer);
        _RemoveRequested = true;

        utils_timer::Create_Tick(InTimer, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTagsChanged(
        FCk_Handle_TagSet InTagSet,
        const FGameplayTagContainer&in InTagsAdded,
        const FGameplayTagContainer&in InTagsRemoved)
    {
        if (_RemoveRequested == false) { return; }
        _SignalCount += 1;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_RemoveRequested == false) { return; }

        _TicksAfterRemove += 1;
        if (_TicksAfterRemove < 5) { return; }

        Assert_Equals_Int(_SignalCount, 0,
            "OnTagsChanged must NOT fire when Request_RemoveTags supplies a tag that's not in the set (no-op)");
        Assert_True(utils_tag_set::HasTag(_TagSet, _TagA),
            "TagA must still be present after the absent-remove no-op");

        FinishSuccess();
    }
}
