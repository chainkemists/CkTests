// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q2 MONTAGE NOTIFY
//============================================================================
//
// Plays a montage on a proxy, asserts both OnAnimationNotify and
// OnMontageFinished fire within timeout.
//
// Auto-loads:
//   /CkTests/CkIskmRenderer/Demo/RendererData_Demo  (UCk_IskmRenderer_Data)
//   /CkTests/CkIskmRenderer/Anim/AM_NotifyTest      (UAnimMontage with >=1 notify)
//
// Either asset missing → test FinishSuccess()-skips.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_MontageNotify : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private bool _NotifyFired = false;
    private bool _MontageFinished = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto RendererResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Demo/RendererData_Demo",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto RendererData = Cast<UCk_IskmRenderer_Data>(RendererResult._Asset);

        auto MontageResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/AM_NotifyTest",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto TestMontage = Cast<UAnimMontage>(MontageResult._Asset);

        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(TestMontage))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_iskm_proxy::BindTo_OnAnimationNotify(_Proxy,
            FCk_Delegate_IskmProxy_OnAnimationNotify(this, n"OnNotify"));
        utils_iskm_proxy::BindTo_OnMontageFinished(_Proxy,
            FCk_Delegate_IskmProxy_OnMontageFinished(this, n"OnMontageEnd"));

        auto MontageReq = FCk_Request_IskmProxy_PlayMontage(TestMontage);
        utils_iskm_proxy::Request_PlayMontage(_Proxy, MontageReq);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnNotify(FCk_Handle_IskmProxy InHandle, FName InNotifyName)
    { _NotifyFired = true; }

    UFUNCTION()
    private void OnMontageEnd(FCk_Handle_IskmProxy InHandle, FCk_IskmProxy_MontageRef InMontage, bool bWasInterrupted)
    { _MontageFinished = true; }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_NotifyFired && _MontageFinished) { FinishSuccess(); }
    }
}

class ACk_AutoTest_IskmRenderer_MontageNotify_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_MontageNotify;
    default _TimeoutSeconds = 10.0f;
}
