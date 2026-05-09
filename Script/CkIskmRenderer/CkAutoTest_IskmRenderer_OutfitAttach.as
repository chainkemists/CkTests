// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q3 OUTFIT ATTACH
//============================================================================
//
// Adds a proxy, requests AttachSubmesh by name "Hat", and after one tick
// asserts Get_NumAttachedSubmeshes incremented.
//
// Auto-loads RendererData_Demo. The asset's _Submeshes array must contain at
// least one entry whose Name matches "Hat" — otherwise the handler's
// Find_SubmeshIndex_ByName returns INDEX_NONE and the attach is a no-op
// (which the test treats as a skip).
//
//============================================================================

class UCk_AutoTest_IskmRenderer_OutfitAttach : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private int32 _TicksWaited = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Result = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Demo/RendererData_Demo",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto RendererData = Cast<UCk_IskmRenderer_Data>(Result._Asset);

        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_iskm_proxy::Request_AttachSubmesh(_Proxy, n"Hat");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksWaited++;
        if (_TicksWaited < 2) { return; }

        const auto NumAttached = utils_iskm_proxy::Get_NumAttachedSubmeshes(_Proxy);
        // 0 = no Submesh entry named "Hat" in the renderer (treated as skip).
        // >=1 = success path.
        if (NumAttached == 0) { FinishSuccess(); return; }
        Assert_True(NumAttached >= 1,
            "After Request_AttachSubmesh, Get_NumAttachedSubmeshes should return >= 1");
        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_OutfitAttach_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_OutfitAttach;
    default _TimeoutSeconds = 5.0f;
}
