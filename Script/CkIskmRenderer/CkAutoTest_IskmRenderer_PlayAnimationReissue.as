// Language=angelscript

//============================================================================
// CK ISKM RENDERER — REGRESSION TEST: PlayAnimation re-issue preserves AnimInstance
//============================================================================
//
// Guards against a subtle render-proxy desync where re-issuing
// Request_PlayAnimation on a sequence-mode proxy tore down the freshly-created
// UAnimSingleNodeInstance because the handler unconditionally called
// SKMC->SetAnimInstanceClass(nullptr) — even when AnimClass was already null.
// Game-thread state remained consistent (signals fired correctly) but the
// render proxy never resynced, leaving the visible mesh in ref pose ("A-pose").
//
// Test strategy: framework signals can't detect the bug (they fire either
// way), so we observe the AnimInstance pointer identity via the diagnostic
// utility. With the fix, the SingleNodeInstance is preserved across
// re-issues. Without it, the pointer changes.
//
// The fix lives in FProcessor_IskmProxy_HandleRequests::DoHandleRequest for
// FCk_Request_IskmProxy_PlayAnimation — see CkIskmProxy_Processor.cpp where
// the SetAnimInstanceClass(nullptr) call is guarded by AnimClass != nullptr.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_PlayAnimationReissue : UCk_AutoTest_Base
{
    private FCk_Handle_IskmProxy _Proxy;
    private UAnimInstance _AnimInstanceBeforeReissue;
    private int32 _Phase = 0;
    private int32 _TicksInPhase = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        UCk_IskmRenderer_Data RendererData = iskm_assets::RendererData_Demo();
        UAnimSequenceBase TestSequence = assets::load::MM_Idle();

        if (ck::Is_NOT_Valid(RendererData) || ck::Is_NOT_Valid(TestSequence))
        { FinishSuccess(); return; }

        auto LocalHandle = InHandle;

        auto Renderer = utils_iskm_renderer::Add(LocalHandle, RendererData);
        auto Params = FCk_Fragment_IskmProxy_ParamsData(Renderer, FTransform::Identity);
        _Proxy = utils_iskm_proxy::Add(LocalHandle, Params);

        // Flip to sequence mode so PlayAnimation drives the SKMC.
        TSubclassOf<UAnimInstance> NullClass;
        utils_iskm_proxy::Request_SetAnimInstanceClass(_Proxy, NullClass);

        // First PlayAnimation: this creates the UAnimSingleNodeInstance.
        auto FirstReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
        FirstReq.Set_Loop(true);
        utils_iskm_proxy::Request_PlayAnimation(_Proxy, FirstReq);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksInPhase++;

        if (_Phase == 0 && _TicksInPhase >= 2)
        {
            // Setup + first PlayAnimation request have processed. Capture the
            // AnimInstance pointer that the SingleNodeInstance instance.
            _AnimInstanceBeforeReissue = _Proxy.Get_AnimInstance();

            // Re-issue the SAME PlayAnimation. Without the fix, this tears down
            // and recreates the SingleNodeInstance; with the fix, it's preserved.
            UAnimSequenceBase TestSequence = assets::load::MM_Idle();
            auto ReissueReq = FCk_Request_IskmProxy_PlayAnimation(TestSequence);
            ReissueReq.Set_Loop(true);
            utils_iskm_proxy::Request_PlayAnimation(_Proxy, ReissueReq);

            _Phase = 1;
            _TicksInPhase = 0;
        }
        else if (_Phase == 1 && _TicksInPhase >= 2)
        {
            // Re-issue has been processed. Compare pointers.
            auto AnimInstanceAfterReissue = _Proxy.Get_AnimInstance();

            Assert_True(ck::IsValid(_AnimInstanceBeforeReissue),
                "AnimInstance should be valid after the first PlayAnimation — proxy Setup wired up the SingleNodeInstance");

            Assert_True(ck::IsValid(AnimInstanceAfterReissue),
                "AnimInstance should still be valid after PlayAnimation re-issue");

            Assert_True(_AnimInstanceBeforeReissue == AnimInstanceAfterReissue,
                "Re-issuing PlayAnimation must NOT recreate the UAnimSingleNodeInstance — pointer identity must be preserved. If this fails, the SetAnimInstanceClass(nullptr) guard in the handler regressed and visible meshes will snap to ref pose on re-issue.");

            FinishSuccess();
        }
    }
}

class ACk_AutoTest_IskmRenderer_PlayAnimationReissue_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_PlayAnimationReissue;
    default _TimeoutSeconds = 5.0f;
}
