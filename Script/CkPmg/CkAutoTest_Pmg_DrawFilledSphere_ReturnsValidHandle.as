// Language=angelscript

//============================================================================
// CK PMG — AUTOMATION TEST: DRAW FILLED SPHERE RETURNS VALID HANDLE
//============================================================================
//
// First-coverage seed for CkPmg. The Pmg drawing primitives spawn debug
// shape entities tracked by a returned FCk_Handle_Pmg_DebugShape. The
// minimum contract: the returned handle is valid for at least the
// requested duration (here, 0.0s means one frame). The most fundamental
// verification is that the handle is valid immediately after Draw.
//============================================================================

class UCk_AutoTest_Pmg_DrawFilledSphere_ReturnsValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Shape = utils_pmg_basic_shapes::DrawFilledSphere(
            FVector(0.0f, 0.0f, 0.0f),
            25.0f, 12, 12,
            FLinearColor::White,
            true, 2.0f, ECk_Plane_Axis::XY, 0.5f);

        Assert_True(ck::IsValid(Shape),
            "DrawFilledSphere should return a valid FCk_Handle_Pmg_DebugShape");

        FinishSuccess();
    }
}
