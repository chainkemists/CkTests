// Language=angelscript
//
// CK MATH - AUTOMATION TEST: Get_FlattenedAndNormalized degenerate + happy path
// A vector that collapses to zero when flattened must come back as ZeroVector
// not a non-unit residue (regression guard: FVector::Normalize() leaves
// near-zero input unchanged; the utility now uses GetSafeNormal). A regular
// vector must come back unit length with the flattened axis stripped.

class UCk_AutoTest_Math_Vector3_FlattenedAndNormalized : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        const float Tol = 0.001f;

        // Degenerate: a pure-Z vector flattened onto XY collapses to zero
        // (UCk_Utils_Vector3_UE is a ScriptMixin on FVector - call as a method)
        auto Degenerate = FVector(0, 0, 5).Get_FlattenedAndNormalized(ECk_Plane_Axis::XY);
        Assert_True(Degenerate.IsNearlyZero(),
            "Flattening a pure-Z vector onto XY must return ZeroVector, not a non-unit residue");

        // Happy path: unit length, flattened axis stripped
        auto Unit = FVector(3, 4, 12).Get_FlattenedAndNormalized(ECk_Plane_Axis::XY);
        Assert_True(Math::Abs(Unit.Size() - 1.0f) < Tol,
            "Flattened+normalized vector must be unit length");
        Assert_True(Math::Abs(Unit.Z) < Tol,
            "XY-flattened vector must have zero Z");

        FinishSuccess();
    }
}
