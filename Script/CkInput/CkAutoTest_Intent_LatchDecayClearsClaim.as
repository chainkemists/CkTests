// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A LATCH EXPIRES, AND TAKES ITS CLAIM WITH IT
//============================================================================
//
// Without decay, a completion stands forever. That reads harmless until you
// remember what a claim is: a consumer could take exclusive ownership of a
// special that landed thirty seconds and two fights ago, and every OTHER
// consumer polling the same row would be excluded from a move nobody made.
// The stale-latch bug and the stale-claim bug are the same bug one layer
// apart, and one decay fixes both.
//
// Three things are pinned, and the second is why the decay frame is asserted
// as arithmetic rather than as "eventually":
//
//   the row returns to Idle
//   it does so EXACTLY the decay window after the completion frame
//   the claim goes with it - unclaimed, and naming nobody
//
// The decay frame is read off the PhaseChanged payload rather than off the
// poll surface, because a decayed row deliberately carries no frame at all:
// the poll can say it decayed but not when, and the signal is the surface
// that answers when.
//============================================================================

class UCk_AutoTest_Intent_LatchDecayClearsClaim : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FCk_Handle _Claimant;

    private FKey _PunchKey;

    private int32 _LatchDecayFrames = 15;

    private int32 _CompletionFrame = -1;
    private int32 _DecayFrame      = -1;

    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::D;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Claimant = utils_entity_lifetime::Request_CreateEntity(InHandle);

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(_LatchDecayFrames);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Claimant), "the claimant must exist for the claim to name anybody");
        Assert_True(ck::IsValid(_Matcher),  "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnIntentPhaseChanged"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move and activate it",                    n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press the punch",                                     n"Step_Press");
        Add_Step_WaitUntil("the move completes",                                   n"Check_Completed");
        Add_Step(          "claim it and record the completion frame",             n"Step_ClaimAndRecord");
        Add_Step_WaitUntil("the latch decays",                                     n"Check_Decayed");
        Add_Step(          "assert the timing and that the claim went with it",    n"Step_AssertDecay");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_Decay_Move", 100));

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
    private void Step_ClaimAndRecord(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _CompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Decay_Move");

        Assert_True(_CompletionFrame >= 0,
            "the completion must carry a real frame for the decay window to be measured against it");

        _LastResult = ECk_Request_OperationResult::Failed_Cancelled;

        utils_intent_matcher::Request_Claim(_Matcher,
            FCk_Request_IntentMatcher_Claim(n"AS_Decay_Move", _Claimant),
            FCk_Delegate_Request_OnCompleted(this, n"OnClaimCompleted"));

        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "a standing completion is claimable, which is precisely what makes an undecaying one dangerous");

        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Decay_Move") == _Claimant,
            "the row names the claimant while the latch stands");
    }

    UFUNCTION()
    private void Step_AssertDecay(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_DecayFrame - _CompletionFrame, _LatchDecayFrames,
            "the latch returns to Idle exactly the declared decay window after it was stamped");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Decay_Move") ==
                    ECk_Intent_Phase::Idle,
            "the poll surface agrees: there is no standing completion any more");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Decay_Move"), -1,
            "a decayed row names no completion frame - the move did not happen recently enough to still be one");

        Assert_False(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Decay_Move"),
            "the claim decayed with the completion it belonged to");

        Assert_True(ck::Is_NOT_Valid(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Decay_Move")),
            "and the row names nobody, so a later poller is not excluded by an owner of a move that expired");
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
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Decay_Move") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_Decayed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_DecayFrame >= 0);
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
        if (InPreviousPhase != ECk_Intent_Phase::Completed || InNewPhase != ECk_Intent_Phase::Idle)
        { return; }

        _DecayFrame = InFrame;
    }

    UFUNCTION()
    private void OnClaimCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LastResult = InResult;
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
