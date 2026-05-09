// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q1 ANIMATION FINISHES
//============================================================================
//
// Plays a non-looping anim sequence on a proxy and asserts the
// OnAnimationFinished signal fires with reason=Completed within timeout.
//
// Auto-loads:
//   /CkTests/CkIskmRenderer/Demo/RendererData_Demo  (UCk_IskmRenderer_Data)
//   /CkTests/CkIskmRenderer/Anim/MM_Jump            (UAnimSequence — non-looping)
//
// Either asset missing → test FinishSuccess()-skips. With both present, the
// real assertion runs.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_AnimationFinishes : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private bool _Fired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto RendererResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Demo/RendererData_Demo",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto RendererData = Cast<UCk_IskmRenderer_Data>(RendererResult._Asset);

        auto SeqResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/MM_Jump",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto TestSequence = Cast<UAnimSequenceBase>(SeqResult._Asset);

        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(TestSequence))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_iskm_proxy::BindTo_OnAnimationFinished(_Proxy,
            FCk_Delegate_IskmProxy_OnAnimationFinished(this, n"OnFinished"));

        auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
        PlayReq.Set_bLoop(false);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, PlayReq);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnFinished(FCk_Handle_IskmProxy InHandle, FCk_IskmProxy_AnimSequenceRef InSeq, ECk_IskmProxy_AnimFinishReason InReason)
    {
        if (InReason == ECk_IskmProxy_AnimFinishReason::Completed)
        { _Fired = true; }
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Fired) { FinishSuccess(); }
    }
}

class ACk_AutoTest_IskmRenderer_AnimationFinishes_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_AnimationFinishes;
    default _TimeoutSeconds = 8.0f;
}
