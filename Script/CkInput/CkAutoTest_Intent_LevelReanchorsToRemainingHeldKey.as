// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE ANCHOR FOLLOWS THE HAND
//============================================================================
//
// A level state remembers ONE key — the anchor — because delivery is a
// per-key question and a modal masking the gamepad must not release a hold the
// player is doing on the keyboard. CkAutoTest_Intent_LevelSurvivesPartialRelease
// already proves the state outlives the anchor key coming up while a co-bound
// key stays down. This test asks the question that leaves behind: after that
// release, WHICH key is the state riding on now?
//
// The answer is the one still under a finger. The anchor RE-ANCHORS to another
// bound key that is both held and deliverable, and the released one stops
// being able to speak for the state at all:
//
//   press A, press B, release A   -> Active, on B now
//   mask A (released, not held)   -> still Active   <- the re-anchor
//   unmask A, mask B (held)       -> Idle           <- and B really is it
//
// Both legs are load-bearing and they fail in opposite directions. An
// implementation that never moves the anchor closes the state on the first
// mask, because the key it is watching stopped being deliverable — for a key
// the player let go of a second ago, which no modal in the world was trying to
// take away from them. An implementation that moved the anchor but kept
// answering for the old one would survive the second mask too, and the state
// would outlive every key the layer can still hear.
//
// The middle "still Active" is a settle, not a condition — it is already true
// on arrival. What makes the silence mean something is the deactivation on the
// far side of it, proving masks are being read at all.
//
// CkTests_DualBound stays on its authored F8/F12 defaults — no key binding is
// mutated, so there is nothing to reset on teardown. The masker's captures live
// on a layer this test owns and dies with.
//============================================================================

class UCk_AutoTest_Intent_LevelReanchorsToRemainingHeldKey : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_InputLayer     _Masker;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FName _MappingName = n"CkTests_DualBound";
    private FKey  _OpeningKey;
    private FKey  _RemainingKey;

    private int32 _ActivationFrame = -1;

    private TArray<ECk_Intent_Phase> _FromPhases;
    private TArray<ECk_Intent_Phase> _ToPhases;
    private TArray<int32>            _Frames;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _OpeningKey   = EKeys::F8;
        _RemainingKey = EKeys::F12;

        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController — the mapped tier derives from the local player's profile");
            return;
        }

        auto UserSettings = utils_key_binding::Get_InputUserSettings(PlayerController);
        if (ck::Is_NOT_Valid(UserSettings))
        {
            FinishFailure("Enhanced Input user settings unavailable on the local player");
            return;
        }

        UserSettings.RegisterInputMappingContext(input_assets::IMC_CkTests_KeyBinding);

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData());
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

        Add_Step_WaitUntil("the dual-bound button derives with both keys",       n"Check_DualBoundDerived");
        Add_Step(          "bake the level intent on the dual-bound button",     n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers captures for BOTH keys",          n"Check_CapturesBothKeys");

        Add_Step(          "open the state on the FIRST key",                    n"Step_PressOpening");
        Add_Step_WaitUntil("the state opens",                                    n"Check_Active");
        Add_Step(          "record the activation frame",                        n"Step_RecordActivation");

        Add_Step(          "put a second finger on the OTHER bound key",         n"Step_PressRemaining");
        Add_Step_WaitUntil("that press reaches the record",                      n"Check_RemainingPressRecorded");

        Add_Step(          "lift the key the state opened on",                   n"Step_ReleaseOpening");
        Add_Step_WaitUntil("that release reaches the record",                    n"Check_OpeningReleaseRecorded");
        Add_Step(          "assert the union kept it open and unmoved",          n"Step_AssertSurvivedPartialRelease");

        Add_Step(          "mask the key the player already LET GO of",          n"Step_MaskOpening");
        Add_Step_WaitUntil("that capture is in force",                           n"Check_OpeningMasked");
        Add_Step_WaitFrames("give a wrong-key close a real window to happen in",  30);
        Add_Step(          "assert the state re-anchored to the held key",       n"Step_AssertStillActive");

        Add_Step(          "lift that mask again",                               n"Step_UnmaskOpening");
        Add_Step_WaitUntil("the capture is really gone",                          n"Check_OpeningUnmasked");
        Add_Step(          "now mask the key that IS being held",                n"Step_MaskRemaining");
        Add_Step_WaitUntil("that capture is in force",                           n"Check_RemainingMasked");
        Add_Step_WaitUntil("the state closes",                                    n"Check_Idle");
        Add_Step(          "assert one open and one close, and nothing else",    n"Step_AssertTransitions");
        Add_Step(          "let go",                                              n"Step_ReleaseRemaining");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV level", n"AS_Level_Reanchor", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_MappedButton()));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressOpening(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_OpeningKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordActivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ActivationFrame = utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Reanchor");

        Assert_True(_ActivationFrame >= 0,
            "an open state must name the frame it opened on, or 'the same state throughout' has nothing to compare against");
    }

    UFUNCTION()
    private void Step_PressRemaining(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_RemainingKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_ReleaseOpening(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_OpeningKey, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertSurvivedPartialRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssert_SameStateStillOpen(
            "the button never came up — one of its keys is still down, so the state must still be on");
    }

    UFUNCTION()
    private void Step_MaskOpening(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAddConsumeCapture(_OpeningKey);
    }

    UFUNCTION()
    private void Step_AssertStillActive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAssert_SameStateStillOpen(
            "the masked key is one the player LET GO of — the state re-anchored to the key still under a finger, and a state watching the original key would close here over input nobody was using");
    }

    UFUNCTION()
    private void Step_UnmaskOpening(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_input_layer::Request_RemoveCapture(_Masker, FCk_Request_InputLayer_RemoveCapture(
            ECk_InputLayer_CaptureMatch::Key, _OpeningKey));
    }

    UFUNCTION()
    private void Step_MaskRemaining(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAddConsumeCapture(_RemainingKey);
    }

    UFUNCTION()
    private void Step_AssertTransitions(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FromPhases.Num(), 2,
            "one open, one close: a re-anchor is a change of bookkeeping, not of state, so it must broadcast nothing");

        if (_FromPhases.Num() != 2)
        { return; }

        Assert_True(_FromPhases[0] == ECk_Intent_Phase::Idle && _ToPhases[0] == ECk_Intent_Phase::Active,
            "the first press opened the state");

        Assert_True(_FromPhases[1] == ECk_Intent_Phase::Active && _ToPhases[1] == ECk_Intent_Phase::Idle,
            "and the mask over the key actually being held is what closed it");

        Assert_Equals_Int(_Frames[0], _ActivationFrame,
            "the broadcast open and the polled open are one reading, held all the way across the re-anchor");
    }

    UFUNCTION()
    private void Step_ReleaseRemaining(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_RemainingKey, ECk_InputSource_EventType::Released);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_DualBoundDerived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_KeysForButton(_Map, DoMake_MappedButton()).Num() == 2 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_CapturesBothKeys(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Keys = utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher);
        Res.Set(Keys.Contains(_OpeningKey) && Keys.Contains(_RemainingKey));
    }

    UFUNCTION()
    private void Check_Active(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Reanchor") ==
                ECk_Intent_Phase::Active);
    }

    UFUNCTION()
    private void Check_Idle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Reanchor") ==
                ECk_Intent_Phase::Idle);
    }

    // Every key edge is gated on the RECORD rather than on a hop count, because the whole test turns
    // on their order: a release that had not landed yet would leave the first mask hitting a key the
    // state was legitimately still anchored on, and the test would pass proving nothing.
    UFUNCTION()
    private void Check_RemainingPressRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_RemainingKey, ECk_InputSource_EventType::Pressed));
    }

    UFUNCTION()
    private void Check_OpeningReleaseRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_OpeningKey, ECk_InputSource_EventType::Released));
    }

    // Capture edits are DEFERRED, so every mask leg waits on the layer's own answer — asserting one
    // hop after the request would be asserting against an edit that has not landed.
    UFUNCTION()
    private void Check_OpeningMasked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _OpeningKey));
    }

    UFUNCTION()
    private void Check_OpeningUnmasked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _OpeningKey) == false);
    }

    UFUNCTION()
    private void Check_RemainingMasked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _RemainingKey));
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

        if (InIntentName != n"AS_Level_Reanchor")
        { return; }

        _FromPhases.Add(InPreviousPhase);
        _ToPhases.Add(InNewPhase);
        _Frames.Add(InFrame);
    }

    //------------------------------------------------------------------------

    // Both survival legs assert the same two things, and the second one is the one that matters: a
    // state that closed and reopened would read as Active too, and only the activation frame can
    // tell a survivor from a replacement.
    private void DoAssert_SameStateStillOpen(const FString& InWhy)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Reanchor") ==
                    ECk_Intent_Phase::Active,
            InWhy);

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Reanchor"),
            _ActivationFrame,
            "and it is the SAME state throughout — a re-anchor moves which key answers for the state, never when it started");
    }

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        return Result.Get_Definition();
    }

    private FCk_Input_ButtonId DoMake_MappedButton()
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, _MappingName);
    }

    private void DoAddConsumeCapture(FKey InKey)
    {
        utils_input_layer::Request_AddCapture(_Masker, FCk_Request_InputLayer_AddCapture(
            utils_input_layer::Make_KeyCapture(InKey, ECk_InputLayer_CaptureBehavior::Consume)));
    }

    private void DoInject(FKey InKey, ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            InKey,
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
}
