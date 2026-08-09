// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE WHOLE LIFECYCLE, TWICE ROUND
//============================================================================
//
// Each earlier test pins one edge. This one drives the loop, because the
// failure that matters most is not any single edge being wrong — it is state
// left behind by one pass that poisons the next:
//
//   press -> complete -> claim          the first ownership is granted
//   decay                                the latch and the claim expire
//   claim again                          REFUSED: there is nothing to own
//   re-press -> complete again           a new event, on a later frame
//   claim again                          granted, by the same consumer
//
// The refusal in the middle is the load-bearing step. A row that decayed but
// kept its claimant would answer that claim Succeeded — idempotently, since
// the claimant matches — and a consumer would act on a move that expired.
// A row that cleared the claimant but not the phase would answer it
// Succeeded too. Only a row that cleared BOTH refuses, which is why the
// refusal is what proves the decay was complete rather than cosmetic.
//
// The re-completion then proves the row is not merely empty but re-armed: a
// fresh press produces a genuinely later completion frame, and ownership can
// be taken again by the same consumer that held the expired one.
//============================================================================

class UCk_AutoTest_Intent_ClaimDecayRecompleteLoop : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FCk_Handle _Claimant;

    private FKey _PunchKey;

    private int32 _LatchDecayFrames = 15;

    private int32 _FirstCompletionFrame = -1;

    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::F4;

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

        Assert_True(ck::IsValid(_Claimant), "the claimant must exist for ownership to name anybody");
        Assert_True(ck::IsValid(_Matcher),  "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move and activate it",                    n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press the punch",                                     n"Step_Press");
        Add_Step_WaitUntil("the move completes",                                   n"Check_Completed");
        Add_Step(          "claim it and record the frame, then release",          n"Step_ClaimFirst");
        Add_Step_WaitUntil("the latch decays",                                     n"Check_Decayed");
        Add_Step(          "assert a decayed row refuses the same claimant",       n"Step_AssertDecayedRefuses");

        Add_Step(          "press the punch again",                                n"Step_Press");
        Add_Step_WaitUntil("the move completes on a later frame",                  n"Check_RecompletedLater");
        Add_Step(          "claim the new completion",                             n"Step_ClaimSecond");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_Loop_Move", 100));

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
    private void Step_ClaimFirst(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _FirstCompletionFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Loop_Move");

        Assert_True(_FirstCompletionFrame >= 0,
            "the first completion must carry a real frame for the second to be shown to be a different one");

        DoClaim();

        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "a standing completion is claimable");

        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Loop_Move") == _Claimant,
            "and the row names the consumer that took it");

        // Released now so the second press is a real press EDGE rather than a button that never came up.
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertDecayedRefuses(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Loop_Move"),
            "the claim expired with the completion it belonged to");

        DoClaim();

        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "the SAME consumer is refused now — a row that kept either half of its old state would answer Succeeded and let it act on a move that expired");

        Assert_True(ck::Is_NOT_Valid(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Loop_Move")),
            "and a refused claim leaves no owner behind on an already-empty row");
    }

    UFUNCTION()
    private void Step_ClaimSecond(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto SecondFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Loop_Move");

        Assert_True(SecondFrame > _FirstCompletionFrame,
            "the second press produced a genuinely new completion rather than reviving the decayed one");

        DoClaim();

        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "the row re-armed: the consumer whose expired claim was cleared can own the new completion");

        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Loop_Move") == _Claimant,
            "and the row names it again, on the new completion this time");
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
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Loop_Move") ==
                ECk_Intent_Phase::Completed);
    }

    UFUNCTION()
    private void Check_Decayed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Loop_Move") ==
                ECk_Intent_Phase::Idle);
    }

    UFUNCTION()
    private void Check_RecompletedLater(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Loop_Move") >
                _FirstCompletionFrame);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnClaimCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LastResult = InResult;
    }

    //------------------------------------------------------------------------

    private void DoClaim()
    {
        _LastResult = ECk_Request_OperationResult::Failed_Cancelled;

        utils_intent_matcher::Request_Claim(_Matcher,
            FCk_Request_IntentMatcher_Claim(n"AS_Loop_Move", _Claimant),
            FCk_Delegate_Request_OnCompleted(this, n"OnClaimCompleted"));

        Assert_True(_LastResult != ECk_Request_OperationResult::Failed_Cancelled,
            "the claim's completion must fire on the calling stack, granted or refused");
    }

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
