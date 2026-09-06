// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A TAP AND A HOLD ON ONE BUTTON
//============================================================================
//
// The one ambiguity that genuinely reaches forward. A bare punch and a
// charged punch on the same button cannot be told apart at the moment of the
// press: the difference is entirely in what happens NEXT. So the press is
// held pending, and the three boundaries of that wait are what this pins.
//
// The three legs are the headless realization of "threshold-1 / at / +1".
// Frame-accurate release is not something a test can inject - which logic
// frame an injected event lands on is a property of the sampler's cadence
// against the renderer's - so each boundary is asserted as exact FRAME
// ARITHMETIC against the press row instead, which is strictly stronger than
// a wall-clock attempt:
//
//   released early   -> the tap completes, and its completion frame is
//                       strictly LESS than threshold frames after the press
//   held to N        -> the hold completes EXACTLY N frames after the press
//   held past N      -> that completion frame does not move, and the tap
//                       never fires on the release of an already-answered hold
//
// The threshold is deliberately half a second: long enough that the early
// release cannot race it, and long enough for the pending window itself to be
// observed rather than inferred.
//============================================================================

class UCk_AutoTest_Intent_TapVsHoldResolvesAtThresholds : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _PunchKey;
    private FName _PunchButtonName;

    private int32 _HoldThresholdFrames = 30;

    private int32 _TapPressFrame  = -1;
    private int32 _TapFrame       = -1;
    private int32 _HoldPressFrame = -1;
    private int32 _HoldFrame      = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::H;
        _PunchButtonName = _PunchKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

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
        Add_Step(          "bake the tap/hold pair and activate it",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press the punch",                                     n"Step_Press");
        Add_Step_WaitUntil("the press is held pending",                           n"Check_TapIsPending");
        Add_Step(          "record the press frame, then release early",          n"Step_RecordThenReleaseEarly");
        Add_Step_WaitUntil("the tap resolves",                                    n"Check_TapCompleted");
        Add_Step(          "assert the tap answered before the threshold",        n"Step_AssertTap");

        Add_Step(          "press the punch again",                               n"Step_Press");
        Add_Step_WaitUntil("the new press is held pending",                       n"Check_HoldIsPending");
        Add_Step(          "record the press frame",                              n"Step_RecordHoldPress");
        Add_Step_WaitUntil("the hold reaches its threshold",                      n"Check_HoldCompleted");
        Add_Step(          "assert it landed exactly on the threshold frame",     n"Step_AssertHold");

        Add_Step_WaitSeconds("keep holding well past the threshold", 0.333f);
        Add_Step(          "assert holding longer changed nothing, then release", n"Step_AssertHeldPastThenRelease");
        Add_Step_WaitFrames("give a late tap a chance to fire",                   8);
        Add_Step(          "assert the release of an answered hold fires nothing", n"Step_AssertReleaseIsInert");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P hold=30", n"AS_Tap_Hold_Charged", 100));
        Definitions.Add(DoParse("P",         n"AS_Tap_Hold_Quick",    50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_PhysicalButton(_PunchKey));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), _HoldThresholdFrames,
            "a tap and a hold on one button is exactly the ambiguity that defers, for the longest hold declared");
        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), 0,
            "neither move needs a second button, so nothing is waiting on a chord window");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_Press(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordThenReleaseEarly(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TapPressFrame = DoFind_LatestPressFrame();

        Assert_True(_TapPressFrame >= 0,
            "a retained row must carry the press edge for the frame arithmetic to mean anything");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Charged") ==
                    ECk_Intent_Phase::Pending,
            "both rivals wait together - the press has not answered either of them yet");

        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertTap(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TapFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Tap_Hold_Quick");

        Assert_True(_TapFrame >= _TapPressFrame,
            "a completion cannot predate the press that caused it");

        Assert_True(_TapFrame - _TapPressFrame < _HoldThresholdFrames,
            "the button came up before the threshold, so the tap is the only reading left and it answers then");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Charged") !=
                    ECk_Intent_Phase::Completed,
            "a hold that never reached its threshold must not complete on the release");
    }

    UFUNCTION()
    private void Step_RecordHoldPress(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _HoldPressFrame = DoFind_LatestPressFrame();

        Assert_True(_HoldPressFrame > _TapPressFrame,
            "the second press must be a later row than the first, or the two legs are reading one episode");
    }

    UFUNCTION()
    private void Step_AssertHold(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _HoldFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Tap_Hold_Charged");

        Assert_Equals_Int(_HoldFrame - _HoldPressFrame, _HoldThresholdFrames,
            "a hold completes on the frame its threshold is reached - not a frame early, not a frame late");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Quick") ==
                    ECk_Intent_Phase::Idle,
            "the tap lost the arbitration rather than failing - a loser goes back to Idle");
    }

    UFUNCTION()
    private void Step_AssertHeldPastThenRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Tap_Hold_Charged"),
            _HoldFrame,
            "holding past the threshold does not re-complete the move on every later frame");

        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertReleaseIsInert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Tap_Hold_Charged"),
            _HoldFrame,
            "the completed hold's frame survives the release that ended the physical hold");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Quick") ==
                    ECk_Intent_Phase::Idle,
            "the episode ended when the hold won, so the release has no wait left to answer as a tap");
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
    private void Check_TapIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Quick") ==
                ECk_Intent_Phase::Pending);
    }

    UFUNCTION()
    private void Check_TapCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Quick") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_HoldIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Charged") ==
                ECk_Intent_Phase::Pending);
    }

    UFUNCTION()
    private void Check_HoldCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Tap_Hold_Charged") ==
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

    private void DoInject(ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    // Offset 0 is the newest row, so the first press found walking forward from it is the most recent one.
    private int32 DoFind_LatestPressFrame()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
            auto Pressed = Row.Get_Pressed();

            for (auto Index = 0; Index < Pressed.Num(); Index++)
            {
                if (Pressed[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
                { continue; }

                if (Pressed[Index].Get_Name() == _PunchButtonName)
                { return Row.Get_FrameIndex(); }
            }
        }

        return -1;
    }
}
