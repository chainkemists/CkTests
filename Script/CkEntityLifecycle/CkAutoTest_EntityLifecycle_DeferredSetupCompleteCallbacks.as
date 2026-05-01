// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: DEFERRED ENTITY COMPLETE CALLBACKS
//============================================================================
//
// Verifies the deferred-entity completion contract:
//   1. Create a deferred entity.
//   2. Bind OnSetupComplete and OnFullyComplete.
//   3. Request_CompleteSetup.
//   4. Both callbacks fire.
//
// Pattern: bind both delegates, issue Request_CompleteSetup, finish only
// when BOTH callbacks have been observed — single-callback fire could
// indicate one of the two signals regressed silently.
//
// Mirrors phases 1-2 of CkEntityLifecycleGym_DeferredSetup.
//============================================================================

class UCk_AutoTest_EntityLifecycle_DeferredSetupCompleteCallbacks : UCk_AutoTest_Base
{
    private FCk_Handle_DeferredEntity _Deferred;
    private bool _SetupCompleteFired = false;
    private bool _FullyCompleteFired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        _Deferred = utils_deferred_entity::Create(LocalHandle);

        utils_deferred_entity::BindTo_OnSetupComplete(
            _Deferred,
            FCk_Delegate_DeferredEntity_OnComplete(this, n"OnSetupComplete"));
        utils_deferred_entity::BindTo_OnFullyComplete(
            _Deferred,
            FCk_Delegate_DeferredEntity_OnFullyComplete(this, n"OnFullyComplete"));

        utils_deferred_entity::Request_CompleteSetup(_Deferred);
    }

    UFUNCTION()
    private void OnSetupComplete(FCk_Handle_DeferredEntity InDeferredEntity)
    {
        if (IsFinished()) { return; }
        _SetupCompleteFired = true;
        TryFinish();
    }

    UFUNCTION()
    private void OnFullyComplete(FCk_Handle_DeferredEntity InDeferredEntity)
    {
        if (IsFinished()) { return; }
        _FullyCompleteFired = true;
        TryFinish();
    }

    private void TryFinish()
    {
        if (!_SetupCompleteFired || !_FullyCompleteFired) { return; }

        Assert_True(_SetupCompleteFired,
            "OnSetupComplete should fire after Request_CompleteSetup");
        Assert_True(_FullyCompleteFired,
            "OnFullyComplete should fire after Request_CompleteSetup");
        FinishSuccess();
    }
}
