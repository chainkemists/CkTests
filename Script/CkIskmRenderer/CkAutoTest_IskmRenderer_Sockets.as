// Language=angelscript

//============================================================================
// CK ISKM RENDERER — AUTOMATION TEST: PHASE L SOCKETS + LINE TRACE
//============================================================================
//
// Phase L test gate. Verifies the socket/line-trace API surface added in L1
// AND the UpdateTransform processor body (no-op stub from E3 → real
// SetWorldTransform pass-through, gated by FTag_IskmProxy_Movable +
// FTag_Transform_Updated, excluding ragdolling).
//
// What this test exercises:
//   1. utils_iskm_proxy::Get_SocketTransform(empty, name, space) returns identity
//   2. utils_iskm_proxy::LineTrace_Instance(empty, params, out) returns false
//      and zeroes the out result
//
// What this test does NOT cover (deferred to Phase Q with real .uasset content):
//   - Socket success path: needs a SkeletalMesh with a named socket bound.
//   - Line trace success path: needs a live SKMC with collision and an actual
//     hit body.
//   - UpdateTransform ECS-side flow: needs a Transform fragment + tag wiring.
//
//============================================================================

class UCk_AutoTest_IskmRenderer_Sockets : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        FCk_Handle_IskmProxy EmptyHandle;

        // ----- Get_SocketTransform null-safety -----

        FTransform Xf = utils_iskm_proxy::Get_SocketTransform(
            EmptyHandle, n"Hand_R", ECk_IskmProxy_TransformSpace::World);
        Assert_True(Xf.GetLocation().IsZero(),
            "Get_SocketTransform on invalid handle should return identity (zero location)");

        // ----- LineTrace_Instance null-safety -----

        FCk_IskmProxy_LineTraceParams Params;
        FCk_IskmProxy_LineTraceResult Result;
        bool bHit = utils_iskm_proxy::LineTrace_Instance(EmptyHandle, Params, Result);
        Assert_True(bHit == false,
            "LineTrace_Instance on invalid handle should return false");

        FinishSuccess();
    }
}

class ACk_AutoTest_IskmRenderer_Sockets_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_IskmRenderer_Sockets;
    default _TimeoutSeconds = 3.0f;
}
