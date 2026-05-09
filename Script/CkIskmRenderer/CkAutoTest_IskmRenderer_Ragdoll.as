// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE K RAGDOLL
//============================================================================
//
// Phase K test gate. Verifies the ragdoll API surface added in K1:
//   - BeginRagdoll stub replaced with real body (compile-verified)
//   - New FCk_Request_IskmProxy_EndRagdoll struct + variant entry
//   - Public Utils API (Request_BeginRagdoll / Request_EndRagdoll) is null-safe
//
// What this test exercises:
//   1. Calling Request_BeginRagdoll with an invalid handle is a safe no-op
//   2. Calling Request_EndRagdoll with an invalid handle is a safe no-op
//
// What this test does NOT cover (deferred to Phase Q with real .uasset content):
//   - Ragdoll success path: needs a SkeletalMesh with a PhysicsAsset bound and
//     a live SKMC. The handler short-circuits with a warning if the mesh has
//     no PhysicsAsset.
//   - Pose-source flip to/from Ragdoll on a live proxy.
//   - UpdateTransform exclusion of ragdolling proxies (already gated via
//     TExclude<FTag_IskmProxy_Ragdolling> from Phase E3, but exercising it
//     requires a live proxy with a Movable transform).
//
//============================================================================

class UCk_AutoTest_IskmRenderer_Ragdoll : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        FCk_Handle_IskmProxy EmptyHandle;

        // ----- Request methods are safe no-ops on invalid handle -----

        FCk_Request_IskmProxy_BeginRagdoll BeginReq;
        FCk_Handle_IskmProxy BeginResult = utils_iskm_proxy::Request_BeginRagdoll(EmptyHandle, BeginReq);
        Assert_True(ck::Is_NOT_Valid(BeginResult),
            "Request_BeginRagdoll on invalid handle should return invalid handle");

        FCk_Handle_IskmProxy EndResult = utils_iskm_proxy::Request_EndRagdoll(EmptyHandle);
        Assert_True(ck::Is_NOT_Valid(EndResult),
            "Request_EndRagdoll on invalid handle should return invalid handle");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_Ragdoll_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_Ragdoll;
    default _TimeoutSeconds = 3.0f;
}
