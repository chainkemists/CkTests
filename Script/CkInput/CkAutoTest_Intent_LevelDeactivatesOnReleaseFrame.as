// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A STATE CLOSES ON THE RELEASE ROW ITSELF
//============================================================================
//
// The other end of the state, held to the same standard as the opening one.
// A level intent turns off on the frame the release was RECORDED on — not a
// pass later, and not on the frame the matcher next scans and notices the
// button is no longer in the held set.
//
// The two ends have to be symmetric or the state is unusable for anything
// that measures it: a drag whose open is stamped from the record and whose
// close is stamped from the scan reports a duration that drifts with frame
// rate, which is precisely the class of bug the frame-indexed record exists
// to make impossible.
//
// The release frame is found by walking the record's own Released rows —
// the exact twin of the press walk in the sibling activation test, and
// deliberately a separate helper rather than a parameterised one, so a change
// to how presses are located cannot silently redefine what "the release
// frame" means.
//
// The transition list is asserted whole, not just its last entry: exactly
// two, Idle -> Active then Active -> Idle, with nothing in between. An
// implementation that dropped through Completed on the way out, or that
// re-entered Active on a subsequent scan of the still-held frames, would show
// up as a count rather than as a subtly wrong single value. And the poll is
// re-read afterwards — a closed state names no activation frame, because
// "when did the current state open" has no answer when there is no state.
//============================================================================

class UCk_AutoTest_Intent_LevelDeactivatesOnReleaseFrame : UCk_AutoTest_Base
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
        Add_Step(          "release the drag key",                               n"Step_Release");
        Add_Step_WaitUntil("the state closes",                                   n"Check_Idle");
        Add_Step(          "assert it closed on the release row, and only once", n"Step_AssertDeactivation");

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

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_PhysicalButton(_DragKey));

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "a level terminal defers for nothing, so neither end of the state can be explained by a deferral window");
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
    private void Step_Release(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertDeactivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto ReleaseFrame = DoFind_LatestReleaseFrame();

        Assert_True(ReleaseFrame >= 0,
            "a retained row must carry the release edge for the frame arithmetic to mean anything");

        Assert_Equals_Int(_FromPhases.Num(), 2,
            "a press and a release are the state's whole life — two transitions, with no Completed and no re-entry among them");

        if (_FromPhases.Num() != 2)
        { return; }

        Assert_True(_FromPhases[0] == ECk_Intent_Phase::Idle && _ToPhases[0] == ECk_Intent_Phase::Active,
            "the press opens the state");

        Assert_True(_FromPhases[1] == ECk_Intent_Phase::Active && _ToPhases[1] == ECk_Intent_Phase::Idle,
            "the release closes it straight back to Idle — a level intent never passes through Completed");

        Assert_Equals_Int(_Frames[1], ReleaseFrame,
            "the close is stamped from the release ROW, so a measured duration is frame-exact rather than drifting with the scan cadence");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Drag"), -1,
            "a closed state names no activation frame — the poll reports the CURRENT state, not the last one there was");
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

    UFUNCTION()
    private void Check_Idle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Drag") ==
                ECk_Intent_Phase::Idle);
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

    // Offset 0 is the newest row, so the first release found walking forward from it is the most recent one.
    private int32 DoFind_LatestReleaseFrame()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
            auto Released = Row.Get_Released();

            for (auto Index = 0; Index < Released.Num(); Index++)
            {
                if (Released[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
                { continue; }

                if (Released[Index].Get_Name() == _DragButtonName)
                { return Row.Get_FrameIndex(); }
            }
        }

        return -1;
    }
}
