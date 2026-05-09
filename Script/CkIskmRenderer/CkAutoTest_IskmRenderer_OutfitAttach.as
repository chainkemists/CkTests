// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q3 OUTFIT ATTACH
//============================================================================
//
// Adds a proxy, requests AttachSubmesh by name, and after one tick asserts
// Get_NumAttachedSubmeshes incremented.
//
// REQUIRES authored content: the RendererData must have at least one entry
// in _Submeshes whose name matches SubmeshNameToAttach. With null or missing
// content, the handler's Find_SubmeshIndex_ByName returns INDEX_NONE and the
// attach is a no-op — so the test FinishSuccess()-skips on missing content.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_OutfitAttach : UCk_AutoTest_Base
{
    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    UPROPERTY(ExposeOnSpawn)
    FName SubmeshNameToAttach;

    private FCk_Handle_IskmProxy _Proxy;
    private int32 _TicksWaited = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (ck::Is_NOT_Valid(RendererData) || SubmeshNameToAttach == NAME_None)
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto LocalRendererData = RendererData;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, LocalRendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_iskm_proxy::Request_AttachSubmesh(_Proxy, SubmeshNameToAttach);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksWaited++;
        // Wait 2 ticks for Setup + HandleRequests to run.
        if (_TicksWaited < 2) { return; }

        const auto NumAttached = utils_iskm_proxy::Get_NumAttachedSubmeshes(_Proxy);
        Assert_True(NumAttached >= 1, "Submesh attach should leave at least one attached submesh");
        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_OutfitAttach_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_OutfitAttach;
    default _TimeoutSeconds = 5.0f;
}
