// Language=angelscript

//============================================================================
// CK INTENT - AUTOMATION TEST: SWAPPING THE SET CLOSES WHAT IT WAS HOLDING
//============================================================================
//
// A state outlives the frame it opened on, which makes it the one thing in
// the matcher a set swap can leave STRANDED. An edge intent's latch is a
// value that goes away with the rows that held it; an open level intent is a
// consumer somewhere holding a door open, and if the swap simply drops the
// rows, that consumer is never told the door closed.
//
// So the swap must close it, and it must close it as a broadcast TRANSITION
// rather than by quietly resizing the phase rows out from under it. A
// default-constructed set is used because that is the deactivation leg of the
// swap contract - captures released, rows gone, Succeeded, because that is
// what the caller asked for - and it is the harshest version of the case: the
// intent's NAME does not exist afterwards.
//
// Which is exactly why this is asserted from the SIGNAL rather than from the
// poll. After the swap there is nothing left to poll: the matcher has no row
// named AS_Level_Swapped, so any answer it gives is about absence, not about
// the closing. The transition list is the only witness that the state ended
// rather than evaporated.
//
// The frame it carries is INDEX_NONE, and that is deliberate rather than
// sloppy: no input row closed this state. Stamping the current frame would
// tell a consumer measuring durations that the player let go, which is a
// different fact about a different world.
//============================================================================

class UCk_AutoTest_Intent_LevelSwapWhileActiveDeactivates : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey _DragKey;

    private int32                       _CompletionCount     = 0;
    private int32                       _ExpectedCompletions = 0;
    private ECk_Request_OperationResult _LastResult          = ECk_Request_OperationResult::Failed;

    private TArray<ECk_Intent_Phase> _FromPhases;
    private TArray<ECk_Intent_Phase> _ToPhases;
    private TArray<int32>            _Frames;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _DragKey = EKeys::F8;

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_DragKey);

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

        Add_Step_WaitUntil("the map mints the drag key and the sampler records", n"Check_Recording");
        Add_Step(          "activate a set with one level intent in it",         n"Step_SwapLevelSet");
        Add_Step_WaitUntil("the swap reports its outcome",                       n"Check_SwapAnswered");
        Add_Step(          "assert it succeeded",                                n"Step_AssertFirstSwap");

        Add_Step(          "open the state",                                     n"Step_Press");
        Add_Step_WaitUntil("the state is open",                                  n"Check_Active");
        Add_Step(          "swap the set away while it is still open",           n"Step_SwapEmptySet");
        Add_Step_WaitUntil("the swap reports its outcome",                       n"Check_SwapAnswered");
        Add_Step(          "assert the state was CLOSED, not dropped",           n"Step_AssertClosedBySwap");
        Add_Step(          "let go",                                             n"Step_Release");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapLevelSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(DoParse("LV level", n"AS_Level_Swapped", 0));

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"LV", DoMake_PhysicalButton(_DragKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        DoSwap(Baked.Get_CompiledSet());
    }

    UFUNCTION()
    private void Step_AssertFirstSwap(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "a set whose terminal resolves on this source must activate");

        Assert_Equals_Int(utils_intent_matcher::Get_ActiveIntentCount(_Matcher), 1,
            "the level intent is the one the matcher is now running");
    }

    UFUNCTION()
    private void Step_Press(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_SwapEmptySet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoSwap(FCk_Intent_CompiledSet());
    }

    UFUNCTION()
    private void Step_AssertClosedBySwap(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastResult == ECk_Request_OperationResult::Succeeded,
            "deactivating is what the caller asked for, so it succeeds rather than rejecting as empty");

        Assert_False(utils_intent_matcher::Get_HasActiveSet(_Matcher),
            "the set is gone, which is what makes the poll useless here and the signal the only witness");

        Assert_Equals_Int(_FromPhases.Num(), 2,
            "open then close: a swap that dropped the rows without closing would leave this at one");

        if (_FromPhases.Num() != 2)
        { return; }

        Assert_True(_FromPhases[1] == ECk_Intent_Phase::Active && _ToPhases[1] == ECk_Intent_Phase::Idle,
            "the second transition is the swap closing the state a consumer is still holding open");

        Assert_Equals_Int(_Frames[1], -1,
            "no input row closed this state, so it names no frame - stamping the current one would tell a consumer the player let go");
    }

    UFUNCTION()
    private void Step_Release(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Released);
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
    private void Check_SwapAnswered(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_CompletionCount >= _ExpectedCompletions);
    }

    UFUNCTION()
    private void Check_Active(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"AS_Level_Swapped") ==
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

        if (InIntentName != n"AS_Level_Swapped")
        { return; }

        _FromPhases.Add(InPreviousPhase);
        _ToPhases.Add(InNewPhase);
        _Frames.Add(InFrame);
    }

    //------------------------------------------------------------------------

    private FCk_Intent_Definition DoParse(const FString& InNotation, FName InName, int32 InPriority)
    {
        auto Result = utils_intent_grammar::Parse(InNotation, InName, InPriority, FGameplayTag());

        Assert_True(Result.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        return Result.Get_Definition();
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
