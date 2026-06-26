// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE H OUTFIT SUBMESH
//============================================================================
//
// Phase H test gate. Verifies the outfit-submesh API surface added in H1/H2:
//   - 3 new request types in the variant (Attach/Detach/DetachAll)
//   - 3 DoHandleRequest overloads (compile/link verified by build)
//   - Public Utils API (Request_AttachSubmesh / Request_DetachSubmesh /
//     Request_DetachAllSubmeshes / Get_NumAttachedSubmeshes) is null-safe
//
// What this test exercises:
//   1. utils_iskm_proxy::Get_NumAttachedSubmeshes(empty) returns 0
//   2. Calling Request_AttachSubmesh with an invalid handle is a safe no-op
//   3. Calling Request_DetachSubmesh with an invalid handle is a safe no-op
//   4. Calling Request_DetachAllSubmeshes with an invalid handle is a safe no-op
//
// What this test does NOT cover (deferred to Phase Q with real .uasset content):
//   - Attach success path: requires a Renderer PDA whose _Submeshes array has
//     entries with valid Mesh assets and matching Names.
//   - MaxSubmeshPerInstance enforcement: requires attaching 16 submeshes to
//     hit the cap, which needs editor-authored asset content.
//   - Submesh fan-out of custom data: Phase G's writer already routes to
//     submeshes; this test only covers the attach side.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_OutfitSubmesh : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        FCk_Handle_IskmProxy EmptyHandle;

        // ----- Accessor null-safety on invalid handle -----

        int32 NumAttached = utils_iskm_proxy::Get_NumAttachedSubmeshes(EmptyHandle);
        Assert_True(NumAttached == 0,
            "Get_NumAttachedSubmeshes should return 0 for an invalid handle");

        // ----- Request methods are safe no-ops on invalid handle -----

        FCk_Handle_IskmProxy AttachResult = utils_iskm_proxy::Request_AttachSubmesh(EmptyHandle, n"Hat");
        Assert_True(ck::Is_NOT_Valid(AttachResult),
            "Request_AttachSubmesh on invalid handle should return invalid handle");

        FCk_Handle_IskmProxy DetachResult = utils_iskm_proxy::Request_DetachSubmesh(EmptyHandle, n"Hat");
        Assert_True(ck::Is_NOT_Valid(DetachResult),
            "Request_DetachSubmesh on invalid handle should return invalid handle");

        FCk_Handle_IskmProxy DetachAllResult = utils_iskm_proxy::Request_DetachAllSubmeshes(EmptyHandle);
        Assert_True(ck::Is_NOT_Valid(DetachAllResult),
            "Request_DetachAllSubmeshes on invalid handle should return invalid handle");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_OutfitSubmesh_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_OutfitSubmesh;
    default _TimeoutSeconds = 3.0f;
}
