// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: TRANSITION REPLACED EVENT
//============================================================================
//
// Plays sequence A (looping), then mid-loop swaps to sequence B. Asserts that
// the OnAnimationFinished signal fired with reason=Replaced for the swap.
//
// This is the only test that exercises the Replaced path in Phase F's
// PlayAnimation handler — Q1 covers Completed, Phase F's StopAnimation covers
// Stopped, but Replaced (interrupting a still-playing sequence) had no
// coverage until this test.
//
// Auto-loads:
//   /CkTests/CkIskmRenderer/Demo/RendererData_Demo  (UCk_IskmRenderer_Data)
//   /CkTests/CkIskmRenderer/Anim/MM_Idle            (UAnimSequence — looping)
//   /CkTests/CkIskmRenderer/Anim/MM_Jump            (UAnimSequence — non-looping)
//
// Either asset missing → test FinishSuccess()-skips.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_TransitionReplaced : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private UAnimSequenceBase _SeqA;
    private UAnimSequenceBase _SeqB;
    private bool _ReplacedFired = false;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto RendererResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Demo/RendererData_Demo",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        auto RendererData = Cast<UCk_IskmRenderer_Data>(RendererResult._Asset);

        auto AResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/MM_Idle",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        _SeqA = Cast<UAnimSequenceBase>(AResult._Asset);

        auto BResult = utils_i_o::LoadAssetByName(
            "/CkTests/CkIskmRenderer/Anim/MM_Jump",
            ECk_AssetSearchScope::Plugins,
            ECk_AssetSearchStrategy::ExactOnly);
        _SeqB = Cast<UAnimSequenceBase>(BResult._Asset);

        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(_SeqA) || ck::Is_NOT_Valid(_SeqB))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        utils_iskm_proxy::BindTo_OnAnimationFinished(_Proxy,
            FCk_Delegate_IskmProxy_OnAnimationFinished(this, n"OnFinished"));

        // Phase 0 setup: kick off seq A (looping).
        auto ReqA = FCk_Request_IskmProxy_PlayAnimation(_SeqA);
        ReqA.Set_bLoop(true);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, ReqA);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnFinished(FCk_Handle_IskmProxy InHandle, FCk_IskmProxy_AnimSequenceRef InSeq, ECk_IskmProxy_AnimFinishReason InReason)
    {
        if (InReason == ECk_IskmProxy_AnimFinishReason::Replaced)
        {
            _ReplacedFired = true;
        }
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            // Seq A is now active. Swap to seq B → handler should fire Replaced for A.
            auto ReqB = FCk_Request_IskmProxy_PlayAnimation(_SeqB);
            ReqB.Set_bLoop(false);
            utils_iskm_proxy::Request_PlayAnimation(_Proxy, ReqB);
            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            Assert_True(_ReplacedFired,
                "After swapping seq B over still-playing seq A, OnAnimationFinished should fire with reason=Replaced");
            FinishSuccess();
        }
    }
}

class ACk_AutoTest_IskmRenderer_TransitionReplaced_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_TransitionReplaced;
    default _TimeoutSeconds = 5.0f;
}
