// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: LEFT AND RIGHT TOGETHER IS NEITHER
//============================================================================
//
// A keyboard can ask a question a gated stick cannot: both ends of one axis at
// once. Under the default Neutral policy the record answers "neither", which is
// the fighting-game tournament ruling and the only answer that stays inside
// what the hardware being emulated could physically produce.
//
// Three readings, and the middle one only means something because of the two
// around it:
//
//   hold Left          -> Negative   one end down is that end
//   also hold Right    -> Neutral    the pair cancels
//   release Left       -> Positive   the survivor takes the axis back
//
// The last line is what separates cancelling from breaking. An implementation
// that simply stopped reporting once two buttons were down would also pass
// "reads Neutral"; only the recovery proves the axis is still live. The row's
// held set is asserted alongside, so "Neutral" cannot pass as "the second press
// never arrived".
//
// The quad is built from tier-2 PHYSICAL buttons rather than from the authored
// player mappings: tier 2 exists precisely so a synthetic source with no
// binding profile still has a button space, and a tier-1 quad would make this
// test depend on a registered mapping context and a live key profile that have
// nothing to do with SOCD.
//
// The vertical pair is asserted throughout even though nothing ever presses it:
// cleaning that leaked across axes would be invisible otherwise.
//============================================================================

class UCk_AutoTest_Intent_SocdNeutralCancelsOpposingHeld : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;

    private FKey _UpKey;
    private FKey _DownKey;
    private FKey _LeftKey;
    private FKey _RightKey;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _UpKey    = EKeys::Gamepad_DPad_Up;
        _DownKey  = EKeys::Gamepad_DPad_Down;
        _LeftKey  = EKeys::Gamepad_DPad_Left;
        _RightKey = EKeys::Gamepad_DPad_Right;

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_UpKey);
        PhysicalButtons.Add(_DownKey);
        PhysicalButtons.Add(_LeftKey);
        PhysicalButtons.Add(_RightKey);

        _Map = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));

        auto Params = FCk_Fragment_IntentSampler_ParamsData(120);
        Params.Set_SocdQuad(FCk_Intent_SocdQuad(
            DoPhysicalButton(_UpKey),
            DoPhysicalButton(_DownKey),
            DoPhysicalButton(_LeftKey),
            DoPhysicalButton(_RightKey)));

        _Sampler = utils_intent_sampler::Add(_Owner, Params);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");

        Add_Step_WaitUntil("the map mints the quad and the sampler is recording", n"Check_Ready");
        Add_Step(          "hold left",                                           n"Step_HoldLeft");
        Add_Step_WaitUntil("the row reads the left end",                          n"Check_ReadsNegative");
        Add_Step(          "assert one end down is that end, then also hold right", n"Step_AssertLeftThenHoldRight");
        Add_Step_WaitUntil("the opposing pair cancels",                           n"Check_ReadsNeutral");
        Add_Step(          "assert both are held and it still reads neither, then release left", n"Step_AssertCancelledThenReleaseLeft");
        Add_Step_WaitUntil("the survivor takes the axis",                         n"Check_ReadsPositive");
        Add_Step(          "assert the survivor won and the vertical never moved", n"Step_AssertSurvivor");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_HoldLeft(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_LeftKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertLeftThenHoldRight(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Row = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Assert_True(Row.Get_CleanedHorizontal() == ECk_Intent_CleanedAxis::Negative,
            "one end of an axis held alone is simply that end - cleaning only has work to do when both are down");

        Assert_True(Row.Get_CleanedVertical() == ECk_Intent_CleanedAxis::Neutral,
            "nothing on the vertical pair was pressed, so its reading must not move with the horizontal one");

        DoInject(_RightKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertCancelledThenReleaseLeft(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Row = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Assert_True(DoContainsPhysical(Row.Get_Held(), _LeftKey),
            "the left button must still be recorded down, or the cancellation below is measuring nothing");

        Assert_True(DoContainsPhysical(Row.Get_Held(), _RightKey),
            "the right button must be recorded down, or Neutral would just mean the press never arrived");

        Assert_True(Row.Get_CleanedHorizontal() == ECk_Intent_CleanedAxis::Neutral,
            "both ends of one axis held under the Neutral policy is an input the hardware cannot give, so the record gives neither");

        DoInject(_LeftKey, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertSurvivor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Row = utils_intent_sampler::Get_LatestFrame(_Sampler);

        Assert_True(Row.Get_CleanedHorizontal() == ECk_Intent_CleanedAxis::Positive,
            "releasing one end hands the axis to the survivor - cancelling suppresses a reading, it does not end one");

        Assert_False(DoContainsPhysical(Row.Get_Held(), _LeftKey),
            "the released end must have left the held set, or the survivor won for the wrong reason");

        Assert_True(Row.Get_CleanedVertical() == ECk_Intent_CleanedAxis::Neutral,
            "the vertical pair was never touched and must read Neutral through the whole sequence");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _UpKey).Num()    >= 1 &&
                utils_input_button_map::Get_ButtonIdsForKey(_Map, _DownKey).Num()  >= 1 &&
                utils_input_button_map::Get_ButtonIdsForKey(_Map, _LeftKey).Num()  >= 1 &&
                utils_input_button_map::Get_ButtonIdsForKey(_Map, _RightKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_ReadsNegative(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_CleanedHorizontal() ==
                ECk_Intent_CleanedAxis::Negative);
    }

    UFUNCTION()
    private void Check_ReadsNeutral(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_CleanedHorizontal() ==
                ECk_Intent_CleanedAxis::Neutral);
    }

    UFUNCTION()
    private void Check_ReadsPositive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_CleanedHorizontal() ==
                ECk_Intent_CleanedAxis::Positive);
    }

    //------------------------------------------------------------------------

    private FCk_Input_ButtonId DoPhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
    }

    private void DoInject(FKey InKey, ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            InKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
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
