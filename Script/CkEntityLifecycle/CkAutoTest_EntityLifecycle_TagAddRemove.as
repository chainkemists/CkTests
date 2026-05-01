// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: TAG ADD / REMOVE
//============================================================================
//
// Verifies the entity-tag API:
//   1. Add a tag to a child entity, TryGet_Tag returns the same tag.
//   2. ForEach_Entity(parent, tag) finds the child.
//   3. Request_TryRemove returns Succeeded.
//   4. ForEach_Entity returns empty after removal.
//
// Removal is request-based (Request_TryRemove), so we poll ForEach until
// the child no longer matches. Harness timeout catches the regression case.
//
// Mirrors CkEntityLifecycleGym_TagSystem.
//============================================================================

class UCk_AutoTest_EntityLifecycle_TagAddRemove : UCk_AutoTest_Base
{
    private FCk_Handle _SelfHandle;
    private FCk_Handle _Child;
    private FName _TestTag = n"AutoTest_TagAlpha";

    private bool _RemovalRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        _Child = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_handle::Set_DebugName(_Child, n"AutoTest_TagChild");

        // Phase 1: Add tag and verify both via TryGet and ForEach.
        utils_entity_tag::Add(_Child, _TestTag);

        auto Retrieved = utils_entity_tag::TryGet_Tag(_Child);
        Assert_True(Retrieved == _TestTag,
            f"TryGet_Tag should return the added tag (got '{Retrieved.ToString()}')");

        auto FoundBefore = utils_entity_tag::ForEach_Entity(_SelfHandle, _TestTag);
        Assert_True(FoundBefore.Num() >= 1,
            f"ForEach_Entity should find at least 1 child with tag '{_TestTag}' (got {FoundBefore.Num()})");

        // Phase 2: Request removal. We poll on a tick callback until ForEach
        // no longer returns the child.
        auto RemoveResult = utils_entity_tag::Request_TryRemove(_Child, _TestTag);
        Assert_True(RemoveResult == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove should report Succeeded on a tag that exists");
        _RemovalRequested = true;

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (!_RemovalRequested) { return; }

        auto FoundAfter = utils_entity_tag::ForEach_Entity(_SelfHandle, _TestTag);
        if (FoundAfter.Num() == 0)
        {
            Assert_True(true, "ForEach_Entity should be empty after Request_TryRemove processes");
            FinishSuccess();
        }
    }
}
