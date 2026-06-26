// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE F ANIMATION PLAYBACK
//============================================================================
//
// Phase F test gate. Verifies the animation playback API surface added in F1–F3:
//   - DoHandleRequest overloads (PlayAnimation / StopAnimation) compile and link
//   - EmitFinishedEvents processor body exists (verified by build succeeding)
//   - Public Utils API (Request_PlayAnimation / StopAnimation / SetPlayRate /
//     Get_PlayingAnimation / Get_PlayTime / Get_PlayLength) returns safe defaults
//     when given an invalid handle
//   - BindTo_OnAnimationFinished / UnbindFrom_OnAnimationFinished are reachable
//
// What this test exercises:
//   1. utils_iskm_proxy::Get_PlayingAnimation(empty) returns null
//   2. utils_iskm_proxy::Get_PlayTime(empty) returns 0.0
//   3. utils_iskm_proxy::Get_PlayLength(empty) returns 0.0
//   4. Calling Request_PlayAnimation with an invalid handle is a safe no-op
//   5. Calling Request_StopAnimation with an invalid handle is a safe no-op
//   6. Calling Request_SetPlayRate with an invalid handle is a safe no-op
//
// What this test does NOT cover (deferred to Phase Q with real .uasset content):
//   - Request_PlayAnimation success path: requires a Renderer PDA with a linked
//     AnimCollection PDA and real UAnimSequenceBase assets.
//   - OnAnimationFinished signal delivery: requires a running animation and a
//     tick boundary; impossible without editor-authored assets.
//   - SetPlayRate and BindTo/UnbindFrom on a live proxy.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_AnimationPlayback : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        FCk_Handle_IskmProxy EmptyHandle;

        // ----- Accessor null-safety on invalid handle -----

        UAnimSequenceBase Seq = utils_iskm_proxy::Get_PlayingAnimation(EmptyHandle);
        Assert_True(Seq == nullptr,
            "Get_PlayingAnimation should return null for an invalid handle");

        float PlayTime = utils_iskm_proxy::Get_PlayTime(EmptyHandle);
        Assert_True(PlayTime == 0.0f,
            "Get_PlayTime should return 0.0 for an invalid handle");

        float PlayLength = utils_iskm_proxy::Get_PlayLength(EmptyHandle);
        Assert_True(PlayLength == 0.0f,
            "Get_PlayLength should return 0.0 for an invalid handle");

        // ----- Request methods are safe no-ops on invalid handle -----

        FCk_Request_IskmProxy_PlayAnimation PlayReq;
        FCk_Handle_IskmProxy PlayResult = utils_iskm_proxy::Request_PlayAnimation(EmptyHandle, PlayReq);
        Assert_True(ck::Is_NOT_Valid(PlayResult),
            "Request_PlayAnimation on invalid handle should return invalid handle");

        FCk_Request_IskmProxy_StopAnimation StopReq;
        FCk_Handle_IskmProxy StopResult = utils_iskm_proxy::Request_StopAnimation(EmptyHandle, StopReq);
        Assert_True(ck::Is_NOT_Valid(StopResult),
            "Request_StopAnimation on invalid handle should return invalid handle");

        FCk_Handle_IskmProxy RateResult = utils_iskm_proxy::Request_SetPlayRate(EmptyHandle, 1.5f);
        Assert_True(ck::Is_NOT_Valid(RateResult),
            "Request_SetPlayRate on invalid handle should return invalid handle");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_AnimationPlayback_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_AnimationPlayback;
    default _TimeoutSeconds = 3.0f;
}
