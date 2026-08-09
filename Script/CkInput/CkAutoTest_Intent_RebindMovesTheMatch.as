// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A REBIND MOVES THE MOVE, WITH NO EDIT
//============================================================================
//
// The payoff of the whole button-space design, asserted end to end and
// headless. A move names a BUTTON; the player rebinds that button in a
// settings screen; the move keeps working on the new key and stops working
// on the old one — and not one character of the notation, the definition or
// the compiled set changed.
//
// Three legs, and the second is the one an implementation that only ADDS
// captures would fail:
//
//   default key  -> the move completes
//   old key      -> after the rebind, a press of it completes NOTHING NEW
//   new key      -> completes, on a later frame than the first completion
//
// The old-key leg is checked against the FIRST completion's frame rather
// than against Idle, because completion is latched: the question is not "has
// this move ever completed" but "did this press complete it", and the frame
// index is the only thing that can tell those apart.
//
// CkTests_Flashlight is used because no other test in this battery remaps it,
// and F3 because nothing in the project is authored to it — so the remap
// cannot be a disguised conflict resolution.
//
// TEARDOWN IS UNCONDITIONAL within its step: all autotests share one PIE
// session and profile rows outlive the test that touched them.
//============================================================================

class UCk_AutoTest_Intent_RebindMovesTheMatch : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FName _MappingName = n"CkTests_Flashlight";
    private FKey  _DefaultKey;
    private FKey  _ReboundKey;

    private int32 _FirstCompletionFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _DefaultKey = EKeys::F;
        _ReboundKey = EKeys::F3;

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
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        // This test holds a completion latch across several waits and asserts it is UNCHANGED, so it must
        // not be coupled to the decay window it is not about. Ten seconds outlasts any step cadence.
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(600);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the first derivation binds the mapping to its default key", n"Check_BoundToDefault");
        Add_Step(          "bake a set naming the MAPPED button and activate it",       n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers a capture for the default key",          n"Check_CaptureOnDefault");

        Add_Step(          "press the default key",                                     n"Step_PressDefault");
        Add_Step_WaitUntil("the move completes",                                        n"Check_Completed");
        Add_Step(          "record the frame, release, then rebind the mapping",        n"Step_RecordThenRebind");
        Add_Step_WaitUntil("the capture follows the association onto the new key",      n"Check_CaptureMoved");

        Add_Step(          "press the OLD key",                                         n"Step_PressDefault");
        Add_Step_WaitFrames("give a stale match a chance to land late",                 8);
        Add_Step(          "assert nothing new completed, then release",                n"Step_AssertOldKeyInert");

        Add_Step(          "press the NEW key",                                         n"Step_PressRebound");
        Add_Step_WaitUntil("the move completes again",                                  n"Check_CompletedLater");
        Add_Step(          "assert the new key drove it, then restore the profile",     n"Step_AssertNewKeyMatches");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("CkTests_Flashlight", n"AS_Rebind_Fire", 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(_MappingName, DoMake_MappedButton()));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressDefault(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_DefaultKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_PressRebound(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_ReboundKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordThenRebind(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstCompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Rebind_Fire");

        Assert_True(_FirstCompletionFrame >= 0,
            "the move must complete on its authored key before a rebind can be shown to move it");

        DoInject(_DefaultKey, ECk_InputSource_EventType::Released);

        auto PlayerController = Gameplay::GetPlayerController(0);
        auto FailureReason = FGameplayTagContainer();

        auto Remapped = utils_key_binding::RemapKey(
            PlayerController, _MappingName, EPlayerMappableKeySlot::First, _ReboundKey, FailureReason);

        Assert_True(Remapped, "RemapKey reports success rebinding the mapping onto the unused key F3");

        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive());
    }

    UFUNCTION()
    private void Step_AssertOldKeyInert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Rebind_Fire"),
            _FirstCompletionFrame,
            "the key the button left produces no button at all, so a press of it completes nothing new");

        DoInject(_DefaultKey, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertNewKeyMatches(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto CompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Rebind_Fire");

        Assert_True(CompletionFrame > _FirstCompletionFrame,
            "the rebound key completes the same move on a later frame, with no edit to the definition or the set");

        DoInject(_ReboundKey, ECk_InputSource_EventType::Released);

        auto PlayerController = Gameplay::GetPlayerController(0);
        utils_key_binding::ResetMappingToDefault(PlayerController, _MappingName);
        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive());
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_BoundToDefault(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::TryGet_KeyForButton(_Map, DoMake_MappedButton()) == _DefaultKey &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_CaptureOnDefault(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_DefaultKey));
    }

    UFUNCTION()
    private void Check_CaptureMoved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Keys = utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher);

        Res.Set(Keys.Contains(_ReboundKey) && !Keys.Contains(_DefaultKey));
    }

    UFUNCTION()
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Rebind_Fire") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_CompletedLater(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Rebind_Fire") >
                _FirstCompletionFrame);
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

    private void DoInject(FKey InKey, ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            InKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }
}
