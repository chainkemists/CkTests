// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THREE NOTCHES IN ONE FRAME ARE THREE NOTCHES
//============================================================================
//
// A wheel spun quickly delivers several notches inside one frame's worth of
// input, and a frame is exactly the resolution the sampler records at. So the
// batch arrives as press/release/press/release/press/release with nothing in
// between, and the question is what a RECORD whose row carries one Pressed set
// and one Released set can say about it.
//
// Folding the batch into one row cannot say it. Held-ness is a set, so three
// presses of one key collapse to one entry, the edges collapse with them, and
// the matcher - which reads EDGES - sees one notch. The player's other two
// vanish. Nothing reports it: the completion that did happen looks perfectly
// healthy, and scroll-to-cycle simply moves one step instead of three under
// exactly the input that makes a wheel feel bad to use.
//
// So the sampler SPLITS the batch at each repeat of an edge it has already
// recorded, and N notches become N rows carrying N press edges. This test
// asserts that from both ends, because either alone is satisfiable by
// accident:
//
//   the RECORD carries three rows, each with the notch's press and its release
//   the MATCHER completes three times, on three distinct frames
//
// The frames being distinct is what makes the second reading mean "three
// events" rather than "one event announced three times" - a re-completion
// stamped on the frame the previous one used would be the same row answering
// twice.
//
// The sibling test, WheelNotchRepeatsWithoutAnIntermediateRelease, pins the
// PAIR staying collapsed onto one row. The two are not in tension and the
// distinction is the whole rule: a press and its own release belong together,
// a press and ANOTHER press do not.
//============================================================================

class UCk_AutoTest_Intent_WheelMultiNotchSameBatchAllComplete : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _NotchKey;

    private int32 _NotchCount = 3;

    private TArray<int32> _CompletionFrames;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _NotchKey = EKeys::MouseScrollDown;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_NotchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        // Three completions land within a few frames of each other and are all read afterwards, so
        // the decay window must outlast the whole burst plus the settle behind it.
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(200);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentCompleted(_Matcher,
            FCk_Delegate_IntentMatcher_Completed(this, n"OnIntentCompleted"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the notch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move on the notch terminal",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the notch capture",                n"Check_SetActive");

        Add_Step(          "spin the wheel three notches inside one batch",       n"Step_ThreeNotches");
        Add_Step_WaitUntil("three completions arrive",                            n"Check_AllCompleted");
        Add_Step_WaitFrames("give a fourth completion a window to show up in",     30);
        Add_Step(          "assert three notches produced three of everything",   n"Step_AssertAllThree");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("WN", n"AS_MultiNotch_Cycle", 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"WN", DoMake_PhysicalButton(_NotchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    // Every edge in ONE step, which is what puts all six of them in one batch - the shape a fast
    // wheel spin produces, and the whole point of the test.
    UFUNCTION()
    private void Step_ThreeNotches(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Notch = 0; Notch < _NotchCount; Notch++)
        {
            DoInject(ECk_InputSource_EventType::Pressed);
            DoInject(ECk_InputSource_EventType::Released);
        }
    }

    UFUNCTION()
    private void Step_AssertAllThree(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(DoCount_RowsCarryingBothEdges(), _NotchCount,
            "the record carries one row per notch - a batch folded into a single row loses every repeat, because held-ness is a SET and three presses of one key collapse into one entry");

        Assert_Equals_Int(_CompletionFrames.Num(), _NotchCount,
            "and the matcher answered every one of them - it reads EDGES, so a collapsed batch would complete once and the player's other two notches would simply not exist");

        if (_CompletionFrames.Num() != _NotchCount)
        { return; }

        // Strictly increasing rather than merely distinct: rows are appended in order, so a
        // completion stamped out of order would mean the split produced rows the record does not
        // actually carry in that sequence.
        for (auto Index = 1; Index < _CompletionFrames.Num(); Index++)
        {
            Assert_True(_CompletionFrames[Index] > _CompletionFrames[Index - 1],
                f"completion {Index} must name a LATER frame than the one before it - three fires on one frame is one row answering three times, not three notches");
        }

        Assert_False(DoContainsNotchButton(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held()),
            "and the burst left nothing held - a split that kept the last press without its release would wedge the key down for the rest of the session");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_MultiNotch_Cycle"),
            _CompletionFrames[_CompletionFrames.Num() - 1],
            "the poll surface holds the LAST completion, and the signal and the poll are two views of one row rather than two sources of truth");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _NotchKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_HasActiveSet(_Matcher) &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_NotchKey));
    }

    // POSITIVE: the three fires have to arrive for anything below to be readable. The "and not a
    // fourth" half is already true on arrival and cannot be a condition, so it rides the settle
    // behind this wait.
    UFUNCTION()
    private void Check_AllCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CompletionFrames.Num() >= _NotchCount);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnIntentCompleted(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        int32 InFrame)
    {
        if (IsFinished())
        { return; }

        if (InIntentName != n"AS_MultiNotch_Cycle")
        { return; }

        _CompletionFrames.Add(InFrame);
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
            ECk_InputSource_DeviceClass::Mouse,
            _NotchKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    // How many rows carry BOTH a press and a release of the notch button. One per notch is the split
    // having happened; one row total is the batch having been folded.
    private int32 DoCount_RowsCarryingBothEdges()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);
        auto Rows  = 0;

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsNotchButton(Row.Get_Pressed()) == false)
            { continue; }

            if (DoContainsNotchButton(Row.Get_Released()) == false)
            { continue; }

            Rows++;
        }

        return Rows;
    }

    private bool DoContainsNotchButton(const TArray<FCk_Input_ButtonId>& InButtons)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == _NotchKey.GetKeyName())
            { return true; }
        }

        return false;
    }
}
