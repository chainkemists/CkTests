// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: EITHER BOUND KEY COMPLETES A DUAL-BOUND TERMINAL
//============================================================================
//
// A terminal naming a Mapped button used to be completable from exactly one
// key - the button's only association. Now a Mapped button can carry several,
// and the matcher's swap registers a capture for EVERY one of them, so the
// terminal must be completable from ANY of its bound slots.
//
// CkTests_DualBound is bound in two slots (F8 primary, F12 secondary - see
// CkInput_Assets.as). This presses the NON-primary key first, on the theory
// that an implementation which only wired up the primary/scalar association
// would fail exactly there while still passing on the primary key; the
// primary is pressed second, on a later frame, to prove the SAME terminal
// answers to both rather than one replacing the other.
//
// No key binding is mutated - CkTests_DualBound stays on its authored F8/F12
// defaults for the whole test - so there is nothing to reset on teardown.
//============================================================================

class UCk_AutoTest_Intent_EitherKeyCompletesDualBoundTerminal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FName _MappingName = n"CkTests_DualBound";
    private FKey  _PrimaryKey;
    private FKey  _SecondaryKey;

    private int32 _FirstCompletionFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PrimaryKey   = EKeys::F8;
        _SecondaryKey = EKeys::F12;

        auto PlayerController = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(PlayerController))
        {
            FinishFailure("no local PlayerController - the mapped tier derives from the local player's profile");
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
        // This test holds the first completion's frame across several step-hops and asserts a LATER
        // completion against it, so it must not be coupled to the decay window it is not about.
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(200);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the dual-bound button derives with both keys", n"Check_DualBoundDerived");
        Add_Step(          "bake a set naming the dual-bound button and activate it", n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers captures for BOTH keys",    n"Check_CapturesBothKeys");

        Add_Step(          "press the SECONDARY key",                     n"Step_PressSecondary");
        Add_Step_WaitUntil("the move completes",                          n"Check_Completed");
        Add_Step(          "record the frame, then release the secondary key", n"Step_RecordThenReleaseSecondary");

        Add_Step(          "press the PRIMARY key",                       n"Step_PressPrimary");
        Add_Step_WaitUntil("the move completes again",                    n"Check_CompletedLater");
        Add_Step(          "assert the primary key drove a later completion, then release", n"Step_AssertPrimaryCompleted");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("CkTests_DualBound", n"AS_DualBound_Fire", 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(_MappingName, DoMake_MappedButton()));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressSecondary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_SecondaryKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordThenReleaseSecondary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstCompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_DualBound_Fire");

        Assert_True(_FirstCompletionFrame >= 0,
            "the SECONDARY key alone must complete the terminal, or a two-key implementation collapsed to primary-only");

        DoInject(_SecondaryKey, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_PressPrimary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_PrimaryKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertPrimaryCompleted(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto CompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_DualBound_Fire");

        Assert_True(CompletionFrame > _FirstCompletionFrame,
            "the PRIMARY key completes the SAME terminal on a later frame - both slots drive it, neither replaces the other");

        DoInject(_PrimaryKey, ECk_InputSource_EventType::Released);
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
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_DualBound_Fire") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_CompletedLater(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_DualBound_Fire") >
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
