// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: THERE IS NOTHING TO CLAIM YET
//============================================================================
//
// A claim takes ownership of a COMPLETION. Every other phase is a state in
// which no completion exists, so a claim against one is refused - and the
// refusal is what stops a consumer reserving a move it merely expects.
//
// `Pending` is the interesting case and the reason this test bakes a tap/hold
// pair rather than a bare move: it is the one phase where the press really
// happened, the matcher really is working on it, and the answer still might
// be this very move. An implementation that treated "an episode is running"
// as good enough would hand out an option on a completion that may never
// arrive - and would hand it out DURING the window where two consumers are
// most likely to be racing.
//
// The unknown-name leg rides along because it shares the rejection path and
// costs one line: a typo'd intent is refused rather than silently claiming
// nothing.
//============================================================================

class UCk_AutoTest_Intent_ClaimOnUncompletedRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FCk_Handle _Claimant;

    private FKey _PunchKey;

    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::W;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _Claimant = utils_entity_lifetime::Request_CreateEntity(InHandle);

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Claimant), "the claimant must exist for a rejection to be about the row");
        Assert_True(ck::IsValid(_Matcher),  "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a tap/hold pair and activate it",                n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "claim a move nothing has completed",                  n"Step_ClaimIdle");
        Add_Step(          "press and start the wait",                            n"Step_Press");
        Add_Step_WaitUntil("the press is held pending",                           n"Check_IsPending");
        Add_Step(          "claim the move while it is still pending",            n"Step_ClaimPending");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P hold=60", n"AS_Reject_Charged", 100));
        Definitions.Add(DoParse("P",         n"AS_Reject_Quick",    50));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    UFUNCTION()
    private void Step_ClaimIdle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Reject_Quick") ==
                    ECk_Intent_Phase::Idle,
            "nothing has been pressed yet, so the row is Idle and the rejection below is about that");

        DoClaim(n"AS_Reject_Quick");
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "an Idle move has no completion to take ownership of");

        DoClaim(n"AS_Reject_NoSuchMove");
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "a name the active set does not carry is refused rather than silently claiming nothing");
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
    private void Step_ClaimPending(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoClaim(n"AS_Reject_Quick");
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "a pending press might still answer this move or the other one - an option on a completion that may never arrive is exactly what the claim must not hand out");

        Assert_False(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Reject_Quick"),
            "a refused claim leaves no owner behind");

        DoClaim(n"AS_Reject_Charged");
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "the other candidate of the same wait is refused for the same reason");
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
        Res.Set(utils_intent_matcher::Get_ActiveIntentCount(_Matcher) == 2 &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey));
    }

    UFUNCTION()
    private void Check_IsPending(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Reject_Quick") ==
                ECk_Intent_Phase::Pending);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnClaimCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LastResult = InResult;
    }

    //------------------------------------------------------------------------

    private void DoClaim(FName InIntentName)
    {
        _LastResult = ECk_Request_OperationResult::Failed_Cancelled;

        utils_intent_matcher::Request_Claim(_Matcher,
            FCk_Request_IntentMatcher_Claim(InIntentName, _Claimant),
            FCk_Delegate_Request_OnCompleted(this, n"OnClaimCompleted"));

        Assert_True(_LastResult != ECk_Request_OperationResult::Failed_Cancelled,
            "the claim's completion must fire on the calling stack, refusal included");
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
