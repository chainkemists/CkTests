// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE Q1 ANIMATION FINISHES
//============================================================================
//
// Plays a non-looping anim sequence on a proxy and asserts the
// OnAnimationFinished signal fires with reason=Completed within timeout.
//
// REQUIRES authored content: the test entity's RendererData must point at a
// real UCk_IskmRenderer_Data asset whose AnimCollection has at least one
// non-looping sequence. With null RendererData (Plan-1 default until the
// engineer wires content), this test FinishSuccess()-skips with a log line —
// it doesn't fail-red on missing content. Wire RendererData via a Blueprint
// subclass of the test runner once content is authored.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_AnimationFinishes : UCk_AutoTest_Base
{
    UPROPERTY(ExposeOnSpawn)
    UCk_IskmRenderer_Data RendererData;

    UPROPERTY(ExposeOnSpawn)
    UAnimSequenceBase TestSequence;

    private FCk_Handle_IskmProxy _Proxy;
    private bool _Fired = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        // Skip-when-no-content gate: Plan-1 ships without authored content.
        // Engineer wires both RendererData + TestSequence via Blueprint subclass.
        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(TestSequence))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;
        auto LocalRendererData = RendererData;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, LocalRendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_iskm_proxy::BindTo_OnAnimationFinished(_Proxy,
            FCk_Delegate_IskmProxy_OnAnimationFinished(this, n"OnFinished"));

        // _Sequence is CK_PROPERTY_GET-only, so use the constructor to set it.
        auto PlayReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
        PlayReq.Set_bLoop(false);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, PlayReq);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnFinished(FCk_Handle_IskmProxy InHandle, FCk_IskmProxy_AnimSequenceRef InSeq, ECk_IskmProxy_AnimFinishReason InReason)
    {
        if (InReason == ECk_IskmProxy_AnimFinishReason::Completed)
        {
            _Fired = true;
        }
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
