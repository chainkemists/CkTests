// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A STATE THAT OPENS AND CLOSES ON ONE FRAME
//============================================================================
//
// A hitch, a wheel notch, or simply a tap short enough to fit inside one
// logic frame puts a press and its release into the SAME sampler row. The
// level lifecycle answers that with two transitions stamped on one frame —
// `Active` then `Idle` — and the ordering is deliberate: activation is
// evaluated ahead of the release precisely so that a tap under a hitch is
// seen to have HAPPENED rather than never entered at all.
//
// Both halves are worth pinning because both have a plausible wrong answer:
//
//   an implementation that evaluated the release first would never open the
//   state, and a consumer counting drags would silently miss every one that
//   fell inside a bad frame
//
//   an implementation that opened the state and left the release for the next
//   row would leave a door held open by a button nobody is holding — the
//   record says the key came up on that very frame
//
// So the poll AFTERWARDS reads `Idle` and the SIGNALS are what carry the fact
// that anything happened. That is the two-surface rule at its sharpest: the
// poll is the authority on state, the signals are the account of the
// transitions, and here the two disagree about whether the frame was
// eventful — correctly.
//
// The collapse itself is asserted rather than assumed. Both edges are injected
// in one step, which is what puts them in one batch, but "one batch" becomes
// "one row" only if the sampler does not split it — so the row carrying BOTH
// edges is looked up by hand. Without that, a sampler that split the pair
// would still pass every phase assertion below for the wrong reason.
//============================================================================

class UCk_AutoTest_Intent_LevelCollapsedPressReleaseOneRow : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _TapKey;

    private TArray<ECk_Intent_Phase> _FromPhases;
    private TArray<ECk_Intent_Phase> _ToPhases;
    private TArray<int32>            _Frames;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _TapKey = EKeys::L;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_TapKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnIntentPhaseChanged"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the tap key and the sampler records",  n"Check_Recording");
        Add_Step(          "bake the level intent and activate it",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",          n"Check_SetActive");

        Add_Step(          "tap inside one frame (press + release together)",    n"Step_CollapsedTap");
        Add_Step_WaitUntil("both transitions are broadcast",                     n"Check_BothTransitions");
        Add_Step_WaitFrames("give a third transition a window to show up in",     30);
        Add_Step(          "assert the pair opened and closed on ONE frame",     n"Step_AssertCollapsedPair");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV level", n"AS_Level_Collapsed", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_PhysicalButton(_TapKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    // Both edges in one step, which is what puts them in one batch — the shape a hitch or a
    // sub-frame tap produces.
    UFUNCTION()
    private void Step_CollapsedTap(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertCollapsedPair(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto CollapsedFrame = DoFind_FrameCarryingBothEdges();

        Assert_True(CollapsedFrame >= 0,
            "the premise: ONE row carries both the press and the release — a sampler that split the batch would satisfy every phase assertion below for a reason this test is not about");

        Assert_Equals_Int(_FromPhases.Num(), 2,
            "a collapsed pair is TWO transitions, not one — an implementation that evaluated the release first would open nothing, and one that deferred the release would leave this at one");

        if (_FromPhases.Num() != 2)
        { return; }

        Assert_True(_FromPhases[0] == ECk_Intent_Phase::Idle && _ToPhases[0] == ECk_Intent_Phase::Active,
            "activation is evaluated ahead of the release, so the tap is seen to have happened rather than never entered");

        Assert_True(_FromPhases[1] == ECk_Intent_Phase::Active && _ToPhases[1] == ECk_Intent_Phase::Idle,
            "and the release on that same row closes it — the record says the key came up, so nothing may still be holding the door");

        Assert_Equals_Int(_Frames[0], CollapsedFrame,
            "the open names the row the press landed on");

        Assert_Equals_Int(_Frames[1], _Frames[0],
            "both edges are ONE frame's worth of history, so both transitions name that frame — a close stamped a frame later would tell a consumer the state had a duration it never had");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Collapsed") ==
                    ECk_Intent_Phase::Idle,
            "a poll afterwards reads Idle: the poll is the authority on STATE, and the state is over");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Collapsed"), -1,
            "and it names no activation frame, because there is no open state to have one — the two payloads are the only account of the frame");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _TapKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_ActiveIntentCount(_Matcher) == 1 &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_TapKey));
    }

    // A POSITIVE condition: the two transitions have to arrive for anything below to be readable. The
    // "and no third one" half cannot be a condition — it is already true on arrival — so it rides the
    // settle behind this wait instead.
    UFUNCTION()
    private void Check_BothTransitions(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FromPhases.Num() >= 2);
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

        if (InIntentName != n"AS_Level_Collapsed")
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
            _TapKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    // The frame index of the row whose Pressed AND Released both name this button, or -1 when no row
    // carries both — which is the collapse not having happened.
    private int32 DoFind_FrameCarryingBothEdges()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsTapButton(Row.Get_Pressed()) == false)
            { continue; }

            if (DoContainsTapButton(Row.Get_Released()) == false)
            { continue; }

            return Row.Get_FrameIndex();
        }

        return -1;
    }

    private bool DoContainsTapButton(const TArray<FCk_Input_ButtonId>& InButtons)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == _TapKey.GetKeyName())
            { return true; }
        }

        return false;
    }
}
