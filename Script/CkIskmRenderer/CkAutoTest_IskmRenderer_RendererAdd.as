// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: PHASE D RENDERER ADD
//============================================================================
//
// Phase D test gate. Verifies the public Renderer API
// (UCk_Utils_IskmRenderer_UE) added in D4 plus the typesafe handle from D1.
//
// What this test exercises:
//   1. Has(handle) on a fresh entity returns false (no renderer added).
//   2. Get_RendererData(invalid handle) returns nullptr (early-out on
//      handle.IsValid()).
//   3. Get_AnimCollection(invalid handle) returns nullptr (chained null
//      check through Get_RendererData).
//   4. The C++ types compile and link as expected: FCk_Handle_IskmRenderer
//      default-constructs as invalid; UCk_Utils_IskmRenderer_UE statics are
//      callable from AS.
//   5. The Setup processor is registered (CK_REGISTER_PROCESSOR) - verified
//      transitively by the build succeeding.
//
// What this test does NOT cover (deferred to Phase Q with real .uasset
// content):
//   - Add() success path: requires a Renderer PDA whose _AnimCollection
//     field is wired to a valid AnimCollection PDA. Both fields are
//     BlueprintReadOnly so AS can't construct a fully-linked pair from
//     scratch; that requires editor-authored assets.
//   - Setup-processor side effects: verifying that after Add() and a tick,
//     the renderer's _RendererActor is wired to the manager actor allocated
//     via the subsystem.
//   - Add() failure paths (null PDA, PDA without AnimCollection): both
//     paths fire CK_ENSURE_IF_NOT, which we avoid here to keep the test
//     deterministic on the AutoTest harness's ensure-handling policy.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_RendererAdd : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // ----- Fresh entity has no renderer -----

        Assert_True(utils_iskm_renderer::Has(LocalHandle) == false,
            "Has() should return false on an entity with no renderer added");

        // ----- Default-constructed handle is invalid -----

        FCk_Handle_IskmRenderer EmptyHandle;
        Assert_True(ck::Is_NOT_Valid(EmptyHandle),
            "Default-constructed FCk_Handle_IskmRenderer should be invalid");

        // ----- Get_* accessors are null-safe on invalid handles -----

        Assert_True(utils_iskm_renderer::Get_RendererData(EmptyHandle) == nullptr,
            "Get_RendererData(invalid handle) should return nullptr (early-out on handle.IsValid())");

        Assert_True(utils_iskm_renderer::Get_AnimCollection(EmptyHandle) == nullptr,
            "Get_AnimCollection(invalid handle) should return nullptr (chained null-check via Get_RendererData)");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_RendererAdd_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_RendererAdd;
    default _TimeoutSeconds = 3.0f;
}
