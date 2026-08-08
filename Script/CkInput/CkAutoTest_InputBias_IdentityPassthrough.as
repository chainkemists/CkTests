// Language=angelscript

//============================================================================
// CK INPUT BIAS — AUTOMATION TEST: AN UNDECLARED AXIS IS NOT TOUCHED
//============================================================================
//
// The default of the conditioning stage is "do nothing". A game declares bias
// for the two or three axes it cares about; every other axis on the device
// must arrive at consumers exactly as the device reported it, and must still
// be SAMPLED — an axis with no bias is passed through, not skipped.
//
// The never-sampled reading is pinned in the same test because it is the one
// value a consumer will read before any input arrives: zero, from no samples,
// not zero from a deadzone.
//============================================================================

class UCk_AutoTest_InputBias_IdentityPassthrough : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputBias   _Bias;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        Assert_True(ck::IsValid(_Bias),
            "InputBias Add on an InputSource entity should return a valid FCk_Handle_InputBias");
        Assert_Equals_Int(utils_input_bias::Get_AxisBiases(_Bias).Num(), 0,
            "a bias composed with no declared rows starts with an empty conditioning table");
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.0f, 0.0001f,
            "an axis no event has ever arrived for reads zero — derived from no samples, not from a deadzone");

        Add_Step(          "inject an unbiased axis sample",              n"Step_InjectAxis");
        Add_Step_WaitUntil("the sample reaches the conditioned state",    n"Check_AxisSampled");
        Add_Step(          "assert the value passed through untouched",   n"Step_AssertIdentity");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectAxis(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            EKeys::Gamepad_LeftX,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(0.35f);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertIdentity(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.35f, 0.0001f,
            "an axis with no declared bias must condition to its raw value exactly");
        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.35f, 0.0001f,
            "the raw half of the sample records what the producer reported");

        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_RightX), 0.0f, 0.0001f,
            "sampling one axis must not invent a reading for a different one");

        auto Absent = utils_input_bias::TryGet_AxisBias(_Bias, EKeys::Gamepad_LeftX);
        Assert_True(!(Absent.Get_AxisKey() == EKeys::Gamepad_LeftX),
            "an axis that was conditioned by the identity must still report NO declared bias");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_AxisSampled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.35f, 0.0001f));
    }
}
