// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: TAG ADD / REMOVE
//============================================================================
//
// Verifies the entity-tag API:
//   1. Add a tag to a child entity, Has reports true (after pump drains).
//   2. ForEach_Entity(parent, tag) finds the child.
//   3. Request_TryRemove returns Succeeded.
//   4. ForEach_Entity returns empty after removal.
//
// Both Add and Request_TryRemove are deferred via the EntityTag request pump
// (see CkEntityTag/Claude.md "Timing"), so observable state (Has,
// ForEach_Entity) is checked after WaitOneFrame.
//============================================================================

class UCk_AutoTest_EntityLifecycle_TagAddRemove : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

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

        utils_entity_tag::Add(_Child, _TestTag);
        WaitOneFrame(n"AfterAdd");
    }

    UFUNCTION()
    private void AfterAdd(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_entity_tag::Has(_Child, _TestTag),
            f"Has should report the added tag '{_TestTag}' after the pump drains");

        auto FoundBefore = utils_entity_tag::ForEach_Entity(_SelfHandle, _TestTag);
        Assert_True(FoundBefore.Num() >= 1,
            f"ForEach_Entity should find at least 1 child with tag '{_TestTag}' (got {FoundBefore.Num()})");

        // Request_TryRemove returns Succeeded whenever the handle is valid (post-deferred-refactor
        // contract; the per-tag presence check happens inside the processor and silently no-ops
        // on absent tags).
        auto RemoveResult = utils_entity_tag::Request_TryRemove(_Child, _TestTag);
        Assert_True(RemoveResult == ECk_SucceededFailed::Succeeded,
            "Request_TryRemove should report Succeeded on a valid handle");
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
