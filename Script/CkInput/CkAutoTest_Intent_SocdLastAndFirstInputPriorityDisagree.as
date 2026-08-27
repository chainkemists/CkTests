// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE TWO PRIORITY POLICIES DISAGREE
//============================================================================
//
// LastInputPriority and FirstInputPriority are only meaningful relative to each
// other: each one on its own is just "some end of the axis won", and an
// implementation that ignored the policy entirely and always picked the same
// end would pass either test in isolation. So both are driven by ONE input
// sequence in ONE test and the assertion is the DISAGREEMENT.
//
//   hold Left, then also hold Right
//     LastInputPriority  -> Positive   the right press is the later one
//     FirstInputPriority -> Negative   the left press is the earlier one
//
// Two samplers, because a sampler's policy is fixed at composition and one
// source has exactly one frame record. Two sources side by side in the shared
// world, fed identical injections in the same step, is the only shape in which
// "same input, two answers" is a fact rather than two separate runs compared by
// hand.
//
// The FirstInputPriority answer is the one that could pass vacuously — it was
// already Negative before the right press arrived. Its guard is the held set:
// the step asserts BOTH buttons are recorded down on that sampler's row, so
// "still Negative" cannot pass as "the second press never got there".
//
// Tier-2 PHYSICAL buttons for the quad, for the same reason as the Neutral
// policy test: no binding profile is involved and none should be.
//============================================================================

class UCk_AutoTest_Intent_SocdLastAndFirstInputPriorityDisagree : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle                _OwnerLast;
    private FCk_Handle_InputSource    _SourceLast;
    private FCk_Handle_InputButtonMap _MapLast;
    private FCk_Handle_IntentSampler  _SamplerLast;

    private FCk_Handle                _OwnerFirst;
    private FCk_Handle_InputSource    _SourceFirst;
    private FCk_Handle_InputButtonMap _MapFirst;
    private FCk_Handle_IntentSampler  _SamplerFirst;

    private FKey _UpKey;
    private FKey _DownKey;
    private FKey _LeftKey;
    private FKey _RightKey;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _UpKey    = EKeys::Gamepad_DPad_Up;
        _DownKey  = EKeys::Gamepad_DPad_Down;
        _LeftKey  = EKeys::Gamepad_DPad_Left;
        _RightKey = EKeys::Gamepad_DPad_Right;

        _OwnerLast   = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _SourceLast  = utils_input_source::Add(_OwnerLast, FCk_Fragment_InputSource_ParamsData(0));
        _MapLast     = utils_input_button_map::Add(_OwnerLast, DoMakeMapParams());
        _SamplerLast = utils_intent_sampler::Add(_OwnerLast,
            DoMakeSamplerParams(ECk_Intent_SocdPolicy::LastInputPriority));

        _OwnerFirst   = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _SourceFirst  = utils_input_source::Add(_OwnerFirst, FCk_Fragment_InputSource_ParamsData(0));
        _MapFirst     = utils_input_button_map::Add(_OwnerFirst, DoMakeMapParams());
        _SamplerFirst = utils_intent_sampler::Add(_OwnerFirst,
            DoMakeSamplerParams(ECk_Intent_SocdPolicy::FirstInputPriority));

        Assert_True(ck::IsValid(_SamplerLast),  "the last-input sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_SamplerFirst), "the first-input sampler must compose for this test to mean anything");

        Add_Step_WaitUntil("both maps mint the quad and both samplers record", n"Check_Ready");
        Add_Step(          "hold left on both sources",                        n"Step_HoldLeft");
        Add_Step_WaitUntil("both read the left end",                           n"Check_BothReadNegative");
        Add_Step(          "assert they agree while one end is down, then also hold right", n"Step_AssertAgreeThenHoldRight");
        Add_Step_WaitUntil("the last-input sampler flips and the first-input one has both", n"Check_Disagreement");
        Add_Step(          "assert the same input produced two readings",      n"Step_AssertDisagreement");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_HoldLeft(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_SourceLast,  _LeftKey);
        DoInject(_SourceFirst, _LeftKey);
    }

    UFUNCTION()
    private void Step_AssertAgreeThenHoldRight(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_sampler::Get_LatestFrame(_SamplerLast).Get_CleanedHorizontal() ==
                    ECk_Intent_CleanedAxis::Negative,
            "with one end down there is no pair to resolve, so the policy cannot yet be what separates them");

        Assert_True(utils_intent_sampler::Get_LatestFrame(_SamplerFirst).Get_CleanedHorizontal() ==
                    ECk_Intent_CleanedAxis::Negative,
            "both policies must start from the same reading, or the disagreement below proves only that they differ somewhere");

        DoInject(_SourceLast,  _RightKey);
        DoInject(_SourceFirst, _RightKey);
    }

    UFUNCTION()
    private void Step_AssertDisagreement(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto RowLast  = utils_intent_sampler::Get_LatestFrame(_SamplerLast);
        auto RowFirst = utils_intent_sampler::Get_LatestFrame(_SamplerFirst);

        Assert_True(DoHoldsBothEnds(RowLast),
            "the last-input sampler must have both ends down, or its reading is not a resolved pair");

        Assert_True(DoHoldsBothEnds(RowFirst),
            "the first-input sampler must have both ends down, or its unchanged reading proves nothing");

        Assert_True(RowLast.Get_CleanedHorizontal() == ECk_Intent_CleanedAxis::Positive,
            "LastInputPriority hands the axis to the press that came second");

        Assert_True(RowFirst.Get_CleanedHorizontal() == ECk_Intent_CleanedAxis::Negative,
            "FirstInputPriority keeps the axis on the press that came first, from the identical sequence");

        Assert_True(RowLast.Get_CleanedVertical() == ECk_Intent_CleanedAxis::Neutral &&
                    RowFirst.Get_CleanedVertical() == ECk_Intent_CleanedAxis::Neutral,
            "neither policy may move an axis whose buttons were never pressed");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoMapIsReady(_MapLast) && DoMapIsReady(_MapFirst) &&
                utils_intent_sampler::Get_FrameCount(_SamplerLast)  >= 1 &&
                utils_intent_sampler::Get_FrameCount(_SamplerFirst) >= 1);
    }

    UFUNCTION()
    private void Check_BothReadNegative(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_SamplerLast).Get_CleanedHorizontal() ==
                    ECk_Intent_CleanedAxis::Negative &&
                utils_intent_sampler::Get_LatestFrame(_SamplerFirst).Get_CleanedHorizontal() ==
                    ECk_Intent_CleanedAxis::Negative);
    }

    UFUNCTION()
    private void Check_Disagreement(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto RowLast  = utils_intent_sampler::Get_LatestFrame(_SamplerLast);
        auto RowFirst = utils_intent_sampler::Get_LatestFrame(_SamplerFirst);

        Res.Set(RowLast.Get_CleanedHorizontal() == ECk_Intent_CleanedAxis::Positive &&
                DoHoldsBothEnds(RowFirst));
    }

    //------------------------------------------------------------------------

    private FCk_Fragment_InputButtonMap_ParamsData DoMakeMapParams()
    {
        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_UpKey);
        PhysicalButtons.Add(_DownKey);
        PhysicalButtons.Add(_LeftKey);
        PhysicalButtons.Add(_RightKey);

        return FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons);
    }

    private FCk_Fragment_IntentSampler_ParamsData DoMakeSamplerParams(ECk_Intent_SocdPolicy InPolicy)
    {
        auto Params = FCk_Fragment_IntentSampler_ParamsData(120);

        Params.Set_SocdQuad(FCk_Intent_SocdQuad(
            DoPhysicalButton(_UpKey),
            DoPhysicalButton(_DownKey),
            DoPhysicalButton(_LeftKey),
            DoPhysicalButton(_RightKey)));

        Params.Set_SocdPolicy(InPolicy);

        return Params;
    }

    private FCk_Input_ButtonId DoPhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
    }

    private bool DoMapIsReady(FCk_Handle_InputButtonMap InMap)
    {
        return utils_input_button_map::Get_ButtonIdsForKey(InMap, _UpKey).Num()    >= 1 &&
               utils_input_button_map::Get_ButtonIdsForKey(InMap, _DownKey).Num()  >= 1 &&
               utils_input_button_map::Get_ButtonIdsForKey(InMap, _LeftKey).Num()  >= 1 &&
               utils_input_button_map::Get_ButtonIdsForKey(InMap, _RightKey).Num() >= 1;
    }

    private void DoInject(FCk_Handle_InputSource InSource, FKey InKey)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            InKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(InSource,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    private bool DoHoldsBothEnds(FCk_Intent_FrameRecord InRow)
    {
        return DoContainsPhysical(InRow.Get_Held(), _LeftKey) &&
               DoContainsPhysical(InRow.Get_Held(), _RightKey);
    }

    private bool DoContainsPhysical(const TArray<FCk_Input_ButtonId>& InButtons, FKey InKey)
    {
        auto KeyName = InKey.GetKeyName();

        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == KeyName)
            { return true; }
        }

        return false;
    }
}
