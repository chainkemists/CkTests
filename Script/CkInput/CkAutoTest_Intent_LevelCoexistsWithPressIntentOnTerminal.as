// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: ONE PRESS, TWO ANSWERS, NO WAITING
//============================================================================
//
// The arbiter's rule is that one press resolves to exactly ONE intent - the
// most dominant one whose prefix is behind it. A level intent is not a
// competitor in that arbitration at all: it is a state the same press opens,
// on the same frame, without taking the press away from anybody.
//
// So the interesting case is the terminal that carries both. A tap and a drag
// on one button is the ordinary shape of a hold-to-drag control, and it must
// cost nothing: the tap completes on its own press frame and the drag opens
// on that same frame. Asserting the two frames are EQUAL is what makes this a
// test rather than a demonstration - it goes red the moment level rows are
// put back inside the first-match-wins arbiter, where the drag would either
// steal the press from the tap or be starved by it.
//
// The pair must also not DEFER. A tap and a hold on one button defer, because
// they cannot be told apart until the threshold passes; a tap and a level
// intent cannot be confused for one another at all, so the bake must write no
// verdict and the press must be answered immediately.
//
// The priorities are 100 and 50, deliberately distinct: a TIE would be
// rejected by the bake's total-order rule, so a test written with equal
// priorities would fail at the bake and never reach the behaviour it is for.
//
// The decay window is long, because the last leg reads the tap's latch after
// the drag has been released - a short window would let the latch expire and
// the final assertion would be reporting the clock, not the arbitration.
//============================================================================

class UCk_AutoTest_Intent_LevelCoexistsWithPressIntentOnTerminal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _DragKey;
    private FName _DragButtonName;

    private int32 _TapFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _DragKey = EKeys::N;
        _DragButtonName = _DragKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_DragKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(600);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the drag key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the tap/drag pair on one terminal",             n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",          n"Check_SetActive");

        Add_Step(          "press the shared terminal once",                     n"Step_Press");
        Add_Step_WaitUntil("the tap completes AND the drag opens",               n"Check_BothAnswered");
        Add_Step(          "assert one press answered both, on one frame",       n"Step_AssertSameFrame");

        Add_Step(          "release",                                            n"Step_Release");
        Add_Step_WaitUntil("the drag closes",                                    n"Check_HoldIdle");
        Add_Step(          "assert the release did not disturb the tap's latch", n"Step_AssertTapLatchIntact");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV",       n"AS_Level_Tap",  100));
        Definitions.Add(DoParse("LV level", n"AS_Level_Hold",  50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_PhysicalButton(_DragKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "an edge intent and a level intent on one terminal is a legal set - distinct priorities keep the total order intact");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_PhysicalButton(_DragKey));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "a level intent is not a hold sibling - nothing about the tap has to wait to find out whether the drag 'wins'");
        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), 0,
            "a single-button terminal completes no chord, so no partner press can be in flight");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_Press(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertSameFrame(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PressFrame = DoFind_LatestPressFrame();

        Assert_True(PressFrame >= 0,
            "a retained row must carry the press edge for the frame comparison to mean anything");

        _TapFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Level_Tap");

        Assert_Equals_Int(_TapFrame, PressFrame,
            "the edge intent still completes on its own press frame - sharing the terminal with a state costs it nothing");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Hold"),
            _TapFrame,
            "the state opened on the SAME press, not on a later one - a level row inside the first-match-wins arbiter could only give one of them this frame");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Level_Hold"), -1,
            "the drag is a state, so it never completes however the press was arbitrated");
    }

    UFUNCTION()
    private void Step_Release(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertTapLatchIntact(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Tap") ==
                    ECk_Intent_Phase::Completed,
            "the tap's latch outlives the drag: the decay window is 600 frames and nothing about closing a state may touch a sibling's phase");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Level_Tap"),
            _TapFrame,
            "and it still names the frame it was stamped with - a re-stamp would read as a second press that never happened");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _DragKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_ActiveIntentCount(_Matcher) == 2 &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_DragKey));
    }

    UFUNCTION()
    private void Check_BothAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Tap") ==
                    ECk_Intent_Phase::Completed &&
                utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Hold") ==
                    ECk_Intent_Phase::Active);
    }

    UFUNCTION()
    private void Check_HoldIdle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Hold") ==
                ECk_Intent_Phase::Idle);
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
            _DragKey,
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

                if (Pressed[Index].Get_Name() == _DragButtonName)
                { return Row.Get_FrameIndex(); }
            }
        }

        return -1;
    }
}
