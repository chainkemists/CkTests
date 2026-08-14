// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE SWAP CLOSES THE OLD STATE ON THE OLD ROWS
//============================================================================
//
// CkAutoTest_Intent_LevelSwapWhileActiveDeactivates proves a swap CLOSES an
// open state rather than dropping it, using a default-constructed set. That
// case is the safe one: afterwards there are no rows at all, so a phase write
// that landed a moment too late would land nowhere and go unnoticed.
//
// This is the same swap into a set that is NOT empty, which is the shape every
// real swap has — a context change, a vehicle entered, a menu opened — and the
// one where the ordering has teeth. Phase rows are addressed by INDEX into the
// active set, so an implementation that replaced the set and then swept the
// non-Idle rows would write `Active -> Idle` against index 0 of the INCOMING
// set: a signal naming an intent that never activated, fired at a consumer who
// just bound to it, on the frame their context came up.
//
// So the assertions are in two halves and both are necessary:
//
//   the outgoing intent signals out EXACTLY ONCE, at INDEX_NONE — no input row
//   closed it, and stamping a real frame would tell a consumer measuring the
//   hold that the player let go
//
//   the incoming intents record NOTHING — not a transition, not a phase — and
//   the incoming set is running with both rows Idle, waiting for a press like
//   any freshly activated set
//
// The incoming set carries TWO intents, a level and an edge at different
// priorities, so the stale-index write has somewhere to land if it happens:
// against a set with fewer rows the bad write would be silently clamped away
// and the test would pass by accident.
//
// The "nothing landed on the new set" half is a negative — already true on
// arrival — so it rides a settle, and what makes the silence mean something is
// the outgoing transition asserted beside it.
//============================================================================

class UCk_AutoTest_Intent_LevelSwapToNonEmptySetSevers : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _OldKey;
    private FKey _NewKey;

    private int32                       _CompletionCount     = 0;
    private int32                       _ExpectedCompletions = 0;
    private ECk_Request_OperationResult _LastResult          = ECk_Request_OperationResult::Failed;

    private int32 _ActivationFrame = -1;

    private TArray<ECk_Intent_Phase> _OldFromPhases;
    private TArray<ECk_Intent_Phase> _OldToPhases;
    private TArray<int32>            _OldFrames;

    private int32 _NewSetTransitions = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _OldKey = EKeys::G;
        _NewKey = EKeys::H;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_OldKey);
        PhysicalButtons.Add(_NewKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(240));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
        MatcherParams.Set_LatchDecayFrames(200);

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);

        Assert_True(ck::IsValid(_Map),     "the button map must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        utils_intent_matcher::BindTo_OnIntentPhaseChanged(_Matcher,
            FCk_Delegate_IntentMatcher_PhaseChanged(this, n"OnIntentPhaseChanged"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        Add_Step_WaitUntil("the map mints both keys and the sampler records",   n"Check_Recording");
        Add_Step(          "activate the OUTGOING set — one level intent",      n"Step_SwapOldSet");
        Add_Step_WaitUntil("the swap reports its outcome",                      n"Check_SwapAnswered");
        Add_Step(          "assert it succeeded",                               n"Step_AssertOldSetRunning");

        Add_Step(          "open the state",                                    n"Step_PressOld");
        Add_Step_WaitUntil("the state is open",                                 n"Check_OldActive");
        Add_Step(          "record the activation frame",                       n"Step_RecordActivation");

        Add_Step(          "swap to a NON-EMPTY set while it is still open",    n"Step_SwapNewSet");
        Add_Step_WaitUntil("the swap reports its outcome",                      n"Check_SwapAnswered");
        Add_Step_WaitFrames("give a stale-index write a window to land in",      30);
        Add_Step(          "assert the old state closed and the new set is untouched", n"Step_AssertSevered");
        Add_Step(          "let go of the outgoing key",                        n"Step_ReleaseOld");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapOldSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("OLD level", n"AS_LevelSever_Old", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"OLD", DoMake_PhysicalButton(_OldKey)));

        DoSwap(DoBake(Definitions, Rows));
    }

    UFUNCTION()
    private void Step_AssertOldSetRunning(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "a set whose terminal resolves on this source must activate");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 1,
            "the outgoing set is the one the matcher is running, and it has exactly the one row the sweep will have to close");
    }

    UFUNCTION()
    private void Step_PressOld(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_OldKey, ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_RecordActivation(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ActivationFrame = utils_intent_matcher::TryGet_ActivationFrame_ByName(_Matcher, n"AS_LevelSever_Old");

        Assert_True(_ActivationFrame >= 0,
            "the state must really be open on a real frame, or the swap has nothing to sever");
    }

    // Two intents, different priorities — a tie on one terminal is a bake rejection, and the point
    // here is a set that RUNS, not one that refuses to compile.
    UFUNCTION()
    private void Step_SwapNewSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("NEW level", n"AS_LevelSever_NewLevel", 0));
        Definitions.Add(DoParse("NEW",       n"AS_LevelSever_NewEdge",  100));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"NEW", DoMake_PhysicalButton(_NewKey)));

        DoSwap(DoBake(Definitions, Rows));
    }

    UFUNCTION()
    private void Step_AssertSevered(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "the incoming set resolves on this source, so the swap is an ordinary success");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 2,
            "the incoming set is running, which is what makes a stale-index write possible at all");

        Assert_Equals_Int(_OldFromPhases.Num(), 2,
            "the outgoing intent signalled EXACTLY once on the way out — a second close is the sweep running twice, and none at all is the rows being dropped without telling the consumer holding the door");

        if (_OldFromPhases.Num() != 2)
        { return; }

        Assert_True(_OldFromPhases[1] == ECk_Intent_Phase::Active && _OldToPhases[1] == ECk_Intent_Phase::Idle,
            "and the second transition is the close, named against the OUTGOING intent — only the set that still carried it could name it");

        Assert_Equals_Int(_OldFrames[1], -1,
            "no input row closed this state, so it names no frame — stamping the current one would tell a consumer the player let go");

        Assert_Equals_Int(_NewSetTransitions, 0,
            "not one phase write landed on the incoming set: an implementation that replaced the rows before sweeping them would announce a state change against index 0 of a set that has never seen a press");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_LevelSever_NewLevel") ==
                    ECk_Intent_Phase::Idle,
            "the incoming level row is waiting for a press like any freshly activated one");

        Assert_True(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_LevelSever_NewEdge") ==
                    ECk_Intent_Phase::Idle,
            "and so is its edge sibling — the row the outgoing sweep would have hit if it ran a frame late");
    }

    UFUNCTION()
    private void Step_ReleaseOld(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(_OldKey, ECk_InputSource_EventType::Released);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_Recording(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_input_button_map::Get_ButtonIdsForKey(_Map, _OldKey).Num() >= 1 &&
                utils_input_button_map::Get_ButtonIdsForKey(_Map, _NewKey).Num() >= 1 &&
                utils_intent_sampler::Get_FrameCount(_Sampler) >= 1);
    }

    UFUNCTION()
    private void Check_SwapAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CompletionCount >= _ExpectedCompletions);
    }

    UFUNCTION()
    private void Check_OldActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_LevelSever_Old") ==
                ECk_Intent_Phase::Active);
    }

    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSwapCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished())
        { return; }

        _LastResult = InResult;
        _CompletionCount += 1;
    }

    UFUNCTION()
    private void OnIntentPhaseChanged(
        FCk_Handle_IntentMatcher InMatcher,
        FName InIntentName,
        FGameplayTag InIntentTag,
        ECk_Intent_Phase InPreviousPhase,
        ECk_Intent_Phase InNewPhase,
        int32 InFrame)
    {
        if (IsFinished())
        { return; }

        if (InIntentName == n"AS_LevelSever_NewLevel" || InIntentName == n"AS_LevelSever_NewEdge")
        {
            _NewSetTransitions += 1;
            return;
        }

        if (InIntentName != n"AS_LevelSever_Old")
        { return; }

        _OldFromPhases.Add(InPreviousPhase);
        _OldToPhases.Add(InNewPhase);
        _OldFrames.Add(InFrame);
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
            "the fixture set must compile before the matcher can run it");

        return Baked.Get_CompiledSet();
    }

    private void DoSwap(const FCk_Intent_CompiledSet& InSet)
    {
        _ExpectedCompletions += 1;

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(InSet),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));
    }

    private FCk_Input_ButtonId DoMake_PhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
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
