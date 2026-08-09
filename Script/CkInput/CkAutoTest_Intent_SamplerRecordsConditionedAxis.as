// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE ROW RECORDS THE CONDITIONED AXIS
//============================================================================
//
// The record must carry the number gameplay would act on, not the number the
// device sent. Those differ by exactly the bias, and the difference is the
// whole point of having a conditioning stage: a recorded 0.5 that ignored a
// 2x sensitivity would describe an input the player never gave.
//
// The expectation is computed the way the InputBias tests compute theirs —
// from the declared bias, by hand — so a change to the conditioning math has
// to be made in two places before this test agrees with it.
//
//   raw 0.5, deadzone 0.2, exponent 1, sensitivity 2
//     -> magnitude 0.5 clears the deadzone
//     -> rescaled (0.5 - 0.2) / (1 - 0.2) = 0.375
//     -> curved   0.375 ^ 1                = 0.375
//     -> scaled   0.375 * 2                = 0.75
//
// The Y axis is left unbiased and injected at a different value, which pins
// the second half of the pair separately: a sampler that read one axis into
// both slots, or swapped them, passes neither assertion.
//============================================================================

class UCk_AutoTest_Intent_SamplerRecordsConditionedAxis : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle               _Owner;
    private FCk_Handle_InputSource   _Source;
    private FCk_Handle_InputBias     _Bias;
    private FCk_Handle_IntentSampler _Sampler;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        Assert_True(ck::IsValid(_Bias),    "the bias must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        auto Row = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        Row.Set_Deadzone(0.2f);
        Row.Set_Sensitivity(2.0f);

        utils_input_bias::Request_SetAxisBias(_Bias, FCk_Request_InputBias_SetAxisBias(Row));

        Add_Step_WaitUntil("the bias lands on the table",           n"Check_BiasLanded");
        Add_Step(          "inject both axes",                      n"Step_InjectAxes");
        Add_Step_WaitUntil("the conditioned values reach a row",    n"Check_AxesRecorded");
        Add_Step(          "assert the row carries the CONDITIONED value", n"Step_AssertConditioned");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectAxes(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(EKeys::Gamepad_LeftX, 0.5f);
        DoInjectAxis(EKeys::Gamepad_LeftY, -0.4f);
    }

    UFUNCTION()
    private void Step_AssertConditioned(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Row = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Assert_True(Row.Get_FrameIndex() >= 0,
            "the sampler must have written at least one row by now");

        Assert_Equals_Float(Row.Get_ConditionedAxisX(), 0.75f, 0.001f,
            "the X slot must carry the biased value, not the 0.5 the device reported");

        Assert_Equals_Float(Row.Get_ConditionedAxisY(), -0.4f, 0.001f,
            "an axis with no declared bias is an identity passthrough, sign included");

        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.5f, 0.0001f,
            "recording must not disturb the raw value the producer reported");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_BiasLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::IsNearlyEqual(
            utils_input_bias::TryGet_AxisBias(_Bias, EKeys::Gamepad_LeftX).Get_Sensitivity(), 2.0f, 0.0001f));
    }

    UFUNCTION()
    private void Check_AxesRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Row = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Res.Set(Row.Get_FrameIndex() >= 0 &&
                Math::IsNearlyEqual(Row.Get_ConditionedAxisX(), 0.75f, 0.001f) &&
                Math::IsNearlyEqual(Row.Get_ConditionedAxisY(), -0.4f, 0.001f));
    }

    //------------------------------------------------------------------------

    private void DoInjectAxis(FKey InAxisKey, float InAnalogValue)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            InAxisKey,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(InAnalogValue);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }
}
