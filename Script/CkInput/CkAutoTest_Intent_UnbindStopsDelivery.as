// Language=angelscript

//============================================================================
// CK INTENT / CK INPUT — AUTOMATION TEST: AN UNBOUND HANDLER STOPS HEARING
//============================================================================
//
// Every BindTo_* in this stack has an UnbindFrom_* beside it, and until now
// nothing exercised one. That asymmetry is the dangerous kind: a bind that
// silently fails is loud — the handler never runs and the test that wanted it
// times out — while an UNBIND that silently fails is invisible. The handler
// keeps being called, and the only symptom is a consumer acting on input long
// after it stopped caring, which surfaces as a lifetime bug in whatever object
// owned the delegate rather than as an input bug.
//
// Three unbinds are proven here — the layer's OnCaptureTriggered and the
// matcher's OnIntentPhaseChanged and OnIntentCompleted — on ONE fixture,
// because the matcher's swap registers its terminal capture on the layer it
// composed onto: a single press drives all three signals off the same routed
// event, so nothing about the three legs can disagree about timing.
//
// THE SHAPE, and why the silence is not vacuous. Each signal carries TWO
// handlers: one under test and one control, bound the same way on the same
// entity. The press proves both fired — that positive is what proves the
// binding path, the delegate signature and the broadcast all work, so a later
// silence means something. The unbind then removes ONLY the handler under
// test, and a second press follows. The control hearing the second round is
// what makes the silence a statement about the unbind rather than about a
// signal that stopped firing; the poll surface reporting a genuinely later
// completion frame says the same thing a second way, off a surface the signals
// cannot influence.
//
// Two details the design leans on:
//   - The release is injected before the re-press so the second press is a real
//     press EDGE rather than a button that never came up.
//   - The decay window is long, so the re-press lands while the first
//     completion is still latched: a re-completion on a later frame is a real
//     event that both signals owe an account of, and choosing it over a decayed
//     row keeps the second round driven by the press rather than by a timer.
//
// The final assertion compares against counts SNAPSHOTTED at unbind time
// rather than against 1: a consumed press is followed by its release to the
// same layer, so the capture signal legitimately fires more than once per
// round and an exact-count assertion would be pinning routing, not unbinding.
//============================================================================

class UCk_AutoTest_Intent_UnbindStopsDelivery : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _PunchKey;

    // Two seconds of standing latch. The re-press has to land while the first completion is still latched, so the
    // second round is driven by the press rather than by the decay that would otherwise arrive first.
    private int32 _LatchDecayFrames = 120;

    private int32 _FirstCompletionFrame = -1;

    private int32 _CaptureFires_UnderTest   = 0;
    private int32 _CaptureFires_Control     = 0;
    private int32 _PhaseFires_UnderTest     = 0;
    private int32 _PhaseFires_Control       = 0;
    private int32 _CompletedFires_UnderTest = 0;
    private int32 _CompletedFires_Control   = 0;

    private int32 _CaptureUnderTest_AtUnbind   = -1;
    private int32 _CaptureControl_AtUnbind     = -1;
    private int32 _PhaseUnderTest_AtUnbind     = -1;
    private int32 _PhaseControl_AtUnbind       = -1;
    private int32 _CompletedUnderTest_AtUnbind = -1;
    private int32 _CompletedControl_AtUnbind   = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::F6;

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

        Assert_True(ck::IsValid(_Layer),   "the layer must be created for its capture signal to have somewhere to live");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        // IgnorePayloadInFlight because every bind here precedes every press: a replay policy would let a handler
        // report a fire it did not receive from the broadcast under test.
        utils_input_layer::BindTo_OnCaptureTriggered(_Layer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnCaptured_UnderTest"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_input_layer::BindTo_OnCaptureTriggered(_Layer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnCaptured_Control"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnPhaseChanged_UnderTest"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnPhaseChanged_Control"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_intent_matcher::BindTo_OnIntentCompleted(_Matcher,
            FCk_Delegate_IntentMatcher_Completed(this, n"OnCompleted_UnderTest"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_intent_matcher::BindTo_OnIntentCompleted(_Matcher,
            FCk_Delegate_IntentMatcher_Completed(this, n"OnCompleted_Control"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the punch key and the sampler records",   n"Check_Recording");
        Add_Step(          "bake a bare move and activate it",                      n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture on the layer", n"Check_SetActive");

        Add_Step(          "press the punch",                                       n"Step_Press");
        Add_Step_WaitUntil("all three signals reach both of their handlers",        n"Check_AllHeard");
        Add_Step(          "unbind the three handlers under test, then release",    n"Step_Unbind");

        Add_Step(          "press the punch again",                                 n"Step_Press");
        Add_Step_WaitUntil("the still-bound controls hear the second round",        n"Check_ControlsHeardAgain");
        // MUST stay a settle. What follows is the NEGATIVE — three counters that must not have moved — and it is
        // already true the instant the wait above resolves. There is no condition left to wait for; the window
        // exists to give a delivery to an unbound handler a chance to arrive and be caught.
        Add_Step_WaitFrames("give a fire on an unbound handler a chance to arrive",  10);
        Add_Step(          "assert the unbound handlers heard nothing more",        n"Step_AssertSilence");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_Unbind_Move", 100));

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
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_Unbind(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_CaptureFires_UnderTest >= 1,
            "the capture handler under test received the press, which is what makes its later silence a statement about the unbind");
        Assert_True(_PhaseFires_UnderTest >= 1,
            "the phase handler under test received the transition, so its delegate signature and binding path are known good");
        Assert_True(_CompletedFires_UnderTest >= 1,
            "the completion handler under test received the completion, so its delegate signature and binding path are known good");

        _FirstCompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Unbind_Move");

        Assert_True(_FirstCompletionFrame >= 0,
            "the first completion must carry a real frame for the second to be shown to be a different one");

        _CaptureUnderTest_AtUnbind   = _CaptureFires_UnderTest;
        _CaptureControl_AtUnbind     = _CaptureFires_Control;
        _PhaseUnderTest_AtUnbind     = _PhaseFires_UnderTest;
        _PhaseControl_AtUnbind       = _PhaseFires_Control;
        _CompletedUnderTest_AtUnbind = _CompletedFires_UnderTest;
        _CompletedControl_AtUnbind   = _CompletedFires_Control;

        utils_input_layer::UnbindFrom_OnCaptureTriggered(_Layer,
            FCk_Delegate_InputLayer_CaptureTriggered(this, n"OnCaptured_UnderTest"));

        utils_intent_matcher::UnbindFrom_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnPhaseChanged_UnderTest"));

        utils_intent_matcher::UnbindFrom_OnIntentCompleted(_Matcher,
            FCk_Delegate_IntentMatcher_Completed(this, n"OnCompleted_UnderTest"));

        // Released now so the second press is a real press EDGE rather than a button that never came up.
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertSilence(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_CaptureFires_Control > _CaptureControl_AtUnbind,
            "the layer went on delivering to the handler that stayed bound — unbinding one handler must not silence the signal");
        Assert_True(_PhaseFires_Control > _PhaseControl_AtUnbind,
            "the matcher went on broadcasting phase transitions to the handler that stayed bound");
        Assert_True(_CompletedFires_Control > _CompletedControl_AtUnbind,
            "the matcher went on broadcasting completions to the handler that stayed bound");

        Assert_Equals_Int(_CaptureFires_UnderTest, _CaptureUnderTest_AtUnbind,
            "an unbound capture handler receives nothing further, including the release delivered straight to the press owner");
        Assert_Equals_Int(_PhaseFires_UnderTest, _PhaseUnderTest_AtUnbind,
            "an unbound phase handler receives nothing further, though the transition it would have named really happened");
        Assert_Equals_Int(_CompletedFires_UnderTest, _CompletedUnderTest_AtUnbind,
            "an unbound completion handler receives nothing further, though the completion it would have named really happened");

        Assert_True(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Unbind_Move") >
                    _FirstCompletionFrame,
            "and the poll surface — which no unbind can reach — agrees a second completion landed on a later frame, so the silence above is about delivery and nothing else");
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
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey) &&
                utils_input_layer::Get_HasCaptureForKey(_Layer, ECk_InputLayer_CaptureMatch::Key, _PunchKey));
    }

    UFUNCTION()
    private void Check_AllHeard(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CaptureFires_UnderTest   >= 1 && _CaptureFires_Control   >= 1 &&
                _PhaseFires_UnderTest     >= 1 && _PhaseFires_Control     >= 1 &&
                _CompletedFires_UnderTest >= 1 && _CompletedFires_Control >= 1);
    }

    UFUNCTION()
    private void Check_ControlsHeardAgain(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CaptureFires_Control   > _CaptureControl_AtUnbind   &&
                _PhaseFires_Control     > _PhaseControl_AtUnbind     &&
                _CompletedFires_Control > _CompletedControl_AtUnbind &&
                utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Unbind_Move") >
                    _FirstCompletionFrame);
    }

    //------------------------------------------------------------------------
    // Handlers — parameter for parameter with their delegates. A dynamic delegate is matched by SIGNATURE, so one
    // type out of place is a handler that is never called, which would make every silence below meaningless.
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnCaptured_UnderTest(
        FCk_Handle_InputLayer InLayer,
        FCk_InputSource_RawEvent InEvent,
        FCk_InputLayer_Capture InCapture)
    {
        _CaptureFires_UnderTest += 1;
    }

    UFUNCTION()
    private void OnCaptured_Control(
        FCk_Handle_InputLayer InLayer,
        FCk_InputSource_RawEvent InEvent,
        FCk_InputLayer_Capture InCapture)
    {
        _CaptureFires_Control += 1;
    }

    UFUNCTION()
    private void OnPhaseChanged_UnderTest(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        ECk_Intent_Phase InPreviousPhase,
        ECk_Intent_Phase InNewPhase,
        int32 InFrame)
    {
        if (InIntentName != n"AS_Unbind_Move")
        { return; }

        _PhaseFires_UnderTest += 1;
    }

    UFUNCTION()
    private void OnPhaseChanged_Control(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        ECk_Intent_Phase InPreviousPhase,
        ECk_Intent_Phase InNewPhase,
        int32 InFrame)
    {
        if (InIntentName != n"AS_Unbind_Move")
        { return; }

        _PhaseFires_Control += 1;
    }

    UFUNCTION()
    private void OnCompleted_UnderTest(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        int32 InFrame)
    {
        if (InIntentName != n"AS_Unbind_Move")
        { return; }

        _CompletedFires_UnderTest += 1;
    }

    UFUNCTION()
    private void OnCompleted_Control(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        int32 InFrame)
    {
        if (InIntentName != n"AS_Unbind_Move")
        { return; }

        _CompletedFires_Control += 1;
    }

    //------------------------------------------------------------------------

    private void DoInject(ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
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
}
