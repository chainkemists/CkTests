// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE E PROXY ADD
//============================================================================
//
// Phase E test gate. Verifies the proxy public API surface added in E4
// (UCk_Utils_IskmProxy_UE::Add / Has) plus the typesafe handle from E1
// (FCk_Handle_IskmProxy).
//
// What this test exercises:
//   1. utils_iskm_proxy::Has(InHandle) on a fresh entity returns false (no
//      proxy added).
//   2. A default-constructed FCk_Handle_IskmProxy is invalid.
//   3. The C++ types compile and link as expected: the 5 proxy processors
//      (Setup / HandleRequests / UpdateTransform / EmitFinishedEvents /
//      EndPlay) are registered via CK_REGISTER_PROCESSOR (verified
//      transitively by the build succeeding) AND the 5 DoHandleRequest
//      stubs added in the E3 fixup keep the visitor template instantiating
//      cleanly.
//
// What this test does NOT cover (deferred to Phase Q with real .uasset
// content):
//   - Add() success path: requires a Renderer PDA whose _AnimCollection
//     field is wired to a valid AnimCollection PDA. Both fields are
//     BlueprintReadOnly so AS can't construct a fully-linked pair from
//     scratch; that requires editor-authored assets.
//   - Setup processor side effects: verifying that after Add() and a tick,
//     the proxy's _BaseSKMC is wired to a SKMC from the manager actor's
//     pool, and FTag_IskmProxy_Movable is set per ParamsData._IsMovable.
//   - Add() failure path with an invalid Renderer: would fire
//     CK_ENSURE_IF_NOT, which we avoid here for deterministic harness
//     behaviour (same as RendererAdd.as).
//   - Request_* dispatching: handlers are stubs at E3; real bodies arrive
//     in F (PlayAnimation/StopAnimation), J (montages), K (ragdoll).
//
//============================================================================

class UCk_AutoTest_IskmRenderer_ProxyAdd : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // ----- Fresh entity has no proxy -----

        Assert_True(utils_iskm_proxy::Has(LocalHandle) == false,
            "Has() should return false on an entity with no proxy added");

        // ----- Default-constructed handle is invalid -----

        FCk_Handle_IskmProxy EmptyHandle;
        Assert_True(ck::Is_NOT_Valid(EmptyHandle),
            "Default-constructed FCk_Handle_IskmProxy should be invalid");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_ProxyAdd_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_ProxyAdd;
    default _TimeoutSeconds = 3.0f;
}
