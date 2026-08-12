// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE STATE IS THE BUTTON'S, NOT ONE KEY'S
//============================================================================
//
// A Mapped button carries every bound slot's key, so "is this button down?"
// is a question about the UNION of its keys. A level intent's state is
// exactly that question asked every frame — which makes the union the one
// place a naive implementation will get it wrong, by remembering the key the
// activating press arrived on and closing the state when that key comes up.
//
// So the player opens the state on the keyboard, puts a thumb on the second
// binding, and lifts the keyboard key. The button never came up. The state
// must not notice — and the activation frame must still be the ORIGINAL one,
// because a state that quietly closed and reopened would look identical to a
// surviving one on a phase poll alone. The frame is the discriminator.
//
// Both keys are keyboard keys (F8 and F12). The device class on an injected
// event is a LABEL the record carries, not a second identity — the held-union
// is key-space and device-agnostic. Injecting the second press as Gamepad
// exercises the injection path's device-class handling and nothing more; a
// reader should not infer that a real gamepad is involved, nor that the union
// is per-device.
//
// The four edges are each gated on the RECORD rather than on a hop count,
// because the whole test turns on their order: a release that had not landed
// yet would leave the state alive for the ordinary reason and the test would
// pass without exercising anything.
//
// CkTests_DualBound stays on its authored F8/F12 defaults for the whole test
// — no key binding is mutated, so there is nothing to reset on teardown.
//============================================================================

class UCk_AutoTest_Intent_LevelSurvivesPartialRelease : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FName _MappingName = n"CkTests_DualBound";
    private FKey  _PrimaryKey;
    private FKey  _SecondaryKey;

    private int32 _ActivationFrame = -1;

    private TArray<ECk_Intent_Phase> _FromPhases;
    private TArray<ECk_Intent_Phase> _ToPhases;
    private TArray<int32>            _Frames;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PrimaryKey   = EKeys::F8;
        _SecondaryKey = EKeys::F12;

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

        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(600);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnIntentPhaseChanged"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the dual-bound button derives with both keys",        n"Check_DualBoundDerived");
        Add_Step(          "bake the level intent on the dual-bound button",      n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers captures for BOTH keys",           n"Check_CapturesBothKeys");

        Add_Step(          "press the PRIMARY key — the state opens on it",       n"Step_PressPrimary");
        Add_Step_WaitUntil("the state opens",                                     n"Check_Active");
        Add_Step(          "record the activation frame",                         n"Step_RecordActivation");

        Add_Step(          "press the SECONDARY key while the primary is down",   n"Step_PressSecondary");
        Add_Step_WaitUntil("the secondary press reaches the record",              n"Check_SecondaryPressRecorded");

        Add_Step(          "release the PRIMARY key — the one it opened on",      n"Step_ReleasePrimary");
        Add_Step_WaitUntil("the primary release reaches the record",              n"Check_PrimaryReleaseRecorded");
        Add_Step(          "assert the state survived, unmoved",                  n"Step_AssertStillActive");

        Add_Step(          "release the SECONDARY key — the last one down",       n"Step_ReleaseSecondary");
        Add_Step_WaitUntil("the state closes",                                    n"Check_Idle");
        Add_Step(          "assert four edges produced exactly two transitions",  n"Step_AssertTransitions");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV level", n"AS_Level_Drag", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_MappedButton()));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Baked.Get_CompiledSet(), DoMake_MappedButton());

        Assert_Equals_Int(Verdict.Get_HoldSiblingFrames(), 0,
            "nothing shares this terminal and no hold is declared, so the state's timing owes nothing to a deferral");
        Assert_Equals_Int(Verdict.Get_ChordMemberFrames(), 0,
            "a single-button terminal completes no chord, so no partner press can be in flight");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressPrimary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_PrimaryKey, ECk_InputSource_DeviceClass::Keyboard, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordActivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ActivationFrame = utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Drag");

        Assert_True(_ActivationFrame >= 0,
            "an open state must name the frame it opened on, or the survival assertion has nothing to compare against");
    }

    UFUNCTION()
    private void Step_PressSecondary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_SecondaryKey, ECk_InputSource_DeviceClass::Gamepad, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_ReleasePrimary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_PrimaryKey, ECk_InputSource_DeviceClass::Keyboard, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertStillActive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Drag") ==
                    ECk_Intent_Phase::Active,
            "the key the state opened on came up while a co-bound key stayed down — the BUTTON never came up, so the state must still be on");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Drag"),
            _ActivationFrame,
            "the same state, not a new one: a close-and-reopen would read as Active too, and only the frame tells them apart");
    }

    UFUNCTION()
    private void Step_ReleaseSecondary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_SecondaryKey, ECk_InputSource_DeviceClass::Gamepad, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertTransitions(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_FromPhases.Num(), 2,
            "four key edges, one state: any extra transition here is the union being read per-key instead of per-button");

        if (_FromPhases.Num() != 2)
        { return; }

        Assert_True(_FromPhases[0] == ECk_Intent_Phase::Idle && _ToPhases[0] == ECk_Intent_Phase::Active,
            "the first press opened the state");

        Assert_True(_FromPhases[1] == ECk_Intent_Phase::Active && _ToPhases[1] == ECk_Intent_Phase::Idle,
            "the LAST release closed it, and nothing in between did");

        Assert_Equals_Int(_Frames[0], _ActivationFrame,
            "the broadcast open and the polled open are one reading, held all the way across the partial release");
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
        Res.Set(Keys.Contains(_PrimaryKey) && Keys.Contains(_SecondaryKey));
    }

    UFUNCTION()
    private void Check_Active(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Drag") ==
                ECk_Intent_Phase::Active);
    }

    UFUNCTION()
    private void Check_Idle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Drag") ==
                ECk_Intent_Phase::Idle);
    }

    UFUNCTION()
    private void Check_SecondaryPressRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_SecondaryKey, ECk_InputSource_EventType::Pressed));
    }

    UFUNCTION()
    private void Check_PrimaryReleaseRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_PrimaryKey, ECk_InputSource_EventType::Released));
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

        if (InIntentName != n"AS_Level_Drag")
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

    private FCk_Input_ButtonId DoMake_MappedButton()
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Mapped, _MappingName);
    }

    private void DoInject(FKey InKey, ECk_InputSource_DeviceClass InDeviceClass, ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            InDeviceClass,
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
