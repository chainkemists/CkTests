// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: ONE COMPLETION, ONE OWNER
//============================================================================
//
// Polling is a read, so nothing about it stops two consumers acting on the
// same completion. The claim is what makes ownership exclusive, and the whole
// reason it is an IMMEDIATE mutator rather than a deferred request is what
// this test exercises: all three claims happen on ONE frame, in one step, on
// one call stack. A deferred claim would leave both consumers reading an
// unclaimed row and both acting — the race the mechanism exists to remove.
//
// Three claims, in order, and the third is the one an over-strict
// implementation gets wrong:
//
//   A claims  -> Succeeded, and the row names A
//   B claims  -> Failed. The exclusion working as designed, not an error.
//   A claims  -> Succeeded. Idempotent: A's intent already holds, and
//                reporting Failed would make a consumer that re-asserts its
//                own ownership look like it lost it.
//
// `TryGet_ClaimedBy` is checked after every one of them, because "the second
// claim failed" and "the second claim failed AND did not overwrite the first"
// are different claims about the same call.
//============================================================================

class UCk_AutoTest_Intent_ClaimExcludesSecondClaimant : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FCk_Handle _ClaimantA;
    private FCk_Handle _ClaimantB;

    private FKey _PunchKey;

    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::R;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _ClaimantA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _ClaimantB = utils_entity_lifetime::Request_CreateEntity(InHandle);

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_ClaimantA), "claimant A must exist for the exclusion to name anybody");
        Assert_True(ck::IsValid(_ClaimantB), "claimant B must exist for the exclusion to be testable");
        Assert_True(ck::IsValid(_Matcher),   "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move and activate it",                    n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press the punch",                                     n"Step_Press");
        Add_Step_WaitUntil("the move completes",                                   n"Check_Completed");
        Add_Step(          "claim it from A, then B, then A again — one frame",    n"Step_ClaimTwice");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_Claim_Move", 100));

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
    private void Step_ClaimTwice(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Claim_Move"),
            "a freshly completed move is unclaimed — a completion carries no owner of its own");

        DoClaim(_ClaimantA);
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "the first claimant takes ownership of an unclaimed completion");
        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Claim_Move") == _ClaimantA,
            "the row names the entity that claimed it, not merely that somebody did");

        DoClaim(_ClaimantB);
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "a second claimant on the same completion is excluded — that IS the mechanism, not a malfunction");
        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Claim_Move") == _ClaimantA,
            "a rejected claim leaves the holder untouched");

        DoClaim(_ClaimantA);
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "the holder re-asserting its own ownership is idempotent — the caller's intent already holds");
        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Claim_Move") == _ClaimantA,
            "and the holder is still A");

        Assert_True(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Claim_Move"),
            "the completion reads as claimed for every later poller on this layer");
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
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Claim_Move") ==
                ECk_Intent_Phase::Completed);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnClaimCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LastResult = InResult;
    }

    //------------------------------------------------------------------------

    // The claim is immediate, so the delegate has already fired by the time this returns and _LastResult is the
    // outcome of THIS call rather than of some earlier one that happened to drain.
    private void DoClaim(FCk_Handle InClaimant)
    {
        _LastResult = ECk_Request_OperationResult::Failed_Cancelled;

        utils_intent_matcher::Request_Claim(_Matcher,
            FCk_Request_IntentMatcher_Claim(n"AS_Claim_Move", InClaimant),
            FCk_Delegate_Request_OnCompleted(this, n"OnClaimCompleted"));

        Assert_True(_LastResult != ECk_Request_OperationResult::Failed_Cancelled,
            "the claim's completion must fire on the calling stack — a deferred claim cannot exclude anybody");
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
