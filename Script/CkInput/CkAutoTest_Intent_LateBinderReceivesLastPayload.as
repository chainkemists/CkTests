// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: BINDING LATE, AND WHAT THAT COSTS
//============================================================================
//
// A consumer that spawns a few frames after the input that concerns it is
// ordinary — an ability actor created in response to a move, a widget opened
// on the same press. The binding policy is what decides whether it hears
// about a completion that already happened, and this test pins BOTH sides of
// that choice against the same standing completion:
//
//   FireIfPayloadInFlight          -> fires, with the original payload
//   FireIfPayloadInFlightThisFrame -> silent, because the payload is old
//
// The second is the API default, deliberately: it is the only policy that
// cannot make the signal contradict the poll, since a latch cannot decay
// inside the frame it was stamped on. Replay across frames is opt-in, and the
// caveat is the reason it is opt-in — the payload a late binder receives is
// the LAST one, with no history behind it, and it may name a completion the
// poll surface has already decayed away. This test keeps the decay window
// long so the completion is genuinely still standing when the binders arrive,
// which is the only situation where the replay is safe to act on.
//
// Both binders arrive on the same frame, several frames after the press, so
// the difference between them cannot be timing — it is the policy alone.
//============================================================================

class UCk_AutoTest_Intent_LateBinderReceivesLastPayload : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _PunchKey;

    // Two seconds of standing latch. The point of the test is a binder arriving while the completion is still
    // real, so the window has to outlast the harness's own step cadence by a wide margin.
    private int32 _LatchDecayFrames = 120;

    private int32 _CompletionFrame = -1;

    private int32  _ReplayFires = 0;
    private FName  _ReplayName;
    private int32  _ReplayFrame = -1;

    private int32 _ThisFrameOnlyFires = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::S;

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

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move and activate it",                    n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press the punch with nobody listening",               n"Step_Press");
        Add_Step_WaitUntil("the move completes",                                   n"Check_Completed");
        Add_Step(          "record the completion frame",                          n"Step_RecordCompletion");
        Add_Step_WaitFrames("let several frames pass so the binders are truly late", 6);
        Add_Step(          "bind two handlers under different policies",           n"Step_BindLate");
        Add_Step_WaitUntil("the replaying binder is served",                       n"Check_ReplayFired");
        Add_Step_WaitFrames("give the same-frame-only binder a chance to fire",     6);
        Add_Step(          "assert the policy alone decided who heard it",         n"Step_AssertPolicies");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_LateBind_Move", 100));

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
    private void Step_RecordCompletion(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_LateBind_Move");

        Assert_True(_CompletionFrame >= 0,
            "the completion must carry a real frame for the replayed payload to be checked against it");

        Assert_Equals_Int(_ReplayFires, 0,
            "nothing was bound when the move landed, so nothing can have fired yet");
    }

    UFUNCTION()
    private void Step_BindLate(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_LateBind_Move") ==
                    ECk_Intent_Phase::Completed,
            "the completion is still standing, which is the only state in which acting on a replay is honest");

        utils_intent_matcher::BindTo_OnIntentCompleted(_Matcher,
            FCk_Delegate_IntentMatcher_Completed(this, n"OnReplayCompleted"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_intent_matcher::BindTo_OnIntentCompleted(_Matcher,
            FCk_Delegate_IntentMatcher_Completed(this, n"OnThisFrameOnlyCompleted"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
    }

    UFUNCTION()
    private void Step_AssertPolicies(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_ReplayFires, 1,
            "a binder that asked for the last payload from any frame receives it exactly once");

        Assert_True(_ReplayName == n"AS_LateBind_Move",
            "the replayed payload is the real one, identity and all — not a synthesised notification");

        Assert_Equals_Int(_ReplayFrame, _CompletionFrame,
            "and it still names the frame the move actually landed on, which is what a late consumer needs to decide whether it is too late to act");

        Assert_Equals_Int(_ThisFrameOnlyFires, 0,
            "the default policy replays only within the frame, so a binder arriving later hears nothing — that is what makes it the policy that can never contradict the poll surface");
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
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_LateBind_Move") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_ReplayFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ReplayFires >= 1);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnReplayCompleted(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        int32 InFrame)
    {
        _ReplayFires += 1;
        _ReplayName   = InIntentName;
        _ReplayFrame  = InFrame;
    }

    UFUNCTION()
    private void OnThisFrameOnlyCompleted(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        int32 InFrame)
    {
        _ThisFrameOnlyFires += 1;
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
}
