// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A STATE OPENS ON THE PRESS ROW ITSELF
//============================================================================
//
// An edge intent answers a press with a completion; a level intent answers it
// by BEING ON, and the moment it turns on is the same moment - the frame the
// press was recorded on, not the frame the matcher happened to notice it.
// This is the level primitive's cheapest and most load-bearing promise: a
// consumer polling the activation frame is reading a fact about the input,
// so it may be compared against the record, replayed, and rolled back.
//
// The frame is asserted against the RECORD's own press row rather than
// against a captured "frame at the time of the step", because those two are
// only the same number when the implementation stamps the press row. An
// activation stamped at scan time would drift by however many passes the
// deferral machinery took, and a hop-count assertion would have absorbed the
// drift silently.
//
// Three readings are pinned in one step so they cannot be satisfied
// separately: the poll (activation frame), the absence of the OTHER poll
// (completion frame stays -1 for a level intent, always), and the signal
// (exactly one transition, Idle -> Active, naming the same frame). An
// implementation that routed level rows through the edge arbiter would pass
// the first and fail the second; one that polled without broadcasting would
// pass both and fail the third.
//
// A lone level intent on the terminal is the point, not a simplification: the
// bake must write NO deferral for it, so nothing about the timing is allowed
// to depend on a forward ambiguity that does not exist.
//============================================================================

class UCk_AutoTest_Intent_LevelActivatesOnPressFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _DragKey;
    private FName _DragButtonName;

    private TArray<ECk_Intent_Phase> _FromPhases;
    private TArray<ECk_Intent_Phase> _ToPhases;
    private TArray<int32>            _Frames;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _DragKey = EKeys::F8;
        _DragButtonName = _DragKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_DragKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        // A level intent never completes, so the decay window governs nothing here - it is set long
        // anyway so a failure can never be read as "the latch expired mid-assertion".
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(200);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnIntentPhaseChanged"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the drag key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the lone level intent and activate it",         n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",          n"Check_SetActive");

        Add_Step(          "press the drag key",                                 n"Step_Press");
        Add_Step_WaitUntil("the state opens",                                    n"Check_Active");
        Add_Step(          "assert it opened on the press row, and only once",   n"Step_AssertActivation");
        Add_Step(          "release the key",                                    n"Step_Release");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV level", n"AS_Level_Drag", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_PhysicalButton(_DragKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        // Read straight off the artifact: a level terminal introduces no forward ambiguity, so the
        // activation frame below cannot be explained away by the matcher merely being prompt.
        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_PhysicalButton(_DragKey));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "a level intent declares no hold, and nothing shares its terminal, so no hold threshold is waited on");
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
    private void Step_AssertActivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PressFrame = DoFind_LatestPressFrame();

        Assert_True(PressFrame >= 0,
            "a retained row must carry the press edge for the frame arithmetic to mean anything");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Drag"),
            PressFrame,
            "the state opens on the frame the press was RECORDED on, not on whichever later pass the matcher scanned");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Level_Drag"), -1,
            "a level intent has no completion at all - a frame here would mean level rows are still being run through the edge arbiter");

        Assert_Equals_Int(_FromPhases.Num(), 1,
            "opening a state is ONE transition - a writer that re-fired while the phase merely stayed Active would retrigger whatever a consumer drives off it");

        if (_FromPhases.Num() != 1)
        { return; }

        Assert_True(_FromPhases[0] == ECk_Intent_Phase::Idle && _ToPhases[0] == ECk_Intent_Phase::Active,
            "Idle -> Active is the only transition a visible press can produce on a level intent");

        Assert_Equals_Int(_Frames[0], PressFrame,
            "the broadcast frame and the polled frame are the same reading, so a consumer that listens and one that polls cannot disagree");
    }

    UFUNCTION()
    private void Step_Release(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Released);
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
        Res.Set(utils_intent_matcher::Get_ActiveIntentCount(_Matcher) == 1 &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_DragKey));
    }

    UFUNCTION()
    private void Check_Active(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Drag") ==
                ECk_Intent_Phase::Active);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnIntentPhaseChanged(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        ECk_Intent_Phase InPreviousPhase,
        ECk_Intent_Phase InNewPhase,
        int32 InFrame)
    {
        if (IsFinished())
        { return; }

        if (InIntentName != n"AS_Level_Drag")
        { return; }

        _FromPhases.Add(InPreviousPhase);
        _ToPhases.Add(InNewPhase);
        _Frames.Add(InFrame);
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
