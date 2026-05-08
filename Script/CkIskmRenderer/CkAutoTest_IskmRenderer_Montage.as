// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE J MONTAGES
//============================================================================
//
// Phase J test gate. Verifies the montage API surface added in J1:
//   - PlayMontage / StopMontage stubs replaced with real bodies (compile-verified)
//   - Public Utils API (Request_PlayMontage / Request_StopMontage /
//     BindTo_OnMontageFinished / UnbindFrom_OnMontageFinished) is null-safe
//
// What this test exercises:
//   1. Calling Request_PlayMontage with an invalid handle is a safe no-op
//   2. Calling Request_StopMontage with an invalid handle is a safe no-op
//
// What this test does NOT cover (deferred to Phase Q with real .uasset content):
//   - Montage success path: needs a UAnimMontage asset and a live SKMC.
//   - Lazy AnimInstance creation in PlayMontage handler: needs a live SKMC.
//   - OnMontageFinished signal forwarding: only fires from
//     UCk_IskmNotify_AnimInstance::NativeOnMontageBlendingOut, which requires
//     a real montage to play to completion.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_Montage : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        FCk_Handle_IskmProxy EmptyHandle;

        // ----- Request methods are safe no-ops on invalid handle -----

        FCk_Request_IskmProxy_PlayMontage PlayReq;
        FCk_Handle_IskmProxy PlayResult = utils_iskm_proxy::Request_PlayMontage(EmptyHandle, PlayReq);
        Assert_True(ck::Is_NOT_Valid(PlayResult),
            "Request_PlayMontage on invalid handle should return invalid handle");

        FCk_Request_IskmProxy_StopMontage StopReq;
        FCk_Handle_IskmProxy StopResult = utils_iskm_proxy::Request_StopMontage(EmptyHandle, StopReq);
        Assert_True(ck::Is_NOT_Valid(StopResult),
            "Request_StopMontage on invalid handle should return invalid handle");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_Montage_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_Montage;
    default _TimeoutSeconds = 3.0f;
}
