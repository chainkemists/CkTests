// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THE COMPLETION SIGNAL REACHES ANGELSCRIPT
//============================================================================
//
// Half of this test is about the intent surface and half is about the BINDING
// PATH itself. A dynamic delegate bound from script is matched by SIGNATURE,
// not by name: one parameter declared differently from the C++ delegate and
// the bind silently never fires - no compile error, no warning, just a
// handler that is never called. Script is a first-class consumer of every
// public API here, so a signal that only C++ can receive is a third of done.
//
// The handler below mirrors `FCk_Delegate_IntentMatcher_Completed` parameter
// for parameter, in order, by value. That is the shape the generated
// bindings expect and the only shape that connects.
//
// The payload is then checked for the two things that make it usable at all:
// it must NAME the intent (there is no per-intent entity to have subscribed
// to, so the name is the only discriminator a consumer has) and it must carry
// the record FRAME the move landed on, which is what lets a handler tell a
// fresh completion from a latch it has already acted on.
//
// `IgnorePayloadInFlight` because this test is about a FUTURE fire: the bind
// happens before the press, so a replay policy would prove nothing about the
// broadcast.
//============================================================================

class UCk_AutoTest_Intent_CompletedSignalFiresInAngelScript : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _PunchKey;
    private FName _PunchButtonName;

    private int32 _Fires = 0;

    private FCk_Handle_IntentMatcher _HeardMatcher;
    private FName                    _HeardName;
    private FGameplayTag             _HeardTag;
    private int32                    _HeardFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::Z;
        _PunchButtonName = _PunchKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentCompleted(_Matcher,
            FCk_Delegate_IntentMatcher_Completed(this, n"OnIntentCompleted"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move and activate it",                    n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press the punch",                                     n"Step_Press");
        Add_Step_WaitUntil("the signal reaches the script handler",               n"Check_Fired");
        Add_Step(          "assert the payload identifies the completion",        n"Step_AssertPayload");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_Signal_Move", 100));

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
    private void Step_AssertPayload(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Fires, 1,
            "one completion broadcasts exactly one OnIntentCompleted");

        Assert_True(_HeardMatcher == _Matcher,
            "the payload names the matcher the consumer bound on, which is the layer the move belongs to");

        Assert_True(_HeardName == n"AS_Signal_Move",
            "identity rides the payload - with no per-intent entity to subscribe to, the name is the only thing a handler can filter on");

        Assert_False(_HeardTag.IsValid(),
            "the set was baked with no tag, and the payload reports that honestly rather than inventing one");

        auto PressFrame = DoFind_LatestPressFrame();

        Assert_True(PressFrame >= 0,
            "a retained row must carry the press edge for the frame comparison to mean anything");

        Assert_Equals_Int(_HeardFrame, PressFrame,
            "the payload's frame is the record frame the move completed on, which is what lets a handler tell a fresh completion from one it already acted on");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Signal_Move"),
            _HeardFrame,
            "the signal and the poll surface report the same frame - they are two views of one row, never two sources of truth");
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
        Res.Set(utils_intent_matcher::Get_HasActiveSet(_Matcher) &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey));
    }

    UFUNCTION()
    private void Check_Fired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Fires >= 1);
    }

    //------------------------------------------------------------------------

    // Parameter for parameter with FCk_Delegate_IntentMatcher_Completed. A dynamic delegate is matched by
    // SIGNATURE, so one type out of place here is a handler that is simply never called.
    UFUNCTION()
    private void OnIntentCompleted(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        int32 InFrame)
    {
        _Fires += 1;

        _HeardMatcher = InMatcher;
        _HeardName    = InIntentName;
        _HeardTag     = InIntentTag;
        _HeardFrame   = InFrame;
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
