// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: Vector attribute clamps per-component
//============================================================================
//
// Pins the per-component clamp contract on a Vector attribute: each of
// X / Y / Z is clamped to its own [Min.X, Max.X] / [Min.Y, Max.Y] /
// [Min.Z, Max.Z] range independently. An override of (200, 50, -50)
// against bounds Min=(0,0,0) Max=(100,100,100) must yield FinalValue
// (100, 50, 0):
//   - X 200 → clamps DOWN to Max.X=100.
//   - Y 50  → stays (in-band).
//   - Z -50 → clamps UP to Min.Z=0.
//
// Catches the regression where Vector clamp uses scalar bounds (one
// dimension's clamp leaking to all three) or treats the whole vector
// as in-band if its magnitude is within range.
//
// Closes the Vector per-component clamp audit gap (third of four
// CkAttribute gaps).
//============================================================================

class UCk_AutoTest_Attribute_VectorPerComponentClamp : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 2.0f;

    private FCk_Handle_VectorAttribute _Attr;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_VectorAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"VectorAttribute.AutoTest_PerComponent"),
            FVector(50.0f, 50.0f, 50.0f));
        Params.Set_MinMax(ECk_MinMax::MinMax);
        Params.Set_MinValue(FVector(0.0f, 0.0f, 0.0f));
        Params.Set_MaxValue(FVector(100.0f, 100.0f, 100.0f));

        _Attr = utils_vector_attribute::Add(LocalHandle, Params);

        // Override one component above Max (X), one in-band (Y), one below
        // Min (Z). Final value must clamp each independently.
        utils_vector_attribute::Request_Override(_Attr, FVector(200.0f, 50.0f, -50.0f));

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Final = utils_vector_attribute::Get_FinalValue(_Attr);

        Assert_True(Final.X == 100.0f,
            f"X above Max=100 should clamp to 100 (got {Final.X})");
        Assert_True(Final.Y == 50.0f,
            f"Y in-band should stay at 50 (got {Final.Y})");
        Assert_True(Final.Z == 0.0f,
            f"Z below Min=0 should clamp to 0 (got {Final.Z})");

        FinishSuccess();
    }
}
