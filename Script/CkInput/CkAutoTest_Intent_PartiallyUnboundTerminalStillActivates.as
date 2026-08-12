// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: A PARTIALLY-UNBOUND TERMINAL STILL ACTIVATES
//============================================================================
//
// The swap is atomic on EMPTINESS, not on "every declared slot is bound". A
// Mapped button that still resolves on ONE device while another slot sits
// unbound is a state a player can produce from a settings screen, not a
// defective set — so activation must succeed with the keys it has, and the
// terminal must still be completable from whichever key remains.
//
// CkAutoTest_Intent_SwapSetIsAtomic already proves the OTHER half of this
// contract — a terminal that resolves to ZERO keys rejects the WHOLE swap and
// leaves the previous set untouched — using a Physical button name the map
// never minted at all. This test does not repeat that atomicity proof; it
// exercises the specific path SwapSetIsAtomic cannot reach: a MAPPED button
// that WAS resolvable, is reduced to one key, still activates, then is
// reduced further to zero keys by unbinding its last slot and rejects.
//
// Per-slot unbinding goes through utils_key_binding::RemapKey with
// EKeys::Invalid as the new key (CkInput/CLAUDE.md "The button space": there
// is no UnMapPlayerKey call in this module because that engine entry point
// RESETS to default rather than unbinding — RemapKey(..., EKeys::Invalid, ...)
// is the documented unbind). No existing AutoTest unbinds a single SLOT of a
// multi-slot mapping (the closest precedent, UnbindConflictAndRemapUnbindsHolder,
// unbinds a single-slot mapping outright) — this is the first one to.
//
// TEARDOWN IS UNCONDITIONAL within its step: all autotests share one PIE
// session and profile rows outlive the test that touched them. A single
// ResetMappingToDefault call restores BOTH slots — it resets the whole row,
// not one slot at a time (Settings->ResetAllPlayerKeysInRow).
//============================================================================

class UCk_AutoTest_Intent_PartiallyUnboundTerminalStillActivates : UCk_AutoTest_Base
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

    private int32                       _CompletionCount     = 0;
    private int32                       _ExpectedCompletions = 0;
    private ECk_Request_OperationResult _LastResult          = ECk_Request_OperationResult::Failed;

    private int32 _PrimaryCompletionFrame = -1;

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
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        // This test holds the partial-binding completion's frame across the second unbind and the rejected
        // swap and asserts it UNCHANGED, so it must not be coupled to the decay window it is not about.
        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(200);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the dual-bound button derives with both keys",   n"Check_DualBoundDerived");
        Add_Step(          "unbind the SECOND slot",                        n"Step_UnbindSecondSlot");
        Add_Step_WaitUntil("the re-derive leaves exactly one key",          n"Check_OneKeyRemains");

        Add_Step(          "activate a set naming the partially-bound button", n"Step_SwapPartial");
        Add_Step_WaitUntil("the swap reports its outcome",                  n"Check_SwapAnswered");
        Add_Step(          "assert it activated with the remaining key",    n"Step_AssertPartialActivated");

        Add_Step(          "press the remaining PRIMARY key",               n"Step_PressPrimary");
        Add_Step_WaitUntil("the move completes",                            n"Check_Completed");
        Add_Step(          "record the frame, release the key",            n"Step_RecordThenRelease");

        Add_Step(          "unbind the LAST remaining slot too",            n"Step_UnbindFirstSlot");
        Add_Step_WaitUntil("the re-derive leaves zero keys",                n"Check_ZeroKeysRemain");

        Add_Step(          "attempt to activate the now fully-unbound button", n"Step_SwapFullyUnbound");
        Add_Step_WaitUntil("the swap reports its outcome",                  n"Check_SwapAnswered");
        Add_Step(          "assert it rejected, then restore the profile",  n"Step_AssertRejectedThenTeardown");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_UnbindSecondSlot(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        auto FailureReason = FGameplayTagContainer();

        auto Unbound = utils_key_binding::RemapKey(
            PlayerController, _MappingName, EPlayerMappableKeySlot::Second, EKeys::Invalid, FailureReason);
        Assert_True(Unbound, "RemapKey reports success unbinding the Second slot with EKeys::Invalid");

        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive());
    }

    UFUNCTION()
    private void Step_SwapPartial(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoSwap(DoBake("CkTests_DualBound", n"AS_Partial_Fire"));
    }

    UFUNCTION()
    private void Step_AssertPartialActivated(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "a terminal that still resolves on one slot must activate with the key it has");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 1,
            "the partially-bound set is the one the matcher is now running");

        auto CaptureKeys = utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher);
        Assert_True(CaptureKeys.Contains(_PrimaryKey),
            "the swap registers a capture for the surviving primary key");
        Assert_False(CaptureKeys.Contains(_SecondaryKey),
            "the swap must not carry a capture for a key the button no longer associates with");
    }

    UFUNCTION()
    private void Step_PressPrimary(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_PrimaryKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordThenRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PrimaryCompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Partial_Fire");

        Assert_True(_PrimaryCompletionFrame >= 0,
            "the surviving primary key must complete the terminal a partial binding still activated");

        DoInject(_PrimaryKey, ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_UnbindFirstSlot(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto PlayerController = Gameplay::GetPlayerController(0);
        auto FailureReason = FGameplayTagContainer();

        auto Unbound = utils_key_binding::RemapKey(
            PlayerController, _MappingName, EPlayerMappableKeySlot::First, EKeys::Invalid, FailureReason);
        Assert_True(Unbound, "RemapKey reports success unbinding the First slot with EKeys::Invalid");

        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive());
    }

    UFUNCTION()
    private void Step_SwapFullyUnbound(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoSwap(DoBake("CkTests_DualBound", n"AS_FullyUnbound_Fire"));
    }

    UFUNCTION()
    private void Step_AssertRejectedThenTeardown(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "a Mapped button reduced to zero keys rejects the WHOLE swap, the same as one the map never minted");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 1,
            "the rejected swap must leave the previously-activated partial set running");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Partial_Fire"),
            _PrimaryCompletionFrame,
            "the previous set's latch was never touched by the rejected swap");

        auto PlayerController = Gameplay::GetPlayerController(0);
        utils_key_binding::ResetMappingToDefault(PlayerController, _MappingName);
        utils_input_button_map::Request_Rederive(_Map, FCk_Request_InputButtonMap_Rederive());
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
    private void Check_OneKeyRemains(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Keys = utils_input_button_map::Get_KeysForButton(_Map, DoMake_MappedButton());
        Res.Set(Keys.Num() == 1 && Keys[0] == _PrimaryKey);
    }

    UFUNCTION()
    private void Check_ZeroKeysRemain(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_KeysForButton(_Map, DoMake_MappedButton()).Num() == 0);
    }

    UFUNCTION()
    private void Check_SwapAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CompletionCount >= _ExpectedCompletions);
    }

    UFUNCTION()
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Partial_Fire") ==
                ECk_Intent_Phase::Completed);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSwapCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        _LastResult = InResult;
        _CompletionCount += 1;
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        return Result.Get_Definition();
    }

    private FCk_Intent_CompiledSet DoBake(const FString& InNotation, FName InName)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse(InNotation, InName, 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(_MappingName, DoMake_MappedButton()));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile — this test is about ACTIVATION, not about the bake");

        return Baked.Get_CompiledSet();
    }

    private void DoSwap(const FCk_Intent_CompiledSet& InSet)
    {
        _ExpectedCompletions += 1;

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(InSet),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));
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
