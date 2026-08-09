// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE THUMB KEEPS HOLDING, THE CHARGE DOES NOT
//============================================================================
//
// The fact/policy split, made observable. A modal opens while the player is
// mid-charge. Two things are true at once and a design that collapses them
// gets one of them wrong:
//
//   the FACT   — the button is still physically down, and the record still
//                says so, because a record that lied about the hardware
//                would be useless for replay, debugging and rollback alike
//   the POLICY — this layer stopped receiving the input, so its charge is
//                over. v1 ships the conservative default pair, and the loss
//                half of it is Cancel.
//
// Both are asserted in the same step against the same frame, which is the
// only way to show they are genuinely separate readings rather than one
// value read twice.
//
// The mask is applied MID-HOLD, after the pending window is observed, so the
// cancel is a transition rather than a state the episode was born into — an
// implementation that only checked deliverability at the press would pass a
// naive version of this test and fail this one.
//============================================================================

class UCk_AutoTest_Intent_DeliveryLossCancelsHold : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_InputLayer     _Masker;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _PunchKey;
    private FName _PunchButtonName;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::T;
        _PunchButtonName = _PunchKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        _Masker  = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 100));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Masker),  "the layer that will mask the hold must be created");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the lower layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a tap/hold pair and activate it",                n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "start charging",                                      n"Step_PressAndHold");
        Add_Step_WaitUntil("the charge is pending",                               n"Check_HoldIsPending");
        Add_Step(          "open a modal over the charge",                        n"Step_PushMask");
        Add_Step_WaitUntil("the charge is cancelled",                             n"Check_HoldFailed");
        Add_Step(          "assert the policy cancelled while the fact continues", n"Step_AssertFactVsPolicy");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P hold=60", n"AS_Loss_Charged", 100));
        Definitions.Add(DoParse("P",         n"AS_Loss_Quick",    50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressAndHold(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_PushMask(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_input_layer::Request_AddCapture(_Masker, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(_PunchKey, ECk_InputLayer_CaptureBehavior::Consume)));
    }

    UFUNCTION()
    private void Step_AssertFactVsPolicy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Loss_Quick") ==
                    ECk_Intent_Phase::Failed,
            "the whole ambiguity was cancelled, not just the hold half — the press answered nothing at all");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Loss_Charged"), -1,
            "a cancelled charge names no completion frame, however far it had got");

        Assert_True(DoContainsPunch(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held()),
            "the record still reports the button down — a mask changes who RECEIVES the input, never what the hardware is doing, and a record that hid that could not be replayed");
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
    private void Check_HoldIsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Loss_Charged") ==
                ECk_Intent_Phase::Pending);
    }

    UFUNCTION()
    private void Check_HoldFailed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Loss_Charged") ==
                ECk_Intent_Phase::Failed);
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

    private bool DoContainsPunch(const TArray<FCk_Input_ButtonId>& InButtons)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == _PunchButtonName)
            { return true; }
        }

        return false;
    }
}
