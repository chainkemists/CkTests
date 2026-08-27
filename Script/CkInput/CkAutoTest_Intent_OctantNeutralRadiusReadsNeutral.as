// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A SHORT VECTOR HAS NO DIRECTION
//============================================================================
//
// Angle is defined for any non-zero vector, which is the problem: a stick a
// hair off centre has a perfectly real angle and a completely arbitrary one.
// The neutral radius is the sampler's answer - below it the row reads Neutral
// rather than naming whichever octant the noise fell in.
//
// Three readings at TWO angles, in this order, because the third one is what
// makes the second mean something:
//
//   magnitude 0.9 at 30 deg -> NE       above the radius, a real direction
//   magnitude 0.1 at 30 deg -> Neutral  same angle, too short to name
//   magnitude 0.9 at 20 deg -> E        and E only because the neutral pass
//                                       CLEARED the remembered NE
//
// That last line is the load-bearing one. 20 degrees sits 25 degrees from NE's
// centre, inside NE's hold band of 22.5 + 5 - so a sampler that kept its
// hysteresis memory through the neutral pass would still be reporting NE here.
// Reading E is only possible if going neutral reset it, which is the documented
// contract: hysteresis damps a flicker inside ONE gesture, and a stick that came
// back to centre has ended the gesture.
//
// An InputBias is composed but left EMPTY - an identity passthrough - so the
// magnitudes under test are the magnitudes asked for, and the axis reaches the
// row by the same path the conditioned-axis test already pins.
//============================================================================

class UCk_AutoTest_Intent_OctantNeutralRadiusReadsNeutral : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle               _Owner;
    private FCk_Handle_InputSource   _Source;
    private FCk_Handle_InputBias     _Bias;
    private FCk_Handle_IntentSampler _Sampler;

    private float32 _NeutralRadius = 0.25f;

    private float32 _ExpectedX = 0.0f;
    private float32 _ExpectedY = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        auto Params = FCk_Fragment_IntentSampler_ParamsData(120);
        Params.Set_OctantNeutralRadius(_NeutralRadius);

        _Sampler = utils_intent_sampler::Add(_Owner, Params);

        Assert_True(ck::IsValid(_Bias),    "the identity bias must compose, or the axis path under test is a different one");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        Add_Step_WaitUntil("the sampler starts recording",                  n"Check_Recording");

        Add_Step(          "drive a long vector at 30 degrees",             n"Step_DriveLongAtNE");
        Add_Step_WaitUntil("the sample reaches a row",                      n"Check_SampleLanded");
        Add_Step(          "assert it names the octant",                    n"Step_AssertNE");

        Add_Step(          "shorten it below the radius, same angle",       n"Step_DriveShortAtNE");
        Add_Step_WaitUntil("the sample reaches a row",                      n"Check_SampleLanded");
        Add_Step(          "assert the angle alone names nothing",          n"Step_AssertNeutral");

        Add_Step(          "drive a long vector at 20 degrees",             n"Step_DriveLongAtE");
        Add_Step_WaitUntil("the sample reaches a row",                      n"Check_SampleLanded");
        Add_Step(          "assert the neutral pass cleared the memory",    n"Step_AssertE");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DriveLongAtNE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDrive(30.0f, 0.9f);
    }

    UFUNCTION()
    private void Step_DriveShortAtNE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDrive(30.0f, 0.1f);
    }

    UFUNCTION()
    private void Step_DriveLongAtE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDrive(20.0f, 0.9f);
    }

    UFUNCTION()
    private void Step_AssertNE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::NE,
            "a vector clear of the radius reads as the octant its angle falls in");
    }

    UFUNCTION()
    private void Step_AssertNeutral(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::Neutral,
            "the same angle inside the radius reads Neutral - magnitude, not angle, decides whether there is a direction at all");
    }

    UFUNCTION()
    private void Step_AssertE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::E,
            "20 degrees is inside NE's hold band, so reading E proves the neutral pass reset the hysteresis memory");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SampleLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Row = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Res.Set(Row.Get_FrameIndex() >= 0 &&
                Math::IsNearlyEqual(Row.Get_ConditionedAxisX(), _ExpectedX, 0.0005f) &&
                Math::IsNearlyEqual(Row.Get_ConditionedAxisY(), _ExpectedY, 0.0005f));
    }

    //------------------------------------------------------------------------

    private void DoDrive(float InAngleDegrees, float InMagnitude)
    {
        const float Radians = InAngleDegrees * float(Math::PI) / 180.0f;

        _ExpectedX = float32(Math::Cos(Radians) * InMagnitude);
        _ExpectedY = float32(Math::Sin(Radians) * InMagnitude);

        DoInjectAxis(EKeys::Gamepad_LeftX, _ExpectedX);
        DoInjectAxis(EKeys::Gamepad_LeftY, _ExpectedY);
    }

    private void DoAssertOctant(ECk_Intent_Octant InExpected, const FString& InWhy)
    {
        auto Row = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Assert_True(Row.Get_FrameIndex() >= 0,
            "the sampler must have written a row before its octant can mean anything");

        Assert_True(Row.Get_Octant() == InExpected, InWhy);
    }

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
