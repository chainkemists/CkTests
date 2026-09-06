// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: EVERY TRANSITION, IN ORDER, ONCE
//============================================================================
//
// A phase cannot change without its signal. That is enforced structurally
// one writer owns the phase fields and broadcasts from inside itself - and
// this is the test that would catch it coming apart.
//
// A charged move is driven through its entire life in one press and the
// transitions are recorded as they arrive:
//
//   Idle -> Pending     the press is ambiguous between tap and hold
//   Pending -> Completed the threshold is reached
//   Completed -> Idle    the latch decays
//
// Three, in that order, no more. The count matters as much as the order: a
// writer that fired on every tick the phase merely STAYED the same would
// produce the same three transitions plus noise, and a consumer driving an
// animation off the completion would retrigger it every frame.
//
// The frames are asserted too, because the order alone does not prove the
// timing: the completion must sit exactly the hold threshold after the press,
// and the decay exactly the decay window after the completion. A short decay
// window is chosen so the whole lifecycle fits comfortably inside the test.
//
// Only the charged move's transitions are recorded. Its tap rival is
// transitioning too - Idle -> Pending -> Idle as it loses - and filtering by
// name in the handler is how a consumer of this signal is meant to work,
// since identity rides the payload rather than the subscription.
//============================================================================

class UCk_AutoTest_Intent_PhaseChangedObservesFullOrder : UCk_AutoTest_Base
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
    private int32 _LatchDecayFrames    = 15;

    private TArray<ECk_Intent_Phase> _FromPhases;
    private TArray<ECk_Intent_Phase> _ToPhases;
    private TArray<int32>            _Frames;

    private int32 _PressFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::A;
        _PunchButtonName = _PunchKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(_LatchDecayFrames);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnIntentPhaseChanged"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the tap/hold pair and activate it",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press and keep holding",                              n"Step_Press");
        Add_Step_WaitUntil("the wait opens",                                       n"Check_PendingHeard");
        Add_Step(          "record the press frame",                               n"Step_RecordPress");
        Add_Step_WaitUntil("the whole lifecycle has been broadcast",                n"Check_ThreeTransitions");
        Add_Step_WaitSeconds("give a duplicate or a fourth transition a chance",    0.167f);
        Add_Step(          "assert the order, the count and the timing",            n"Step_AssertLifecycle");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P hold=30", n"AS_Order_Charged", 100));
        Definitions.Add(DoParse("P",         n"AS_Order_Quick",    50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_Press(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_RecordPress(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PressFrame = DoFind_LatestPressFrame();

        Assert_True(_PressFrame >= 0,
            "a retained row must carry the press edge for the timing assertions to mean anything");
    }

    UFUNCTION()
    private void Step_AssertLifecycle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FromPhases.Num(), 3,
            "the charged move's whole life is three transitions - a writer that also fired on unchanged phases would add noise a consumer would replay as gameplay");

        if (_FromPhases.Num() != 3)
        { return; }

        Assert_True(_FromPhases[0] == ECk_Intent_Phase::Idle && _ToPhases[0] == ECk_Intent_Phase::Pending,
            "the press is ambiguous between the tap and the hold, so it opens a wait rather than answering");

        Assert_True(_FromPhases[1] == ECk_Intent_Phase::Pending && _ToPhases[1] == ECk_Intent_Phase::Completed,
            "reaching the threshold answers the wait in the charged move's favour");

        Assert_True(_FromPhases[2] == ECk_Intent_Phase::Completed && _ToPhases[2] == ECk_Intent_Phase::Idle,
            "the latch decays back to Idle, which is the only transition that fires PhaseChanged without a completion");

        Assert_Equals_Int(_Frames[0], _PressFrame,
            "the wait opens on the press row itself");

        Assert_Equals_Int(_Frames[1] - _PressFrame, _HoldThresholdFrames,
            "the completion lands exactly the hold threshold after the press");

        Assert_Equals_Int(_Frames[2] - _Frames[1], _LatchDecayFrames,
            "the decay lands exactly the decay window after the completion, not a frame either side");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Order_Charged") ==
                    ECk_Intent_Phase::Idle,
            "the poll surface agrees with the last transition it was told about");
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
    private void Check_PendingHeard(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FromPhases.Num() >= 1);
    }

    UFUNCTION()
    private void Check_ThreeTransitions(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_FromPhases.Num() >= 3);
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
        if (InIntentName != n"AS_Order_Charged")
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
