// Language=angelscript

//============================================================================
// CK PMG — AUTOMATION TEST: DRAW FILLED BOX RETURNS VALID HANDLE
//============================================================================
//
// Box variant of the DrawFilledSphere seed. utils_pmg_basic_shapes::DrawFilledBox
// must return a valid FCk_Handle_Pmg_DebugShape on call.
//============================================================================

class UCk_AutoTest_Pmg_DrawFilledBox_ReturnsValidHandle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Shape = utils_pmg_basic_shapes::DrawFilledBox(
            FVector(0.0f, 0.0f, 0.0f),
            FVector(30.0f, 30.0f, 30.0f),
            FLinearColor::Red,
            true, 2.0f, ECk_Plane_Axis::XY, 0.5f);

        Assert_True(ck::IsValid(Shape),
            "DrawFilledBox should return a valid FCk_Handle_Pmg_DebugShape");

        FinishSuccess();
    }
}
