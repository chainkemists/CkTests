// Language=angelscript

//============================================================================
// CK INPUT BIAS - AUTOMATION TEST: INVERSION FLIPS THE VALUE, NOT THE RECORD
//============================================================================
//
// "Invert Y" is the one conditioning setting every player expects to find,
// and it is the one most likely to be implemented by negating at the point of
// use instead of in the stage. Pinning it here means a consumer never has to
// know whether the player inverted anything.
//
// Both directions are injected: an implementation that negates only positive
// deflections, or that clamps to zero on the way through, passes on one
// sample and fails on the other.
//
// The raw half is asserted alongside every conditioned value - inversion is
// the cheapest place to accidentally rewrite the recorded fact.
//============================================================================

class UCk_AutoTest_InputBias_InversionFlipsSign : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputBias   _Bias;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        auto Row = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftY);
        Row.Set_Inversion(ECk_InputBias_AxisInversion::Inverted);

        auto Rows = TArray<FCk_InputBias_AxisBias>();
        Rows.Add(Row);

        _Bias = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData(Rows));

        Assert_True(ck::IsValid(_Bias),
            "a bias declaring only an inversion must compose");

        auto Declared = utils_input_bias::TryGet_AxisBias(_Bias, EKeys::Gamepad_LeftY);
        Assert_True(Declared.Get_Inversion() == ECk_InputBias_AxisInversion::Inverted,
            "the declared inversion must survive into the live table");

        Add_Step(          "inject a positive deflection",           n"Step_InjectPositive");
        Add_Step_WaitUntil("the positive sample lands",              n"Check_SampledPositive");
        Add_Step(          "assert it comes back negative",          n"Step_AssertPositiveInverted");

        Add_Step(          "inject a negative deflection",           n"Step_InjectNegative");
        Add_Step_WaitUntil("the negative sample lands",              n"Check_SampledNegative");
        Add_Step(          "assert it comes back positive",          n"Step_AssertNegativeInverted");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectPositive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(0.5f);
    }

    UFUNCTION()
    private void Step_AssertPositiveInverted(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftY), -0.5f, 0.0001f,
            "an inverted axis must condition a positive deflection to its negative");
        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftY), 0.5f, 0.0001f,
            "inversion must not touch the recorded raw value");
    }

    UFUNCTION()
    private void Step_InjectNegative(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(-0.25f);
    }

    UFUNCTION()
    private void Step_AssertNegativeInverted(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftY), 0.25f, 0.0001f,
            "inversion is symmetric - a negative deflection must condition to its positive");
        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftY), -0.25f, 0.0001f,
            "the recorded raw value keeps the sign the device sent");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_SampledPositive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(
            utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftY), 0.5f, 0.0001f));
    }

    UFUNCTION()
    private void Check_SampledNegative(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(
            utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftY), -0.25f, 0.0001f));
    }

    //------------------------------------------------------------------------

    private void DoInjectAxis(float InAnalogValue)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            EKeys::Gamepad_LeftY,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(InAnalogValue);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }
}
