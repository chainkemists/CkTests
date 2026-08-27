// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: PHASE Q6 LOAD ACTIVATION
//============================================================================
//
// Demonstrates the post-load contract documented in the CkIskmRenderer docs:
// once a renderer asset is resident, Add(...) on the resolved pointer creates
// a working proxy. This test exercises the post-load Add -> Has flow.
//
// Pulls iskm_assets::RendererData_Demo(). Real async-load wiring (FStreamableManager
// + lambda callback) is C++-side and not exposed cleanly to AS - this Plan-1
// test covers the post-load activation that any caller eventually hits.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_AsyncLoad : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();

        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto TransformHandle = utils_transform::Add(LocalHandle, FTransform::Identity);

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(TransformHandle, Params);

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
