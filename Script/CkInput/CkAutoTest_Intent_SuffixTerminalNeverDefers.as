// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A SHARED TERMINAL COSTS NOTHING
//============================================================================
//
// The property the deferral model exists to protect. `236+P` and a bare `P`
// share a terminal, and a naive matcher would hold the bare punch back for a
// few frames "in case a motion was coming" — which is exactly the input lag
// the whole design refuses. The prefix either already happened or it did not,
// so there is nothing in the FUTURE to wait for.
//
// Both halves are asserted against ONE set in ONE session, because either
// alone would also pass against a broken implementation:
//
//   no motion  -> the bare punch completes on its own press frame, even
//                 though a higher-priority move shares its button
//   with 236   -> the motion wins the frame by priority, and the bare punch
//                 does NOT also fire on it
//
// The second leg is what pins the arbiter: one press resolves to exactly one
// intent, the most dominant one whose prefix is actually behind it. The bare
// punch's completion frame is checked to still be the FIRST leg's, which is
// stronger than checking it is merely "not now" — it proves the latch was
// left alone rather than re-stamped.
//============================================================================

class UCk_AutoTest_Intent_SuffixTerminalNeverDefers : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputBias      _Bias;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _PunchKey;
    private FName _PunchButtonName;

    private ECk_Intent_Octant _AwaitedOctant = ECk_Intent_Octant::Neutral;

    private int32 _BareFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::B;
        _PunchButtonName = _PunchKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        // This test holds a completion latch across several waits and asserts it is UNCHANGED, so it must
        // not be coupled to the decay window it is not about. Ten seconds outlasts any step cadence.
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(600);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the suffix-sharing set and activate it",         n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "punch with no motion behind it",                      n"Step_PressPunch");
        Add_Step_WaitUntil("the bare punch completes",                            n"Check_BareCompleted");
        Add_Step(          "assert it landed on its own press frame, then let go", n"Step_AssertBareThenRelease");

        Add_Step_WaitUntil("the release reaches a row",                           n"Check_PunchReleased");
        Add_Step(          "drive the stick to S",                                n"Step_DriveSouth");
        Add_Step_WaitUntil("the record reads S",                                  n"Check_AwaitedOctant");
        Add_Step(          "drive the stick to SE",                               n"Step_DriveSouthEast");
        Add_Step_WaitUntil("the record reads SE",                                 n"Check_AwaitedOctant");
        Add_Step(          "drive E and punch on the same frame",                 n"Step_DriveEastAndPunch");
        Add_Step_WaitUntil("the motion completes",                                n"Check_SpecialCompleted");
        Add_Step(          "assert the motion won the frame outright",            n"Step_AssertArbitration");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("236+P", n"AS_Suffix_Special", 100));
        Definitions.Add(DoParse("P",     n"AS_Suffix_Bare",     50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        // The property under test, read straight off the artifact: sharing a terminal earns no deferral, so
        // nothing about the bare punch's timing depends on the matcher choosing to be prompt.
        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_PhysicalButton(_PunchKey));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "neither move declares a hold, so the shared terminal waits on no hold threshold");
        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), 0,
            "the motion's chord needs a DIRECTION and no second button, so nothing is ever in flight");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressPunch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInjectPunch(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertBareThenRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PressFrame = DoFind_LatestPunchPressFrame();

        Assert_True(PressFrame >= 0,
            "a retained row must carry the punch's press edge for the comparison to mean anything");

        _BareFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Suffix_Bare");

        Assert_Equals_Int(_BareFrame, PressFrame,
            "a button several moves share still completes the bare move on its own press frame");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Suffix_Special") ==
                    ECk_Intent_Phase::Idle,
            "the motion has no prefix behind it, so a lone punch must not complete it");

        DoInjectPunch(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_DriveSouth(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AwaitedOctant = ECk_Intent_Octant::S;
        DoDriveAxes(0.0f, -0.9f);
    }

    UFUNCTION()
    private void Step_DriveSouthEast(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AwaitedOctant = ECk_Intent_Octant::SE;
        DoDriveAxes(0.7f, -0.7f);
    }

    UFUNCTION()
    private void Step_DriveEastAndPunch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoDriveAxes(0.9f, 0.0f);
        DoInjectPunch(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertArbitration(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PressFrame = DoFind_LatestPunchPressFrame();

        Assert_True(PressFrame >= 0,
            "a retained row must carry the second punch's press edge");

        auto SpecialFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Suffix_Special");

        Assert_Equals_Int(SpecialFrame, PressFrame,
            "the motion completes on its terminal's press frame, the same as the bare move did");

        auto BareFrameNow = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Suffix_Bare");

        Assert_Equals_Int(BareFrameNow, _BareFrame,
            "one press resolves to ONE intent: the dominant move won the frame, so the bare latch still names its earlier frame");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _PunchKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_ActiveIntentCount(_Matcher) == 2 &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey));
    }

    UFUNCTION()
    private void Check_BareCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Suffix_Bare") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_PunchReleased(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!DoContainsPunch(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held()));
    }

    UFUNCTION()
    private void Check_AwaitedOctant(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Octant() == _AwaitedOctant);
    }

    UFUNCTION()
    private void Check_SpecialCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Suffix_Special") ==
                ECk_Intent_Phase::Completed);
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        return Result.Get_Definition();
    }

    private FCk_Input_ButtonId DoMake_PhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
    }

    private void DoDriveAxes(float InX, float InY)
    {
        DoInjectAxis(EKeys::Gamepad_LeftX, InX);
        DoInjectAxis(EKeys::Gamepad_LeftY, InY);
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

    private void DoInjectPunch(ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    private bool DoContainsPunch(const TArray<FCk_Input_ButtonId>& InButtons)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == _PunchButtonName)
            { return true; }
        }

        return false;
    }

    // Offset 0 is the newest row, so the first press found walking forward from it is the most recent one — which
    // is the press the assertion around this call is about.
    private int32 DoFind_LatestPunchPressFrame()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsPunch(Row.Get_Pressed()))
            { return Row.Get_FrameIndex(); }
        }

        return -1;
    }
}
