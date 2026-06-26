// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE G PER-INSTANCE CUSTOM DATA
//============================================================================
//
// Phase G test gate. Verifies the per-instance custom-data API surface added in
// G1 (FCk_Request_IskmProxy_SetCustomDataFloat in the variant + DoHandleRequest
// overload + Request_SetCustomDataFloat / Get_CustomDataFloat Utils methods).
//
// What this test exercises:
//   1. utils_iskm_proxy::Get_CustomDataFloat(empty, 0) returns 0.0
//   2. utils_iskm_proxy::Get_CustomDataFloat(empty, INT32_MAX) returns 0.0 (out-of-range safe)
//   3. Calling Request_SetCustomDataFloat with an invalid handle is a safe no-op
//
// What this test does NOT cover (deferred to Phase Q with real .uasset content):
//   - SetCustomDataFloat success path: requires a Renderer PDA with non-zero
//     _NumCustomDataFloat and an active proxy with allocated SKMC. The handler
//     guards against IsValidIndex(_Offset) which only matters with a real
//     _Values array sized by Setup.
//   - Submesh fan-out: requires attached child SKMCs (Phase H attaches them).
//
//============================================================================

class UCk_AutoTest_IskmRenderer_CustomData : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        FCk_Handle_IskmProxy EmptyHandle;

        // ----- Accessor null-safety on invalid handle -----

        float Slot0 = utils_iskm_proxy::Get_CustomDataFloat(EmptyHandle, 0);
        Assert_True(Slot0 == 0.0f,
            "Get_CustomDataFloat(0) should return 0.0 for an invalid handle");

        float SlotMax = utils_iskm_proxy::Get_CustomDataFloat(EmptyHandle, 99999);
        Assert_True(SlotMax == 0.0f,
            "Get_CustomDataFloat with out-of-range offset should return 0.0 safely");

        // ----- Request method is a safe no-op on invalid handle -----

        FCk_Handle_IskmProxy SetResult = utils_iskm_proxy::Request_SetCustomDataFloat(EmptyHandle, 0, 1.5f);
        Assert_True(ck::Is_NOT_Valid(SetResult),
            "Request_SetCustomDataFloat on invalid handle should return invalid handle");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_CustomData_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_CustomData;
    default _TimeoutSeconds = 3.0f;
}
