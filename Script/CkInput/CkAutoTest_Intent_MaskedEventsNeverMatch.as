// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A MASKED PRESS IS NOT AN INPUT
//============================================================================
//
// Matching runs per LAYER, over the events that layer was allowed to see. So
// a modal that consumes a key above the move set does not merely make the
// move feel wrong - the move is unrepresentable, because the press never
// reached the layer whose set names it.
//
// This is a NEGATIVE, and the silence is only meaningful once the machinery
// is proven to have run. The positive comes first and it is specific: the
// record must show the press, recorded as ConsumedByLayer, naming the MASKER
// as the layer that ended the walk. A router that dropped the event entirely
// would produce the same final silence for an entirely different reason.
//
// Both layers declare a Consume capture on the same key - the matcher's is
// registered for it by the swap, the masker's by hand - so nothing about the
// outcome depends on the lower layer being uninterested. It is interested,
// and it is outranked.
//============================================================================

class UCk_AutoTest_Intent_MaskedEventsNeverMatch : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_InputLayer     _Masker;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _PunchKey;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::V;

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

        Assert_True(ck::IsValid(_Masker),  "the masking layer must be created");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the lower layer");

        utils_input_layer::Request_AddCapture(_Masker, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(_PunchKey, ECk_InputLayer_CaptureBehavior::Consume)));

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare-punch set and activate it",               n"Step_SwapSet");
        Add_Step_WaitUntil("the set is live and the masker is capturing",         n"Check_Ready");

        Add_Step(          "press the punch key under the mask",                  n"Step_PressPunch");
        Add_Step_WaitUntil("the record shows the masker consumed it",             n"Check_MaskerConsumed");
        Add_Step_WaitFrames("give a masked match a chance to land late",          8);
        Add_Step(          "assert the matcher never saw an input",               n"Step_AssertIdle");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_Masked_Bare", 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressPunch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_AssertIdle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Masked_Bare") ==
                    ECk_Intent_Phase::Idle,
            "an event a higher layer consumed is not an input to the layers below it, so the move stays Idle");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Masked_Bare"), -1,
            "a move that never completed names no frame");
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
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_HasActiveSet(_Matcher) &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey) &&
                utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _PunchKey));
    }

    UFUNCTION()
    private void Check_MaskerConsumed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_MaskedPressOffset() >= 0);
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

    private int32 DoFind_MaskedPressOffset()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);
            auto Routed = Row.Get_RoutedEvents();

            for (auto Index = 0; Index < Routed.Num(); Index++)
            {
                if (Routed[Index].Get_Event().Get_Key() != _PunchKey)
                { continue; }

                if (Routed[Index].Get_Event().Get_EventType() != ECk_InputSource_EventType::Pressed)
                { continue; }

                if (Routed[Index].Get_Outcome() != ECk_InputLayer_DeliveryOutcome::ConsumedByLayer)
                { continue; }

                if (Routed[Index].Get_ConsumingLayer() != _Masker)
                { continue; }

                return Offset;
            }
        }

        return -1;
    }
}
