// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q6 LOAD ACTIVATION
//============================================================================
//
// Demonstrates the post-load contract documented in CkIskmRenderer Claude.md:
// once a renderer asset is resident (whether resolved via FStreamableManager
// async or hard-loaded), Add(...) on the resolved pointer creates a working
// proxy. This test exercises the post-load Add → Has flow.
//
// REQUIRES authored content: RendererData wired to a real asset. With null,
// the test FinishSuccess()-skips. Real async-load wiring (FStreamableManager
// + lambda callback) is C++-side and not exposed cleanly to AS — this Plan-1
// test covers the flow that any caller eventually hits regardless of whether
// the load was sync or async.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_AsyncLoad : UCk_AutoTest_Base
{
    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private FCk_Handle_IskmProxy _Proxy;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto LocalRendererData = RendererData;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, LocalRendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        Assert_True(utils_iskm_proxy::Has(LocalHandle),
            "After Add, the entity should report Has() == true");
        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_AsyncLoad_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_AsyncLoad;
    default _TimeoutSeconds = 5.0f;
}
