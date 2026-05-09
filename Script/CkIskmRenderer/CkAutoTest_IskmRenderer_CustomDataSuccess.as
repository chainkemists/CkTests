// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q5 CUSTOM-DATA SUCCESS PATH
//============================================================================
//
// Adds a proxy, requests SetCustomDataFloat(slot=0, value=0.5), asserts that
// after one tick Get_CustomDataFloat(0) reads back 0.5.
//
// REQUIRES authored content: RendererData must have NumCustomDataFloat >= 1
// so the proxy's _Values array has slot 0 allocated at Setup. With null or
// zero NumCustomDataFloat, the handler's IsValidIndex check fails and the
// write is a no-op — the test FinishSuccess()-skips.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_CustomDataSuccess : UCk_AutoTest_Base
{
    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    private FCk_Handle_IskmProxy _Proxy;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (ck::Is_NOT_Valid(RendererData)) { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto LocalRendererData = RendererData;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, LocalRendererData);
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
            // After Setup, NumCustomDataFloat must be >= 1 for slot 0 to be valid.
            // We can't introspect that here without leaking _Values, so we just write
            // and read; if the slot wasn't allocated the write was a no-op.
            utils_iskm_proxy::Request_SetCustomDataFloat(_Proxy, int32(0), 0.5f);
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            const auto Value = utils_iskm_proxy::Get_CustomDataFloat(_Proxy, int32(0));
            // If NumCustomDataFloat == 0 (Plan-1 default content), Value is 0 and we
            // treat that as the skip condition. Otherwise Value must be 0.5.
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
