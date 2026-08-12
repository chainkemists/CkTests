// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE MASK HAS TO HIT THE KEY IT OPENED ON
//============================================================================
//
// Losing delivery closes a level state — but "delivery" is about the key the
// state is actually riding on, and a Mapped button has more than one. The
// state remembers the ANCHOR: the key the activating press arrived on. A mask
// over any OTHER bound key of the same button takes away input the state was
// never leaning on, and must change nothing.
//
// The failure this catches is the mirror of the partial-release one, and it
// is the more tempting mistake: an implementation that closes the state as
// soon as ANY key of the held union stops being deliverable would look
// correct in every single-bound test in the corpus, because with one key the
// anchor and the union are the same key. Two bindings is the smallest fixture
// where they can disagree.
//
// The negative half — "still Active after the wrong key was masked" — is a
// settle rather than a condition, because it is already true on arrival. What
// makes the silence mean something is the leg after it: the anchor is masked
// too, and the state closes even though the non-anchor key is STILL physically
// held. A state that merely ignored masks entirely would pass the first half
// and hang forever on the second.
//
// CkTests_DualBound stays on its authored F8/F12 defaults — no key binding is
// mutated, so there is nothing to reset on teardown. The masker's captures are
// added on a layer this test owns and dies with.
//============================================================================

class UCk_AutoTest_Intent_LevelMaskingNonAnchorKeyKeepsActive : UCk_AutoTest_Base
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
    private FKey  _AnchorKey;
    private FKey  _OtherKey;

    private int32 _ActivationFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _AnchorKey = EKeys::F8;
        _OtherKey  = EKeys::F12;

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

        Add_Step_WaitUntil("the dual-bound button derives with both keys",       n"Check_DualBoundDerived");
        Add_Step(          "bake the level intent on the dual-bound button",     n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers captures for BOTH keys",          n"Check_CapturesBothKeys");

        Add_Step(          "open the state on the ANCHOR key",                   n"Step_PressAnchor");
        Add_Step_WaitUntil("the state is open",                                  n"Check_Active");
        Add_Step(          "record the activation frame",                        n"Step_RecordActivation");

        Add_Step(          "also press the other bound key",                     n"Step_PressOther");
        Add_Step_WaitUntil("that press reaches the record",                      n"Check_OtherPressRecorded");

        Add_Step(          "mask the OTHER key only",                            n"Step_MaskOther");
        Add_Step_WaitUntil("that capture is in force",                           n"Check_OtherMasked");
        Add_Step_WaitFrames("give a wrong-key close a real window to happen in",  30);
        Add_Step(          "assert masking a non-anchor key changed nothing",    n"Step_AssertStillActive");

        Add_Step(          "now mask the ANCHOR key too",                        n"Step_MaskAnchor");
        Add_Step_WaitUntil("that capture is in force",                           n"Check_AnchorMasked");
        Add_Step_WaitUntil("the state closes",                                   n"Check_Idle");
        Add_Step(          "let go of both",                                     n"Step_ReleaseBoth");

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

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_PressAnchor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_AnchorKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordActivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ActivationFrame = utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Drag");

        Assert_True(_ActivationFrame >= 0,
            "an open state must name the frame it opened on, or 'unchanged' below has nothing to compare against");
    }

    UFUNCTION()
    private void Step_PressOther(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_OtherKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_MaskOther(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAddConsumeCapture(_OtherKey);
    }

    UFUNCTION()
    private void Step_AssertStillActive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Drag") ==
                    ECk_Intent_Phase::Active,
            "the masked key is not the one the state is riding on — closing here would be the union being mistaken for the anchor");

        Assert_Equals_Int(utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_Level_Drag"),
            _ActivationFrame,
            "and it is the SAME state throughout: a close-and-reopen would read as Active too, and only the frame tells them apart");
    }

    UFUNCTION()
    private void Step_MaskAnchor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoAddConsumeCapture(_AnchorKey);
    }

    UFUNCTION()
    private void Step_ReleaseBoth(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_AnchorKey, ECk_InputSource_EventType::Released);
        DoInject(_OtherKey,  ECk_InputSource_EventType::Released);
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
        Res.Set(Keys.Contains(_AnchorKey) && Keys.Contains(_OtherKey));
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
    private void Check_OtherPressRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_RoutedEdge(_OtherKey, ECk_InputSource_EventType::Pressed));
    }

    // Capture edits are DEFERRED, so both mask legs wait on the capture actually being in force —
    // asserting one hop after the request would be asserting against a mask that is not applied yet.
    UFUNCTION()
    private void Check_OtherMasked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _OtherKey));
    }

    UFUNCTION()
    private void Check_AnchorMasked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_layer::Get_HasCaptureForKey(_Masker, ECk_InputLayer_CaptureMatch::Key, _AnchorKey));
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
