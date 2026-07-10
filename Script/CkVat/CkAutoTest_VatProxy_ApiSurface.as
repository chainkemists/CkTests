// Language=angelscript

//============================================================================
// CK VAT — AUTOMATION TEST: API SURFACE
//============================================================================
//
// Verifies the CkVat public surface that is testable WITHOUT editor-authored
// baked content (mirrors CkAutoTest_IskmRenderer_ProxyAdd's scoping):
//   1. utils_vat_proxy::Has() on a fresh entity returns false.
//   2. A default-constructed FCk_Handle_VatProxy is invalid.
//   3. Getters and Request_* on an invalid handle are guarded no-ops (no
//      ensures, no crashes) — the AS mixin surface links and dispatches.
//   4. The three Vat processors registered via CK_REGISTER_PROCESSOR
//      (verified transitively by the module loading).
//
// What this test does NOT cover (Gate 4, needs committed baked content):
//   - Add() success + Setup side effects: requires a BAKED collection
//     (Setup fires CK_ENSURE on unbaked ones — deliberately not triggered
//     here for deterministic harness behaviour) and the generated look
//     masters resolving a render state.
//   - PlayClip/Stop/SetPlayRate state transitions + the 12-float pushes.
//   - OnClipFinished for Once clips.
//   The bake side-effects (SavePackage) make bake-at-test-time unsuitable;
//   the plan is one editor bake of a Mannequin collection committed as
//   content, then an end-to-end playback autotest against it.
//
//============================================================================

class UCk_AutoTest_VatProxy_ApiSurface : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // ----- Fresh entity has no Vat -----

        Assert_True(utils_vat_proxy::Has(LocalHandle) == false,
            "Has() should return false on an entity with no Vat added");

        // ----- Default-constructed handle is invalid -----

        FCk_Handle_VatProxy EmptyHandle;
        Assert_True(ck::Is_NOT_Valid(EmptyHandle),
            "Default-constructed FCk_Handle_VatProxy should be invalid");

        // ----- Getters on an invalid handle are guarded no-ops -----

        Assert_True(utils_vat_proxy::Get_Collection(EmptyHandle) == nullptr,
            "Get_Collection() on an invalid handle should return nullptr");

        Assert_True(utils_vat_proxy::Get_ActiveClipName(EmptyHandle) == NAME_None,
            "Get_ActiveClipName() on an invalid handle should return None");

        // ----- Request_* on an invalid handle are guarded no-ops (chainable, no ensure) -----

        auto PlayRequest = FCk_Request_VatProxy_PlayClip(n"AnyClip");
        auto AfterPlay = utils_vat_proxy::Request_PlayClip(EmptyHandle, PlayRequest);
        Assert_True(ck::Is_NOT_Valid(AfterPlay),
            "Request_PlayClip() on an invalid handle should return the (invalid) handle unchanged");

        auto AfterStop = utils_vat_proxy::Request_Stop(EmptyHandle);
        Assert_True(ck::Is_NOT_Valid(AfterStop),
            "Request_Stop() on an invalid handle should return the (invalid) handle unchanged");

        auto AfterRate = utils_vat_proxy::Request_SetPlayRate(EmptyHandle, 2.0f);
        Assert_True(ck::Is_NOT_Valid(AfterRate),
            "Request_SetPlayRate() on an invalid handle should return the (invalid) handle unchanged");

        FinishSuccess();
    }
}

class ACk_AutoTest_VatProxy_ApiSurface_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_VatProxy_ApiSurface;
    default _TimeoutSeconds = 3.0f;
}
