// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q5 CUSTOM-DATA SUCCESS PATH
//============================================================================
//
// Requests SetCustomDataFloat(slot=0, value=0.5), asserts that
// Get_CustomDataFloat(0) reads back 0.5 after one tick.
//
// Auto-loads RendererData_Demo. The renderer's _NumCustomDataFloat must be
// >= 1 for slot 0 to be allocated at Setup — otherwise the handler's
// IsValidIndex check fails and the write is a no-op (skip condition).
//
//============================================================================

class UCk_AutoTest_IskmRenderer_CustomDataSuccess : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

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

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            utils_iskm_proxy::Request_SetCustomDataFloat(_Proxy, int32(0), 0.5f);
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            const auto Value = utils_iskm_proxy::Get_CustomDataFloat(_Proxy, int32(0));
            // NumCustomDataFloat == 0 → write was a no-op (skip).
            if (Value == 0.0f) { FinishSuccess(); return; }
            Assert_True(Value == 0.5f,
                "Get_CustomDataFloat(0) should read back the value written via Request_SetCustomDataFloat");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_IskmRenderer_CustomDataSuccess_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_CustomDataSuccess;
    default _TimeoutSeconds = 5.0f;
}
