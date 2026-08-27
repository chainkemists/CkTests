// Language=angelscript

//============================================================================
// CK ISKM RENDERER - AUTOMATION TEST: PHASE I ANIMBP PATH
//============================================================================
//
// Phase I test gate. Verifies the AnimBP-mode API surface added in I1:
//   - FCk_Request_IskmProxy_SetAnimInstanceClass struct compiles & is in variant
//   - DoHandleRequest overload links
//   - Public Utils API (Request_SetAnimInstanceClass / Get_PoseSource) is null-safe
//
// What this test exercises:
//   1. utils_iskm_proxy::Get_PoseSource(empty) returns ECk_IskmProxy_PoseSource::Sequence
//      (the default - invalid handle yields the safe baseline pose source)
//   2. Calling Request_SetAnimInstanceClass with an invalid handle is a safe no-op
//
// What this test does NOT cover (deferred to Phase Q with real .uasset content):
//   - Pose-source flip after Request_SetAnimInstanceClass(valid class): requires
//     a live proxy + an AnimBP class to verify _PoseSource transitions to AnimBP.
//   - nullptr-fallback to UCk_IskmNotify_AnimInstance: needs a live SKMC.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_AnimBP : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        FCk_Handle_IskmProxy EmptyHandle;

        // ----- Accessor null-safety on invalid handle -----

        ECk_IskmProxy_PoseSource Pose = utils_iskm_proxy::Get_PoseSource(EmptyHandle);
        Assert_True(Pose == ECk_IskmProxy_PoseSource::Sequence,
            "Get_PoseSource should return Sequence (default) for an invalid handle");

        // ----- Request method is a safe no-op on invalid handle -----

        TSubclassOf<UAnimInstance> NullClass;
        FCk_Handle_IskmProxy SetResult = utils_iskm_proxy::Request_SetAnimInstanceClass(EmptyHandle, NullClass);
        Assert_True(ck::Is_NOT_Valid(SetResult),
            "Request_SetAnimInstanceClass on invalid handle should return invalid handle");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_AnimBP_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_AnimBP;
    default _TimeoutSeconds = 3.0f;
}
