// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: A SET ACTIVATES WHOLE, OR NOT AT ALL
//============================================================================
//
// Every other atomicity boundary in this module rejects at BAKE time, where
// the input is a designer's text. This one cannot: a set compiles perfectly
// and still names a button the player has left unbound, which is a state a
// settings screen can produce at runtime. So the rejection lives at
// ACTIVATION, and it has to leave the matcher exactly as it found it.
//
// "Exactly as it found it" is asserted through the previous set's LATCH
// rather than through a count, and that is the point of ordering the legs
// this way: a move is completed on the first set, then the bad swap is
// attempted, then the completion frame is read back. A swap that half-landed
// would have resized and cleared the phase rows, so the latch would read as
// never-completed even though the intent count looked unchanged.
//
// The third leg pins the other end of the same request: a default-constructed
// set is not a rejection, it is DEACTIVATION - captures removed, rows gone,
// and Succeeded, because that is what the caller asked for.
//============================================================================

class UCk_AutoTest_Intent_SwapSetIsAtomic : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _PunchKey;

    private int32                        _CompletionCount     = 0;
    private int32                        _ExpectedCompletions = 0;
    private ECk_Request_OperationResult  _LastResult          = ECk_Request_OperationResult::Failed;

    private int32 _PrimaryFrame = -1;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::G;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));
        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "activate a set the source can resolve",               n"Step_SwapResolvableSet");
        Add_Step_WaitUntil("the swap reports its outcome",                        n"Check_SwapAnswered");
        Add_Step(          "assert it succeeded",                                 n"Step_AssertFirstSwap");

        Add_Step(          "complete the move so the latch has a frame in it",    n"Step_PressPunch");
        Add_Step_WaitUntil("the move completes",                                  n"Check_PrimaryCompleted");
        Add_Step(          "record the latch, then swap in an unresolvable set",  n"Step_SwapUnresolvableSet");
        Add_Step_WaitUntil("the swap reports its outcome",                        n"Check_SwapAnswered");
        Add_Step(          "assert it failed whole and changed nothing",          n"Step_AssertRejectionChangedNothing");

        Add_Step(          "swap in an empty set",                                n"Step_SwapEmptySet");
        Add_Step_WaitUntil("the swap reports its outcome",                        n"Check_SwapAnswered");
        Add_Step(          "assert the matcher deactivated",                      n"Step_AssertDeactivated");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapResolvableSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("P", n"AS_Atomic_Primary", 100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey.GetKeyName())));

        DoSwap(DoBake(Definitions, Rows));
    }

    UFUNCTION()
    private void Step_AssertFirstSwap(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "a set whose every terminal resolves on this source must activate");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 1,
            "the activated set is the one the matcher is now running");
    }

    UFUNCTION()
    private void Step_PressPunch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Keyboard,
            _PunchKey,
            ECk_InputSource_EventType::Pressed);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
    }

    UFUNCTION()
    private void Step_SwapUnresolvableSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PrimaryFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Atomic_Primary");

        Assert_True(_PrimaryFrame >= 0,
            "the first set must have completed something, or the latch cannot prove it survived the rejection");

        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("Ghost", n"AS_Atomic_Unresolvable", 100));

        // The row is well-formed, so the BAKE accepts it - the identity it names simply is not one this source's
        // map has ever minted, which is a fact only the activation can know.
        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"Ghost", DoMake_PhysicalButton(n"CkTests_NoSuchKey")));

        DoSwap(DoBake(Definitions, Rows));
    }

    UFUNCTION()
    private void Step_AssertRejectionChangedNothing(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Failed,
            "one terminal the source cannot produce rejects the WHOLE swap");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 1,
            "the previous set is still the active one");

        Assert_Equals_Int(utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"AS_Atomic_Primary"),
            _PrimaryFrame,
            "the previous set's phase rows were never touched - a half-landed swap would have cleared them");

        Assert_True(utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey),
            "the previous set's captures are still registered");
    }

    UFUNCTION()
    private void Step_SwapEmptySet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoSwap(FCk_Intent_CompiledSet());
    }

    UFUNCTION()
    private void Step_AssertDeactivated(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "deactivating is what the caller asked for, so it succeeds rather than rejecting as empty");

        Assert_False(utils_intent_matcher::Get_HasActiveSet(_Matcher),
            "an empty set leaves the matcher with nothing to match");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 0,
            "no definitions remain to be polled");

        Assert_Equals_Int(utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Num(), 0,
            "captures follow the set, so deactivating releases every key the matcher had claimed");
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
    private void Check_SwapAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CompletionCount >= _ExpectedCompletions);
    }

    UFUNCTION()
    private void Check_PrimaryCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Atomic_Primary") ==
                ECk_Intent_Phase::Completed);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSwapCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
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

    private FCk_Intent_CompiledSet DoBake(
        const TArray<FCk_Intent_Definition>& InDefinitions,
        const TArray<FCk_Intent_ButtonNameRow>& InRows)
    {
        auto Baked = utils_intent_grammar::Bake(InDefinitions, InRows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile - this test is about ACTIVATION, not about the bake");

        return Baked.Get_CompiledSet();
    }

    private void DoSwap(const FCk_Intent_CompiledSet& InSet)
    {
        _ExpectedCompletions += 1;

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(InSet),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));
    }

    private FCk_Input_ButtonId DoMake_PhysicalButton(FName InName)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InName);
    }
}
