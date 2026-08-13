// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A WHEEL NOTCH IS A COLLAPSED PRESS/RELEASE PAIR
//============================================================================
//
// A mouse-wheel notch has no duration. The Slate writer therefore records it
// as a Pressed AND a Released inside one call, and both land in the same
// sampler row. This pins the two properties every consumer of a wheel terminal
// depends on, neither of which any other test covers:
//
//   1. A collapsed pair still COMPLETES. Activation is evaluated before the
//      release, so a notch is seen to have happened rather than never entered.
//   2. The notch key is NOT held afterwards, so the NEXT notch is a real press
//      edge and completes again.
//
// (2) is the load-bearing half and the one that fails loudly if the writer
// ever emits a press without its release: the second scroll would then be a
// press on a button already down, produce no edge, and silently do nothing —
// while every readiness gate (button minted, capture registered, set active)
// still reported healthy. Scroll-to-cycle is the canonical consumer, and it is
// used by repeating the notch, never by holding it.
//
// Physical tier deliberately: the shape under test is the event pair, which is
// identical whichever tier minted the button, and Physical needs no mapping
// context to exist first.
//============================================================================

class UCk_AutoTest_Intent_WheelNotchRepeatsWithoutAnIntermediateRelease : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _NotchKey;

    private int32 _FirstCompletionFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _NotchKey = EKeys::MouseScrollUp;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_NotchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        // The first completion's frame is held across several step-hops and compared against a later
        // one, so the decay window must not expire underneath the comparison.
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(200);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the notch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move on the notch terminal",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the notch capture",                n"Check_SetActive");

        Add_Step(          "turn the wheel one notch (press + release together)", n"Step_Notch");
        Add_Step_WaitUntil("the move completes",                                  n"Check_Completed");
        Add_Step(          "record the frame and assert nothing stayed held",     n"Step_RecordAndAssertNotHeld");

        Add_Step(          "turn the wheel a second notch",                       n"Step_Notch");
        Add_Step_WaitUntil("the move completes again, on a later frame",          n"Check_CompletedLater");
        Add_Step(          "assert the second notch produced its own completion", n"Step_AssertSecondNotch");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("WN", n"AS_Notch_Cycle", 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"WN", DoMake_PhysicalButton(_NotchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    // Both edges in one step, which is what puts them in one sampler row — the shape the Slate
    // writer produces for a notch, and the whole point of the test.
    UFUNCTION()
    private void Step_Notch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_RecordAndAssertNotHeld(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstCompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Notch_Cycle");

        Assert_True(_FirstCompletionFrame >= 0,
            "a notch whose press and release collapse onto one row still completes — activation is evaluated ahead of the release");

        Assert_False(DoContainsPhysical(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held(), _NotchKey.GetKeyName()),
            "the notch left nothing held — a press recorded without its release would wedge the key down for the rest of the session");
    }

    UFUNCTION()
    private void Step_AssertSecondNotch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto SecondFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Notch_Cycle");

        Assert_True(SecondFrame > _FirstCompletionFrame,
            "the second notch is a fresh press EDGE and completes on its own frame — scroll-to-cycle is used by repeating the notch, never by holding it");
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

    UFUNCTION()
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Notch_Cycle") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_CompletedLater(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Notch_Cycle") >
                _FirstCompletionFrame);
    }

    //------------------------------------------------------------------------

    private void DoInject(ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Mouse,
            _NotchKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

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

    private bool DoContainsPhysical(const TArray<FCk_Input_ButtonId>& InButtons, FName InName)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == InName)
            { return true; }
        }

        return false;
    }
}
