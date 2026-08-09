// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE PARTNER ARRIVES, OR IT DOES NOT
//============================================================================
//
// The second forward ambiguity. A button that is both a move's terminal on
// its own AND half of a two-button chord cannot be answered on the press
// frame: the partner may still be in flight. So the press waits out the
// chord window, and the two ways that wait can end are both pinned here
// against ONE set in ONE session.
//
//   partner arrives -> the chord completes, and the bare move does NOT also
//                      fire on the same press
//   window expires  -> the bare move completes, and the gap between the press
//                      row and the completion frame is at least the window
//
// The gap is the assertion that matters, and it is why the fixture bakes a
// deliberately wide window rather than the default: a matcher that quietly
// answered on the press frame would pass a "the bare move completed" check
// and fail this one.
//
// Latency was paid; history was not rewritten. The completion frame names
// the frame the WAIT ended on, while the backward scan behind it is still
// anchored on the press row — those are two different frames on purpose, and
// conflating them would either lie about when the game reacted or lie about
// what the player did.
//============================================================================

class UCk_AutoTest_Intent_ChordWindowResolvesPartnerOrTimeout : UCk_AutoTest_Base
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
    private FKey  _KickKey;

    // Two thirds of a second, an order of magnitude past the shipped default. Wide enough that the partner press
    // cannot lose a race with the harness's own step cadence on a slow editor, and wide enough that the timeout
    // leg's gap assertion cannot pass by accident.
    private int32 _ChordWindowFrames = 40;

    private int32 _ChordFrame     = -1;
    private int32 _TimeoutPress   = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::I;
        _PunchButtonName = _PunchKey.GetKeyName();
        _KickKey = EKeys::O;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);
        PhysicalButtons.Add(_KickKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints both keys and the sampler records",   n"Check_Recording");
        Add_Step(          "bake the chord/bare pair and activate it",          n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers both terminals' captures",       n"Check_SetActive");

        Add_Step(          "press the punch",                                   n"Step_PressPunch");
        Add_Step_WaitUntil("the press is held pending",                         n"Check_BareIsPending");
        Add_Step(          "press the kick inside the window",                  n"Step_PressKick");
        Add_Step_WaitUntil("the chord completes",                               n"Check_ChordCompleted");
        Add_Step(          "assert the chord won it alone, then let both go",   n"Step_AssertChordThenRelease");
        Add_Step_WaitUntil("both keys leave the held set",                      n"Check_BothReleased");

        Add_Step(          "press the punch with no partner coming",            n"Step_PressPunch");
        Add_Step_WaitUntil("the press is held pending",                         n"Check_BareIsPending");
        Add_Step(          "record the press frame",                            n"Step_RecordTimeoutPress");
        Add_Step_WaitUntil("the bare move completes after the window",          n"Check_BareCompleted");
        Add_Step(          "assert the wait was real and the chord lost",       n"Step_AssertTimeout");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P+K", n"AS_Chord_Both", 100));
        Definitions.Add(DoParse("P",   n"AS_Chord_Bare",  50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));
        Rows.Add(FCk_Intent_ButtonNameRow(n"K", DoMake_PhysicalButton(_KickKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, _ChordWindowFrames);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_PhysicalButton(_PunchKey));

        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), _ChordWindowFrames,
            "the punch both terminates a move alone and completes a chord, which is the chord ambiguity exactly");
        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "neither move declares a hold, so nothing is waiting on a threshold");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressPunch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_PunchKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_PressKick(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_KickKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertChordThenRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ChordFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Chord_Both");

        Assert_True(_ChordFrame >= 0,
            "the chord must carry a real completion frame");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Chord_Bare") !=
                    ECk_Intent_Phase::Completed,
            "one press resolves to ONE intent — the chord is what the player asked for, so the bare move loses");

        DoInject(_PunchKey, ECk_InputSource_EventType::Released);
        DoInject(_KickKey,  ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_RecordTimeoutPress(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TimeoutPress = DoFind_LatestPunchPressFrame();

        Assert_True(_TimeoutPress >= 0,
            "a retained row must carry the second press edge for the gap to be measurable");
    }

    UFUNCTION()
    private void Step_AssertTimeout(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto BareFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Chord_Bare");

        Assert_True(BareFrame - _TimeoutPress >= _ChordWindowFrames,
            "the bare move could only answer once the chord window had actually expired, so the gap between the press row and the completion is at least the whole window");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Chord_Both") ==
                    ECk_Intent_Phase::Idle,
            "the chord was in the running for this press and lost, which returns it to Idle rather than Failed");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _PunchKey).Num() >= 1 &&
                utils_input_button_map::Get_ButtonIdsForKey(_Map, _KickKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Keys = utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher);

        Res.Set(utils_intent_matcher::Get_ActiveIntentCount(_Matcher) == 2 &&
                Keys.Contains(_PunchKey) && Keys.Contains(_KickKey));
    }

    UFUNCTION()
    private void Check_BareIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Chord_Bare") ==
                ECk_Intent_Phase::Pending);
    }

    UFUNCTION()
    private void Check_ChordCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Chord_Both") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_BothReleased(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Held = utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held();

        Res.Set(Held.Num() == 0);
    }

    UFUNCTION()
    private void Check_BareCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Chord_Bare") ==
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

    private void DoInject(FKey InKey, ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            InKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    private int32 DoFind_LatestPunchPressFrame()
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
