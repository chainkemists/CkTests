// Language=angelscript

//============================================================================
// CK INPUT BIAS - AUTOMATION TEST: DEADZONE, THEN EXPONENT, THEN SENSITIVITY
//============================================================================
//
// Four stages that each look like a scalar multiply are not commutative, and
// the wrong order produces a curve that still "feels like a curve" - which is
// why this has to be an assertion and not a comment.
//
// The numbers are chosen so every wrong order lands somewhere obviously else.
// With deadzone 0.2, exponent 2, sensitivity 3 and a raw deflection of 0.6:
//
//   declared order   (0.6-0.2)/0.8 = 0.5  ->  0.5^2 = 0.25  ->  x3  = 0.75
//   sensitivity first        0.6 x3 = 1.8  ->  rescaled/^2        = 4.0
//   exponent before deadzone 0.6^2 = 0.36  ->  rescaled x3        = 0.6
//
// The full-deflection sample pins the other half of the rescale contract: 1
// still maps to 1 through the deadzone, so sensitivity is exactly what a
// fully deflected stick produces - the property a designer actually tunes
// against.
//============================================================================

class UCk_AutoTest_InputBias_StagesComposeInDeclaredOrder : UCk_AutoTest_Base
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

        auto Row = FCk_InputBias_AxisBias(EKeys::Gamepad_RightX);
        Row.Set_Deadzone(0.2f);
        Row.Set_Exponent(2.0f);
        Row.Set_Sensitivity(3.0f);

        auto Rows = TArray<FCk_InputBias_AxisBias>();
        Rows.Add(Row);

        _Bias = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData(Rows));

        Assert_True(ck::IsValid(_Bias),
            "a bias declaring all four stages must compose");

        Add_Step(          "inject a partial deflection",              n"Step_InjectPartial");
        Add_Step_WaitUntil("the partial sample lands",                 n"Check_SampledPartial");
        Add_Step(          "assert the stages composed in order",      n"Step_AssertPartial");

        Add_Step(          "inject full deflection",                   n"Step_InjectFull");
        Add_Step_WaitUntil("the full-deflection sample lands",         n"Check_SampledFull");
        Add_Step(          "assert full deflection reads sensitivity", n"Step_AssertFull");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectPartial(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(0.6f);
    }

    UFUNCTION()
    private void Step_AssertPartial(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_RightX), 0.75f, 0.001f,
            "deadzone, then exponent, then sensitivity - applying sensitivity first reads 4.0, exponent before the deadzone reads 0.6");
        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_RightX), 0.6f, 0.0001f,
            "four stages of conditioning must still leave the recorded raw value alone");
    }

    UFUNCTION()
    private void Step_InjectFull(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(1.0f);
    }

    UFUNCTION()
    private void Step_AssertFull(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_RightX), 3.0f, 0.001f,
            "the rescale anchors full deflection at 1, so an exponent of any power leaves sensitivity as the full-deflection reading");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_SampledPartial(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(
            utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_RightX), 0.6f, 0.0001f));
    }

    UFUNCTION()
    private void Check_SampledFull(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(
            utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_RightX), 1.0f, 0.0001f));
    }

    //------------------------------------------------------------------------

    private void DoInjectAxis(float InAnalogValue)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            EKeys::Gamepad_RightX,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(InAnalogValue);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }
}
