// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE OCTANT STICKS AT A BOUNDARY, BOTH WAYS
//============================================================================
//
// A direction read straight off an angle flickers when the stick rests on a
// boundary, and a flicker is indistinguishable from a deliberate eighth-turn
// to everything above the record. The sampler damps it by making the two
// transitions cost different amounts: STAYING in the octant it last reported
// is free, ENTERING a new one costs the configured margin past the boundary.
//
// Both halves have to be pinned or the test proves nothing. A rule that simply
// refused to ever change octant passes "hysteresis held"; a rule with no
// hysteresis at all passes "it moved". So the walk crosses the E/NE boundary
// at 22.5 degrees FOUR times, and each crossing is asserted against what the
// asymmetry predicts:
//
//   20 deg (from centre) -> E   nothing to hold, the candidate is taken
//   26 deg               -> E   short of 22.5 + 5, the hold band still covers it
//   30 deg               -> NE  past 22.5 + 5, the boundary is cleared
//   21 deg               -> NE  back inside E's TERRITORY, inside NE's hold band
//    5 deg               -> E   40 degrees from NE's centre, well clear
//
// The third and fourth lines are the ones that matter: the same angle reads as
// two different octants depending on where it came from, which is exactly what
// hysteresis means and what no memoryless mapping can reproduce.
//
// An InputBias is composed but left EMPTY, which is an identity passthrough:
// the recorded values are the injected ones, so the angle under test is the
// angle that was asked for, and the axis reaches the row by the same path the
// conditioned-axis test already pins. Each wait is on the SAMPLE reaching a
// row, not on the octant: two of the five expectations are "unchanged", and a
// wait on an unchanged value would return before the new sample ever arrived.
//============================================================================

class UCk_AutoTest_Intent_OctantBoundaryHysteresisHoldsBothDirections : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle               _Owner;
    private FCk_Handle_InputSource   _Source;
    private FCk_Handle_InputBias     _Bias;
    private FCk_Handle_IntentSampler _Sampler;

    private float32 _MarginDegrees = 5.0f;

    private float32 _ExpectedX = 0.0f;
    private float32 _ExpectedY = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        auto Params = FCk_Fragment_IntentSampler_ParamsData(120);
        Params.Set_OctantHysteresisMarginDegrees(_MarginDegrees);

        _Sampler = utils_intent_sampler::Add(_Owner, Params);

        Assert_True(ck::IsValid(_Bias),    "the identity bias must compose, or the axis path under test is a different one");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        Add_Step_WaitUntil("the sampler starts recording",                    n"Check_Recording");

        Add_Step(          "drive to 20 degrees, just inside E",              n"Step_DriveJustInsideE");
        Add_Step_WaitUntil("the sample reaches a row",                        n"Check_SampleLanded");
        Add_Step(          "assert the reading is E",                         n"Step_AssertE");

        Add_Step(          "drive to 26 degrees, short of the margin",        n"Step_DriveShortOfMargin");
        Add_Step_WaitUntil("the sample reaches a row",                        n"Check_SampleLanded");
        Add_Step(          "assert hysteresis held it at E",                  n"Step_AssertStillE");

        Add_Step(          "drive to 30 degrees, past the margin",            n"Step_DrivePastMargin");
        Add_Step_WaitUntil("the sample reaches a row",                        n"Check_SampleLanded");
        Add_Step(          "assert the boundary was cleared into NE",         n"Step_AssertNE");

        Add_Step(          "drive back to 21 degrees, inside E's territory",  n"Step_DriveBackInsideE");
        Add_Step_WaitUntil("the sample reaches a row",                        n"Check_SampleLanded");
        Add_Step(          "assert hysteresis held it at NE",                 n"Step_AssertStillNE");

        Add_Step(          "drive to 5 degrees, well into E",                 n"Step_DriveWellIntoE");
        Add_Step_WaitUntil("the sample reaches a row",                        n"Check_SampleLanded");
        Add_Step(          "assert it returned to E",                         n"Step_AssertBackToE");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps - driving
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DriveJustInsideE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDriveToAngle(20.0f);
    }

    UFUNCTION()
    private void Step_DriveShortOfMargin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDriveToAngle(26.0f);
    }

    UFUNCTION()
    private void Step_DrivePastMargin(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDriveToAngle(30.0f);
    }

    UFUNCTION()
    private void Step_DriveBackInsideE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDriveToAngle(21.0f);
    }

    UFUNCTION()
    private void Step_DriveWellIntoE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDriveToAngle(5.0f);
    }

    //------------------------------------------------------------------------
    // Steps - asserting
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::E,
            "an angle inside E, arrived at from centre, reads as E");
    }

    UFUNCTION()
    private void Step_AssertStillE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::E,
            "past the boundary but short of the margin the previous octant still holds");
    }

    UFUNCTION()
    private void Step_AssertNE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::NE,
            "clearing the boundary by more than the margin is what moves the reading");
    }

    UFUNCTION()
    private void Step_AssertStillNE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::NE,
            "the same angle reads NE coming back that read E going out - the asymmetry is the mechanism");
    }

    UFUNCTION()
    private void Step_AssertBackToE(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssertOctant(ECk_Intent_Octant::E,
            "an angle clear of NE's hold band returns the reading to E, so the damping is not a latch");
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

    private void DoDriveToAngle(float InAngleDegrees)
    {
        const float Radians = InAngleDegrees * float(Math::PI) / 180.0f;

        _ExpectedX = float32(Math::Cos(Radians));
        _ExpectedY = float32(Math::Sin(Radians));

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
