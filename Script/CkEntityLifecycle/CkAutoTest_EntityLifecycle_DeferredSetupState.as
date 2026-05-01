// Language=angelscript

//============================================================================
// CK ENTITY LIFECYCLE — AUTOMATION TEST: DEFERRED ENTITY CREATE STATE
//============================================================================
//
// Bundled smoke test for the synchronous query surface on a freshly-created
// deferred entity:
//   1. Create deferred entity, expect handle valid.
//   2. Get_IsDeferred returns true while pending.
//   3. Has(deferred-as-handle) returns true.
//   4. DoCast on the underlying handle returns a populated optional.
//
// All operations resolve in the same DoBeginPlay frame — no callbacks
// involved. The deferred-completion side (OnSetupComplete / OnFullyComplete
// after Request_CompleteSetup) lives in DeferredSetupCompleteCallbacks.
//
// Mirrors phase 0 of CkEntityLifecycleGym_DeferredSetup.
//============================================================================

class UCk_AutoTest_EntityLifecycle_DeferredSetupState : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Deferred = utils_deferred_entity::Create(LocalHandle);
        Assert_True(Deferred.IsValid(),
            "utils_deferred_entity::Create should return a valid handle");

        Assert_True(utils_deferred_entity::Get_IsDeferred(Deferred),
            "Get_IsDeferred should return true on a freshly-created deferred entity");

        auto AsHandle = FCk_Handle(Deferred);
        Assert_True(utils_deferred_entity::Has(AsHandle),
            "Has(deferred-as-handle) should return true on a fresh deferred entity");

        auto CastResult = utils_deferred_entity::DoCast(AsHandle);
        Assert_True(CastResult.IsSet(),
            "DoCast on a deferred-entity handle should return a populated optional");

        FinishSuccess();
    }
}
