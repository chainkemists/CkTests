// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: ONE OPEN STATE, ONE OWNER
//============================================================================
//
// A level intent has the same exclusivity problem an episodic one has - two
// consumers can both poll `Active` and both act on it - and it gets the same
// answer rather than a second mechanism beside it: `Active` is CLAIMABLE, on
// the same call, with the same outcomes.
// CkAutoTest_Intent_ClaimExcludesSecondClaimant pins that shape over a
// `Completed` latch. This is the same shape over a state, and the difference
// is not the taking but the LETTING GO:
//
//   a completion's claim is bounded by the latch decay - time runs out
//   a state's claim is bounded by the player letting go - input runs out
//
// So the deactivation leg is the half this test exists for, and it is asserted
// three ways, because "reads unclaimed" alone is worth very little: an Idle row
// answers `false` to `Get_IsClaimed` whether the claim was released or is still
// sitting in the row unread. A claim attempted while Idle must FAIL (there is
// nothing to own), and a claim on the state opened by the NEXT press must
// SUCCEED for a different claimant - which no stale ownership could allow.
//
// All three claims of the first round happen in ONE step, on one call stack,
// for the reason the mechanism is an immediate mutator at all: a deferred claim
// leaves both consumers reading an unclaimed row and both acting, which is the
// race the claim exists to remove.
//============================================================================

class UCk_AutoTest_Intent_LevelActiveIsClaimable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FCk_Handle _ClaimantA;
    private FCk_Handle _ClaimantB;

    private FKey _DragKey;

    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _DragKey = EKeys::N;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        _ClaimantA = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _ClaimantB = utils_entity_lifetime::Request_CreateEntity(InHandle);

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_DragKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_ClaimantA), "claimant A must exist for the exclusion to name anybody");
        Assert_True(ck::IsValid(_ClaimantB), "claimant B must exist for the exclusion to be testable");
        Assert_True(ck::IsValid(_Matcher),   "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the drag key and the sampler records", n"Check_Recording");
        Add_Step(          "bake the level intent and activate it",              n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",          n"Check_SetActive");

        Add_Step(          "open the state",                                     n"Step_Press");
        Add_Step_WaitUntil("the state is open",                                  n"Check_Active");
        Add_Step(          "claim it from A, then B, then A again - one frame",  n"Step_ClaimTwice");

        Add_Step(          "let go - the state's claim is bounded by input",     n"Step_Release");
        Add_Step_WaitUntil("the state closes",                                    n"Check_Idle");
        Add_Step(          "assert the close released the claim",                n"Step_AssertClaimReleased");

        // The re-press cannot share a batch with the release: the Idle wait above already required
        // that release to have been sampled and acted on, which is several steps back by now.
        Add_Step(          "open the state again",                                n"Step_Press");
        Add_Step_WaitUntil("the state is open",                                   n"Check_Active");
        Add_Step(          "assert the NEXT state is claimable by anybody",      n"Step_AssertNextStateIsFree");
        Add_Step(          "let go",                                              n"Step_Release");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV level", n"AS_Level_Claimed", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_PhysicalButton(_DragKey)));

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
    private void Step_ClaimTwice(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Level_Claimed"),
            "a freshly opened state is unclaimed - an activation carries no owner of its own");

        DoClaim(_ClaimantA);
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "Active is claimable, and the first claimant takes ownership of an unclaimed state");
        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Level_Claimed") == _ClaimantA,
            "the row names the entity that claimed it, not merely that somebody did");

        DoClaim(_ClaimantB);
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "a second consumer on the same open state is excluded - that IS the mechanism, not a malfunction");
        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Level_Claimed") == _ClaimantA,
            "a rejected claim leaves the holder untouched");

        DoClaim(_ClaimantA);
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "the holder re-asserting its own ownership is idempotent - the caller's intent already holds");
        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Level_Claimed") == _ClaimantA,
            "and the holder is still A");

        Assert_True(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Level_Claimed"),
            "the open state reads as claimed for every later poller on this layer");
    }

    UFUNCTION()
    private void Step_Release(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_AssertClaimReleased(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Level_Claimed"),
            "every phase transition clears the claim as it is written, so the Active -> Idle the release wrote dropped it with the state");

        Assert_Invalid(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Level_Claimed"),
            "and nobody is named - there is nothing for a consumer to release and nothing that outlives the input it was taken against");

        DoClaim(_ClaimantA);
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "an Idle row is not claimable even by the entity that held it a frame ago - there is nothing to take ownership of");
    }

    UFUNCTION()
    private void Step_AssertNextStateIsFree(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_Level_Claimed"),
            "the state the NEXT press opened carries no ownership from the one before it");

        // B, deliberately: A succeeding here would also be explained by a stale claim that was never
        // released. Only the claimant that LOST the first round can distinguish the two.
        DoClaim(_ClaimantB);
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "the consumer excluded from the first state takes the second one - which no surviving claim could have allowed");
        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_Level_Claimed") == _ClaimantB,
            "and the row names B, so the ownership really moved rather than being reported loosely");
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _DragKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_ActiveIntentCount(_Matcher) == 1 &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_DragKey));
    }

    UFUNCTION()
    private void Check_Active(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Claimed") ==
                ECk_Intent_Phase::Active);
    }

    UFUNCTION()
    private void Check_Idle(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Claimed") ==
                ECk_Intent_Phase::Idle);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnClaimCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LastResult = InResult;
    }

    //------------------------------------------------------------------------

    // The claim is immediate, so the delegate has already fired by the time this returns and
    // _LastResult is the outcome of THIS call rather than of some earlier one that happened to drain.
    private void DoClaim(FCk_Handle InClaimant)
    {
        _LastResult = ECk_Request_OperationResult::Failed_Cancelled;

        utils_intent_matcher::Request_Claim(_Matcher,
            FCk_Request_IntentMatcher_Claim(n"AS_Level_Claimed", InClaimant),
            FCk_Delegate_Request_OnCompleted(this, n"OnClaimCompleted"));

        Assert_True(_LastResult != ECk_Request_OperationResult::Failed_Cancelled,
            "the claim's completion must fire on the calling stack - a deferred claim cannot exclude anybody");
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

    private void DoInject(ECk_InputSource_EventType InEventType)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _DragKey,
            InEventType);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }
}
