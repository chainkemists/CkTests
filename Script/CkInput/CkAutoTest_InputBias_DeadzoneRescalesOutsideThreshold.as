// Language=angelscript

//============================================================================
// CK INPUT BIAS - AUTOMATION TEST: THE DEADZONE BOUNDARY, FROM BOTH SIDES
//============================================================================
//
// A deadzone is only correct at its edge. Three samples straddle the
// threshold - below it, exactly on it, and one hundredth above it - because
// the two implementations that get this wrong both look right in the middle
// of the range: a naive "zero it out" leaves a step at the threshold (the
// first live value jumps to the threshold value instead of leaving zero
// smoothly), and an off-by-one comparison makes the threshold itself live.
//
// The rescale is what removes the step: the surviving band is stretched so
// the threshold maps to 0 and full deflection still maps to 1.
//
// The negative sample is here because every stage after inversion works on
// the magnitude - if the rescale were applied to the signed value instead,
// this is the assertion that catches it.
//============================================================================

class UCk_AutoTest_InputBias_DeadzoneRescalesOutsideThreshold : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle             _Owner;
    private FCk_Handle_InputSource _Source;
    private FCk_Handle_InputBias   _Bias;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        auto Row = FCk_InputBias_AxisBias(EKeys::Gamepad_LeftX);
        Row.Set_Deadzone(0.25f);

        auto Rows = TArray<FCk_InputBias_AxisBias>();
        Rows.Add(Row);

        _Bias = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData(Rows));

        Assert_True(ck::IsValid(_Bias),
            "a bias declaring one in-range row must compose");

        auto Declared = utils_input_bias::TryGet_AxisBias(_Bias, EKeys::Gamepad_LeftX);
        Assert_True(Declared.Get_AxisKey() == EKeys::Gamepad_LeftX,
            "the declared row must be readable back for the axis it names");
        Assert_Equals_Float(Declared.Get_Deadzone(), 0.25f, 0.0001f,
            "the composed deadzone must survive into the live table");

        Add_Step(          "inject just inside the deadzone",         n"Step_InjectBelow");
        Add_Step_WaitUntil("the below-threshold sample lands",        n"Check_SampledBelow");
        Add_Step(          "assert it reads as dead",                 n"Step_AssertBelowIsZero");

        Add_Step(          "inject exactly at the threshold",         n"Step_InjectAt");
        Add_Step_WaitUntil("the at-threshold sample lands",           n"Check_SampledAt");
        Add_Step(          "assert the threshold itself is dead",     n"Step_AssertAtIsZero");

        Add_Step(          "inject just outside the deadzone",        n"Step_InjectAbove");
        Add_Step_WaitUntil("the above-threshold sample lands",        n"Check_SampledAbove");
        Add_Step(          "assert it leaves zero, rescaled",         n"Step_AssertAboveIsRescaled");

        Add_Step(          "inject the mirrored negative sample",     n"Step_InjectNegative");
        Add_Step_WaitUntil("the negative sample lands",               n"Check_SampledNegative");
        Add_Step(          "assert the rescale kept the sign",        n"Step_AssertNegativeMirrors");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_InjectBelow(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(0.24f);
    }

    UFUNCTION()
    private void Step_AssertBelowIsZero(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.0f, 0.0001f,
            "a magnitude inside the deadzone must condition to exactly zero");
        Assert_Equals_Float(utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.24f, 0.0001f,
            "a zeroed axis still records the raw value it was zeroed from");
    }

    UFUNCTION()
    private void Step_InjectAt(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(0.25f);
    }

    UFUNCTION()
    private void Step_AssertAtIsZero(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), 0.0f, 0.0001f,
            "the threshold itself belongs to the dead band, not to the live one");
    }

    UFUNCTION()
    private void Step_InjectAbove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(0.26f);
    }

    UFUNCTION()
    private void Step_AssertAboveIsRescaled(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        float Expected = (0.26f - 0.25f) / (1.0f - 0.25f);

        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), Expected, 0.0001f,
            "the band above the deadzone must be rescaled so the threshold maps to zero - an unrescaled implementation reads 0.26 here");
    }

    UFUNCTION()
    private void Step_InjectNegative(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectAxis(-0.26f);
    }

    UFUNCTION()
    private void Step_AssertNegativeMirrors(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        float Expected = -((0.26f - 0.25f) / (1.0f - 0.25f));

        Assert_Equals_Float(utils_input_bias::Get_ConditionedAxisValue(_Bias, EKeys::Gamepad_LeftX), Expected, 0.0001f,
            "the deadzone acts on the magnitude and restores the sign, so a negative deflection mirrors its positive twin");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_SampledBelow(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoGet_RawIs(0.24f));
    }

    UFUNCTION()
    private void Check_SampledAt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoGet_RawIs(0.25f));
    }

    UFUNCTION()
    private void Check_SampledAbove(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoGet_RawIs(0.26f));
    }

    UFUNCTION()
    private void Check_SampledNegative(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoGet_RawIs(-0.26f));
    }

    //------------------------------------------------------------------------

    private void DoInjectAxis(float InAnalogValue)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            EKeys::Gamepad_LeftX,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(InAnalogValue);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    // Each sample overwrites the previous one on the same axis, so "the raw half now reads X" names the exact
    // write the following assertions read - and no two samples in this test share a value.
    private bool DoGet_RawIs(float InExpectedRaw)
    {
        return Math::IsNearlyEqual(
            utils_input_bias::Get_LastRawAxisValue(_Bias, EKeys::Gamepad_LeftX), InExpectedRaw, 0.0001f);
    }
}
