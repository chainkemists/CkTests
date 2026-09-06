// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE THUMB KEEPS HOLDING, THE STATE DOES NOT
//============================================================================
//
// The fact/policy split again, now against a state rather than a charge. A
// modal opens while the player is mid-drag. Two things are true at once and a
// design that collapses them gets one of them wrong:
//
//   the FACT   - the button is still physically down, and the record still
//                says so, because a record that lied about the hardware would
//                be useless for replay, debugging and rollback alike
//   the POLICY - this layer stopped receiving the input, so its state is
//                over
//
// Both are asserted in the same step against the same frame, which is the
// only way to show they are genuinely separate readings rather than one value
// read twice.
//
// The second half is the one a level primitive can get wrong in a way an edge
// intent cannot: once the mask lifts, or once a later scan finds the button
// still in the held set, an implementation that derives the state from "is it
// down?" rather than from "did a visible press open it?" will turn the state
// back ON with no new input. That is why the settle after the deactivation is
// a settle and not a condition - "still Idle" is already true on arrival, so
// it can only be made meaningful by the positive assertions before it and by
// giving the reactivation a real window in which to happen.
//
// The mask is applied MID-STATE, after Active is observed, so the close is a
// transition rather than a state the intent was never allowed into: an
// implementation that only checked deliverability at the press would pass a
// naive version of this test and fail this one.
//============================================================================

class UCk_AutoTest_Intent_LevelDeactivatesUnderModal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_InputLayer     _Masker;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _DragKey;
    private FName _DragButtonName;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _DragKey = EKeys::J;
        _DragButtonName = _DragKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_DragKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        _Masker  = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Masker),  "the layer that will mask the state must be created");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the lower layer");

        Add_Step_WaitUntil("the map mints the drag key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the level intent and activate it",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",          n"Check_SetActive");

        Add_Step(          "start dragging",                                     n"Step_PressAndHold");
        Add_Step_WaitUntil("the state is open",                                  n"Check_Active");
        Add_Step(          "open a modal over the drag",                         n"Step_PushMask");
        // Capture edits are DEFERRED - the mask is not in force on the frame it was requested, so the
        // deactivation must be waited for behind the capture actually landing, never behind a hop count.
        Add_Step_WaitUntil("the modal's capture is in force",                    n"Check_MaskInForce");
        Add_Step_WaitUntil("the state closes",                                   n"Check_Idle");
        Add_Step(          "assert the policy closed while the fact continues",  n"Step_AssertFactVsPolicy");

        Add_Step_WaitSeconds("give a reactivation a real window to happen in", 0.500f);
        Add_Step(          "assert the held key never re-opens the state",       n"Step_AssertNoReactivation");
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
        Definitions.Add(DoParse("LV level", n"AS_Level_Modal", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_PhysicalButton(_DragKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressAndHold(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_PushMask(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_input_layer::Request_AddCapture(_Masker, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(_DragKey, ECk_InputLayer_CaptureBehavior::Consume)));
    }

    UFUNCTION()
    private void Step_AssertFactVsPolicy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Modal"), -1,
            "the state is over, so it names no activation frame - losing delivery ends it as surely as a release does");

        Assert_True(DoContainsDrag(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held()),
            "the record still reports the button down - a mask changes who RECEIVES the input, never what the hardware is doing, and a record that hid that could not be replayed");
    }

    UFUNCTION()
    private void Step_AssertNoReactivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Modal") ==
                    ECk_Intent_Phase::Idle,
            "after ANY deactivation a fresh press is required - a state derived from 'is the key down?' would come back on its own while the player is still holding");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Modal"), -1,
            "and it names no frame, because there is no state to have opened on one");
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
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Modal") ==
                ECk_Intent_Phase::Active);
    }

    UFUNCTION()
    private void Check_MaskInForce(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _DragKey));
    }

    UFUNCTION()
    private void Check_Idle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Modal") ==
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

    private bool DoContainsDrag(const TArray<FCk_Input_ButtonId>& InButtons)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == _DragButtonName)
            { return true; }
        }

        return false;
    }
}
