// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE - AUTOMATION TEST: ON BEGIN DESTROY CALLBACK
//============================================================================
//
// Verifies that OnBeginDestroy fires when an entity is destroyed via
// Request_DestroyEntity:
//   1. Create a child entity.
//   2. Bind OnBeginDestroy with a delegate.
//   3. Request_DestroyEntity on the child.
//   4. Expect the callback to fire and finish the test.
//
// Mirrors the single-destroy path in CkEntityLifecycleGym_DestroyCallbacks.
//============================================================================

class UCk_AutoTest_EntityLifecycle_OnBeginDestroy : UCk_AutoTest_Base
{
    private FCk_Handle _Child;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        _Child = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        utils_handle::Set_DebugName(_Child, n"AutoTest_DestroyChild");

        utils_entity_lifetime::BindTo_OnBeginDestroy(_Child,
            FCk_Delegate_OnBeginDestroy(this, n"OnChildBeginDestroy"));

        utils_entity_lifetime::Request_DestroyEntity(_Child);
    }

    UFUNCTION()
    private void OnChildBeginDestroy(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        Assert_True(true, "OnBeginDestroy should fire after Request_DestroyEntity");
        FinishSuccess();
    }
}
