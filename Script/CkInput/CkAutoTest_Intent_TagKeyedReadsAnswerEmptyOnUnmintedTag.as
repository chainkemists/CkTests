// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE TAG-KEYED READS, WHILE NOTHING MINTS A TAG
//============================================================================
//
// `Get_IntentPhase` is the RULED primary read and it is keyed by the
// definition's `_IntentTag`. The `Intent.*` namespace is still an open
// question, nothing mints a tag, and the grammar carries whatever it is handed
// — so every set baked today carries an EMPTY tag, and the four tag-keyed
// reads answer nothing for every caller. `_ByName` is what a v1 consumer and
// every other test in this battery actually calls.
//
// That is a deliberate interim state, not a defect, and this test PINS it:
//
//   Get_IntentPhase        -> Idle
//   TryGet_CompletionFrame -> INDEX_NONE
//   Get_IsClaimed          -> false
//   TryGet_ClaimedBy       -> an invalid handle
//
// Both ways of missing are covered, because they miss for different reasons
// and only one of them survives the namespace landing: an EMPTY tag is
// rejected before the set is ever consulted, while a real, registered tag the
// set does not carry walks the intents and finds no row. A future change that
// mints tags at bake time turns the first leg red — which is the point. This
// file is where "the tag surface answers nothing yet" is written down, so that
// day shows up as a deliberate, located red rather than as four reads quietly
// starting to work with nobody having decided they should.
//
// WHAT MAKES THE FOUR NEGATIVES NON-VACUOUS. They are asserted against a
// matcher whose row is as far from empty as this module can make it: a live
// set, a move that really completed, and a claim really taken on it. The
// `_ByName` forms are asserted FIRST and report all of that. So the tag forms
// are not answering `Idle`/`INDEX_NONE`/`false`/invalid because there is
// nothing to report — they are answering it while the row beside them reports
// everything.
//============================================================================

class UCk_AutoTest_Intent_TagKeyedReadsAnswerEmptyOnUnmintedTag : UCk_AutoTest_Base
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

    // Long enough that the latch, and the claim it bounds, are both still standing when the assertions read them.
    private int32 _LatchDecayFrames = 120;

    private ECk_Request_OperationResult _LastResult = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::F7;

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

        Assert_True(ck::IsValid(_Claimant), "the claimant must exist for the claim leg to name anybody");
        Assert_True(ck::IsValid(_Matcher),  "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "bake a bare move and activate it",                    n"Step_SwapSet");
        Add_Step_WaitUntil("the swap registers the terminal's capture",           n"Check_SetActive");

        Add_Step(          "press the punch",                                     n"Step_Press");
        Add_Step_WaitUntil("the move completes",                                  n"Check_Completed");
        Add_Step(          "claim the completion so every row has something to report", n"Step_Claim");
        Add_Step(          "assert the name-keyed reads report the live row",     n"Step_AssertByNameIsLive");
        Add_Step(          "assert the tag-keyed reads answer nothing",           n"Step_AssertTagKeyedAnswerEmpty");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_TagRead_Move", 100));

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
    private void Step_Claim(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _LastResult = ECk_Request_OperationResult::Failed_Cancelled;

        utils_intent_matcher::Request_Claim(_Matcher,
            FCk_Request_IntentMatcher_Claim(n"AS_TagRead_Move", _Claimant),
            FCk_Delegate_Request_OnCompleted(this, n"OnClaimCompleted"));

        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "a standing completion is claimable, and the claim is what gives the ownership reads something to answer");
    }

    UFUNCTION()
    private void Step_AssertByNameIsLive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_intent_matcher::Get_HasActiveSet(_Matcher),
            "the matcher is running a set");
        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 1,
            "and that set carries exactly the one move this fixture baked");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_TagRead_Move") ==
                    ECk_Intent_Phase::Completed,
            "the row is Completed — the tag-keyed phase read below answers Idle beside a row that is anything but");

        Assert_True(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_TagRead_Move") >= 0,
            "the row carries a real completion frame, so the INDEX_NONE below is a lookup miss rather than an absent completion");

        Assert_True(utils_intent_matcher::Get_IsClaimed_ByName(_Matcher, n"AS_TagRead_Move"),
            "the row is claimed, so the false below is a lookup miss rather than an unowned completion");

        Assert_True(utils_intent_matcher::TryGet_ClaimedBy_ByName(_Matcher, n"AS_TagRead_Move") == _Claimant,
            "and it names the claimant, so the invalid handle below is a lookup miss rather than a row with no owner");
    }

    UFUNCTION()
    private void Step_AssertTagKeyedAnswerEmpty(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto EmptyTag = FGameplayTag();

        Assert_False(EmptyTag.IsValid(),
            "the empty tag is the one every set baked today carries, since nothing mints an Intent.* tag");

        DoAssert_AnswersNothing(EmptyTag,
            "an empty tag is rejected before the set is consulted at all");

        // A real, registered tag from another feature's namespace. It reaches the set and finds no row, which is the
        // OTHER way a tag-keyed read misses — and the way that survives whatever the Intent.* namespace turns out to be.
        auto UnrelatedTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Cue.AfterOneFrame");

        Assert_True(UnrelatedTag.IsValid(),
            "the unrelated tag must be a registered one, or this leg would be a second empty-tag leg wearing a name");

        DoAssert_AnswersNothing(UnrelatedTag,
            "a registered tag the active set does not carry walks the intents and finds no row");
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
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_TagRead_Move") ==
                ECk_Intent_Phase::Completed);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnClaimCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _LastResult = InResult;
    }

    //------------------------------------------------------------------------

    private void DoAssert_AnswersNothing(FGameplayTag InTag, const FString& InWhy)
    {
        Assert_True(utils_intent_matcher::Get_IntentPhase(_Matcher, InTag) == ECk_Intent_Phase::Idle,
            f"the tag-keyed phase read answers Idle: {InWhy}");

        // INDEX_NONE. A phase enum has no Unknown value and the frame read has no found-flag, so a miss and a row
        // that is simply not Completed answer identically — deliberately, since a consumer acts the same on both.
        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame(_Matcher, InTag), -1,
            f"the tag-keyed completion frame answers INDEX_NONE: {InWhy}");

        Assert_False(utils_intent_matcher::Get_IsClaimed(_Matcher, InTag),
            f"the tag-keyed ownership read answers false: {InWhy}");

        Assert_True(ck::Is_NOT_Valid(utils_intent_matcher::TryGet_ClaimedBy(_Matcher, InTag)),
            f"the tag-keyed claimant read answers an invalid handle: {InWhy}");
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
