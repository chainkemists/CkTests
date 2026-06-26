// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q1 ANIMATION FINISHES
//============================================================================
//
// Plays a non-looping anim sequence on a proxy and asserts the
// OnAnimationFinished signal fires with reason=Completed within timeout.
//
// Pulls iskm_assets::RendererData_Demo() (AS-authored, in CkIskmRenderer_Assets.as)
// and assets::load::MM_Jump() (registry-generated). Either invalid →
// FinishSuccess()-skip. With both present, the real assertion runs.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_AnimationFinishes : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private bool _Fired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        UAnimSequenceBase TestSequence = assets::load::MM_Jump();

        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(TestSequence))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_iskm_proxy::BindTo_OnAnimationFinished(_Proxy,
            FCk_Delegate_IskmProxy_OnAnimationFinished(this, n"OnFinished"));

        auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
        PlayReq.Set_Loop(false);
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
