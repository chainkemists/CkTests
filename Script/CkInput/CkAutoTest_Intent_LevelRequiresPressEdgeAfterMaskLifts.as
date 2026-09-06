// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE MASK LIFTING IS NOT AN INPUT
//============================================================================
//
// The eight level tests around this one all drive the state with input, and
// every one of them would still pass against an implementation that computed
// `Active` as "is this button in the held union, and is it deliverable?". That
// is the single most likely wrong implementation of a level row - it is
// simpler, it needs no memory, and it agrees with the correct one on every
// sequence made only of presses, releases and a mask that stays up.
//
// They disagree on exactly one sequence, which is this test: the mask comes
// DOWN while the button is still physically held. A derived state comes back
// on by itself, because both of its inputs are true again. A state that
// remembers it was opened by a visible press EDGE stays off, because no edge
// arrived - the player has not touched anything since the modal opened.
//
//   press           -> Active
//   mask the key    -> Idle          (already covered by DeactivatesUnderModal)
//   UNMASK the key  -> still Idle    <- the discriminator, and only here
//   release, press  -> Active        (the re-press the policy demands)
//
// The last leg is not decoration. Without it, "still Idle" is satisfied by a
// matcher that has stopped answering the button at all - a capture removal
// that dropped the row would look identical to the correct behaviour, and the
// re-press is the only thing that tells them apart.
//
// The unmask is the reason the settle after it is a settle rather than a
// condition: "did not re-activate" is already true on arrival, so what makes
// the silence mean anything is the positive activation on either side of it.
//============================================================================

class UCk_AutoTest_Intent_LevelRequiresPressEdgeAfterMaskLifts : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_InputLayer     _Masker;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _DragKey;

    private int32 _FirstActivationFrame = -1;

    private TArray<ECk_Intent_Phase> _FromPhases;
    private TArray<ECk_Intent_Phase> _ToPhases;
    private TArray<int32>            _Frames;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _DragKey = EKeys::K;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_DragKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        _Masker  = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Masker),  "the masking layer must be created");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the lower layer");

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnIntentPhaseChanged"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the drag key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the level intent and activate it",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",          n"Check_SetActive");

        Add_Step(          "press and keep holding",                            n"Step_Press");
        Add_Step_WaitUntil("the state opens",                                    n"Check_Active");
        Add_Step(          "record the activation frame",                        n"Step_RecordFirstActivation");

        Add_Step(          "open a modal over the hold",                         n"Step_Mask");
        Add_Step_WaitUntil("the modal's capture is in force",                    n"Check_Masked");
        Add_Step_WaitUntil("the state closes",                                   n"Check_Idle");

        // The whole test. The key is STILL DOWN across this removal - nothing about the player
        // changed, only about who may hear them.
        Add_Step(          "close the modal while the key is still down",        n"Step_Unmask");
        Add_Step_WaitUntil("the capture is really gone",                         n"Check_Unmasked");
        Add_Step_WaitSeconds("give a self-reactivation a real window to happen in", 0.667f);
        Add_Step(          "assert the lifted mask opened nothing",              n"Step_AssertNoSelfReactivation");

        // The two edges are separate steps, gated on the record between them, because a release and
        // a press that collapse onto ONE row are the same-frame open-and-close case - a different
        // contract, pinned by its own test, and it would close this state on the frame it opened.
        Add_Step(          "let go",                                             n"Step_Release");
        Add_Step_WaitUntil("the release reaches the record",                      n"Check_ReleaseRecorded");
        Add_Step(          "press again - a real edge this time",                n"Step_Press");
        Add_Step_WaitUntil("the state opens again",                              n"Check_Active");
        Add_Step(          "assert the re-press is what opened it",              n"Step_AssertRepressReopened");
        Add_Step(          "let go",                                             n"Step_Release");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV level", n"AS_Level_Edged", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_PhysicalButton(_DragKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_Press(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordFirstActivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstActivationFrame = utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Edged");

        Assert_True(_FirstActivationFrame >= 0,
            "an open state must name the frame it opened on, or the second activation has nothing to be distinguished from");
    }

    UFUNCTION()
    private void Step_Mask(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_input_layer::Request_AddCapture(_Masker, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(_DragKey, ECk_InputLayer_CaptureBehavior::Consume)));
    }

    UFUNCTION()
    private void Step_Unmask(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_input_layer::Request_RemoveCapture(_Masker, FCk_Request_InputLayer_RemoveCapture(
            ECk_InputLayer_CaptureMatch::Key, _DragKey));
    }

    UFUNCTION()
    private void Step_AssertNoSelfReactivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(DoContainsDragKey(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held()),
            "the premise of the whole test: the button is STILL DOWN, so a state derived from held-ness plus deliverability has both of its inputs back");

        Assert_False(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _DragKey),
            "and delivery is really restored - a capture that outlived the removal would make the silence below prove nothing");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Edged") ==
                    ECk_Intent_Phase::Idle,
            "the modal closing is not an input - only a fresh visible press edge opens a state, and the player has not touched anything since");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Edged"), -1,
            "and it names no frame, because there is no state to have opened on one");

        Assert_Equals_Int(_FromPhases.Num(), 2,
            "one open and one close so far - a third transition here is the row coming back on its own");
    }

    UFUNCTION()
    private void Step_AssertRepressReopened(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto SecondActivationFrame = utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Edged");

        Assert_True(SecondActivationFrame > _FirstActivationFrame,
            "the re-press opened a NEW state on its own frame - this is what separates 'stayed off because no edge arrived' from 'stayed off because the row stopped answering'");

        Assert_Equals_Int(_FromPhases.Num(), 3,
            "open, close, open: exactly one transition per real edge, and none for the mask lifting");

        if (_FromPhases.Num() != 3)
        { return; }

        Assert_True(_FromPhases[2] == ECk_Intent_Phase::Idle && _ToPhases[2] == ECk_Intent_Phase::Active,
            "the third transition is the re-press opening the state, not the unmask");

        Assert_Equals_Int(_Frames[2], SecondActivationFrame,
            "the broadcast open and the polled open are one reading of one press row");
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
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Edged") ==
                ECk_Intent_Phase::Active);
    }

    UFUNCTION()
    private void Check_Idle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Edged") ==
                ECk_Intent_Phase::Idle);
    }

    // Both capture edits are DEFERRED, so both legs wait on the layer's own answer rather than on a
    // hop count - asserting one hop after either request would be asserting against an edit that has
    // not landed.
    UFUNCTION()
    private void Check_Masked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _DragKey));
    }

    UFUNCTION()
    private void Check_Unmasked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _DragKey) == false);
    }

    // The first release of the whole test, so finding ANY release of this key in the ring is finding
    // this one. The re-press must not land in the same batch as it - see the step list.
    UFUNCTION()
    private void Check_ReleaseRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_DragKey, ECk_InputSource_EventType::Released));
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

        if (InIntentName != n"AS_Level_Edged")
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

    private bool DoFind_RoutedEdge(FKey InKey, ECk_InputSource_EventType InEventType)
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
            auto Routed = Row.Get_RoutedEvents();

            for (auto Index = 0; Index < Routed.Num(); Index++)
            {
                if (Routed[Index].Get_Event().Get_Key() != InKey)
                { continue; }

                if (Routed[Index].Get_Event().Get_EventType() != InEventType)
                { continue; }

                return true;
            }
        }

        return false;
    }

    private bool DoContainsDragKey(const TArray<FCk_Input_ButtonId>& InButtons)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == _DragKey.GetKeyName())
            { return true; }
        }

        return false;
    }
}
