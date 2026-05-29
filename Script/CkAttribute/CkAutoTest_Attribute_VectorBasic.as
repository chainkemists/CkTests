// Language=angelscript

//============================================================================
// CK ATTRIBUTE — AUTOMATION TEST: VECTOR BASIC (ADD + OVERRIDE)
//============================================================================
//
// Vector-side parity with the Float/Integer/Byte Basic tests. Verifies that
// Add round-trips the starting vector through Get_FinalValue, and that
// Request_Override replaces the value (fires OnValueChanged on Current).
//   1. Add a Velocity attribute starting at (10, 20, 30).
//   2. FinalValue should equal (10, 20, 30) immediately.
//   3. Override to (40, 50, 60) -> OnValueChanged fires, FinalValue updates.
//============================================================================

class UCk_AutoTest_Attribute_VectorBasic : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_VectorAttribute _Velocity;
    private bool _Observed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_VectorAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"VectorAttribute.AutoTest_PerComponent"),
            FVector(10.0f, 20.0f, 30.0f));

        _Velocity = utils_vector_attribute::Add(LocalHandle, Params);

        auto Initial = utils_vector_attribute::Get_FinalValue(_Velocity);
        Assert_True(Initial.Equals(FVector(10.0f, 20.0f, 30.0f), 0.01f),
            f"Initial FinalValue should round-trip the starting vector (got {Initial})");

        utils_vector_attribute::BindTo_OnValueChanged(
            _Velocity,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_VectorAttribute_OnValueChanged(this, n"OnValueChanged"));

        utils_vector_attribute::Request_Override(_Velocity, FVector(40.0f, 50.0f, 60.0f));
    }

    UFUNCTION()
    private void OnValueChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_VectorAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }
        if (_Observed) { return; }
        _Observed = true;

        auto Final = utils_vector_attribute::Get_FinalValue(_Velocity);
        Assert_True(Final.Equals(FVector(40.0f, 50.0f, 60.0f), 0.01f),
            f"After override, FinalValue should be (40,50,60) (got {Final})");

        FinishSuccess();
    }
}
