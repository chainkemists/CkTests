// Language=angelscript

//============================================================================
// CK INTENT — AUTOMATION TEST: THE NEAR-MISS RING, AND ITS OFF SWITCH
//============================================================================
//
// A failed scan leaves no trace anywhere else. The matcher simply declines to
// complete, so "I did the motion and nothing came out" is invisible to the
// record, the phase rows and the signals alike — which makes the diagnostic
// ring the only surface that can answer WHICH step had nothing behind it.
//
// Three legs, and the first is as load-bearing as the other two:
//
//   off (default) -> a scan runs and the ring stays EMPTY. Opt-in has to be
//                    real, because this is written on every scan attempt.
//   on, failing   -> the entry names the step the walk died on and how many
//                    frames it examined before giving up
//   on, matching  -> the entry reports every step and the frame it matched at
//
// The failing leg's numbers are pinned exactly rather than loosely, and the
// fixture is shaped to make that possible: `w=10 lenient` bounds the walk by
// the WINDOW rather than by whatever the ring happens to be retaining, so
// nine examined frames is arithmetic and not a machine-speed reading. Lenient
// also keeps the failure a clean window exhaustion instead of a contiguity
// break on the first neutral row — the two outcomes are different diagnoses
// and this leg is about the first one.
//
// The matching leg swaps in the same move with a window wide enough for the
// harness to drive two octants through it. Two sets rather than one because
// a window tight enough to be deterministic is too tight to steer.
//
// THE CVAR IS GLOBAL and is restored at the top of the final step, before any
// assertion that could fail and skip it.
//============================================================================

class UCk_AutoTest_Intent_ScanDiagnosticsRecordOnlyWhenEnabled : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle                _Owner;
    private FCk_Handle_InputSource    _Source;
    private FCk_Handle_InputBias      _Bias;
    private FCk_Handle_InputButtonMap _Map;
    private FCk_Handle_IntentSampler  _Sampler;
    private FCk_Handle_InputLayer     _Layer;
    private FCk_Handle_IntentMatcher  _Matcher;

    private FKey  _PunchKey;
    private FName _PunchButtonName;

    // The failing leg walks offsets 1..w-1 looking for a step that is never there, so the count it reports is
    // the window minus the terminal's own row.
    private int32 _TightWindowFrames   = 10;
    private int32 _ExpectedFramesExamined = 9;

    private ECk_Intent_Octant _AwaitedOctant = ECk_Intent_Octant::Neutral;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _PunchKey = EKeys::F5;
        _PunchButtonName = _PunchKey.GetKeyName();

        _Owner  = utils_entity_lifetime::Request_CreateEntity(InHandle);
        _Source = utils_input_source::Add(_Owner, FCk_Fragment_InputSource_ParamsData(0));
        _Bias   = utils_input_bias::Add(_Owner, FCk_Fragment_InputBias_ParamsData());

        TArray<FKey> PhysicalButtons;
        PhysicalButtons.Add(_PunchKey);

        _Map     = utils_input_button_map::Add(_Owner, FCk_Fragment_InputButtonMap_ParamsData(PhysicalButtons));
        _Sampler = utils_intent_sampler::Add(_Owner, FCk_Fragment_IntentSampler_ParamsData(120));

        _Layer   = utils_input_layer::Create(_Owner, FCk_Fragment_InputLayer_ParamsData(_Source, 50));

        FCk_Handle LayerEntity = _Layer;
        _Matcher = utils_intent_matcher::Add(LayerEntity, FCk_Fragment_IntentMatcher_ParamsData());

        Assert_True(ck::IsValid(_Sampler), "the sampler must compose for this test to mean anything");
        Assert_True(ck::IsValid(_Matcher), "the matcher must compose onto the layer");

        Add_Step_WaitUntil("the map mints the punch key and the sampler records", n"Check_Recording");
        Add_Step(          "activate the tight-window motion",                    n"Step_SwapTightSet");
        Add_Step_WaitUntil("the swap registers the terminal capture",             n"Check_SetActive");

        Add_Step(          "punch with no motion, diagnostics off",               n"Step_Press");
        Add_Step_WaitUntil("the press reaches a row",                             n"Check_PressRecorded");
        Add_Step_WaitFrames("give a stray entry a chance to be written",          6);
        Add_Step(          "assert the ring stayed empty, then let go",           n"Step_AssertSilentThenRelease");

        Add_Step_WaitUntil("the punch leaves the held set",                       n"Check_Released");
        Add_Step(          "turn diagnostics on",                                 n"Step_EnableDiagnostics");
        Add_Step_WaitUntil("the switch is live",                                  n"Check_DiagnosticsEnabled");

        // The exact frames-examined assertion needs the WINDOW to be the binding constraint, not
        // retention: the walk clamps to the rows the ring actually holds, so the ring must already
        // carry a full tight window of rows behind the press.
        Add_Step_WaitUntil("the ring holds a full tight window of rows",          n"Check_RingWarm");
        Add_Step(          "punch with no motion again",                          n"Step_Press");
        Add_Step_WaitUntil("the failed scan is filed",                            n"Check_OneEntry");
        Add_Step(          "assert it names the step and the frames examined",    n"Step_AssertFailure");

        Add_Step_WaitUntil("the punch leaves the held set",                       n"Check_Released");
        Add_Step(          "activate the wide-window motion",                     n"Step_SwapWideSet");
        Add_Step_WaitUntil("the swap registers the terminal capture",             n"Check_SetActive");
        Add_Step(          "drive the stick to S",                                n"Step_DriveSouth");
        Add_Step_WaitUntil("the record reads S",                                  n"Check_AwaitedOctant");
        Add_Step(          "drive the stick to SE",                               n"Step_DriveSouthEast");
        Add_Step_WaitUntil("the record reads SE",                                 n"Check_AwaitedOctant");
        Add_Step(          "punch with the motion behind it",                     n"Step_Press");
        Add_Step_WaitUntil("the matching scan is filed",                          n"Check_TwoEntries");
        Add_Step(          "restore the switch, then assert the match",           n"Step_AssertMatch");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SwapTightSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoSwap("2 3 P w=10 lenient");
    }

    UFUNCTION()
    private void Step_SwapWideSet(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoSwap("2 3 P w=90 lenient");
    }

    UFUNCTION()
    private void Step_Press(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        DoInject(ECk_InputSource_EventType::Pressed);
    }

    UFUNCTION()
    private void Step_AssertSilentThenRelease(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_intent_matcher::Get_ScanDiagnosticsEnabled(),
            "the switch is off unless somebody turns it on — a ring written by default is not opt-in");

        Assert_Equals_Int(utils_intent_matcher::Get_ScanDiagnostics(_Matcher).Num(), 0,
            "a scan really did run on that press, and it wrote nothing because recording was off");

        DoInject(ECk_InputSource_EventType::Released);
    }

    UFUNCTION()
    private void Step_EnableDiagnostics(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Set_CVarForTest(n"ck.Intent.RecordScanDiagnostics", "1");
    }

    UFUNCTION()
    private void Step_AssertFailure(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Released first so the early-return guards below can never leave the key wedged for the
        // steps that follow — the asserts read the ring, not the held state, so order is free.
        DoInject(ECk_InputSource_EventType::Released);

        TArray<FCk_Intent_ScanDiagnostic> Entries = utils_intent_matcher::Get_ScanDiagnostics(_Matcher);

        Assert_Equals_Int(Entries.Num(), 1,
            "one press, one scan attempt, one entry");

        if (Entries.Num() != 1)
        { return; }

        auto Entry = Entries[0];

        Assert_True(Entry.Get_IntentName() == n"AS_Diag_Motion",
            "the entry names the move that did not come out");

        Assert_True(Entry.Get_Outcome() == ECk_Intent_ScanOutcome::FailedAtStep,
            "the scan failed, and the ring records both outcomes rather than only the interesting one");

        Assert_Equals_Int(Entry.Get_TerminalFrame(), DoFind_LatestPressFrame(),
            "the entry is anchored on the row that carried the press it was scanning back from");

        Assert_Equals_Int(Entry.Get_FailedStepIndex(), 1,
            "the terminal was satisfied by the press, so the walk died seeking the step before it");

        TArray<FCk_Intent_ScanStepDiagnostic> Steps = Entry.Get_Steps();

        Assert_Equals_Int(Steps.Num(), 2,
            "the walk has nothing to say about the step it never got to look for");

        if (Steps.Num() != 2)
        { return; }

        Assert_Equals_Int(Steps[0].Get_StepIndex(), 2,
            "steps are in WALK order, so the terminal comes first");
        Assert_True(Steps[0].Get_Outcome() == ECk_Intent_ScanStepOutcome::Matched,
            "the punch itself was fine — that is exactly what makes this a near miss rather than a wrong button");
        Assert_Equals_Int(Steps[0].Get_FramesExamined(), 1,
            "a terminal is tested against the press row and nowhere else");

        Assert_Equals_Int(Steps[1].Get_StepIndex(), 1,
            "the next step back is the one the walk died on");
        Assert_True(Steps[1].Get_Outcome() == ECk_Intent_ScanStepOutcome::WindowExhausted,
            "the stick was never moved, and a lenient move tolerates every intervening row — so the walk ran out of window rather than breaking contiguity");
        Assert_Equals_Int(Steps[1].Get_MatchedAtFrame(), -1,
            "a step that never matched names no frame");
        Assert_Equals_Int(Steps[1].Get_FramesExamined(), _ExpectedFramesExamined,
            "it spent the whole window looking: every row the window covers except the terminal's own");
    }

    UFUNCTION()
    private void Step_DriveSouth(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AwaitedOctant = ECk_Intent_Octant::S;
        DoDriveAxes(0.0f, -0.9f);
    }

    UFUNCTION()
    private void Step_DriveSouthEast(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _AwaitedOctant = ECk_Intent_Octant::SE;
        DoDriveAxes(0.7f, -0.7f);
    }

    UFUNCTION()
    private void Step_AssertMatch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Set_CVarForTest(n"ck.Intent.RecordScanDiagnostics", "0");

        TArray<FCk_Intent_ScanDiagnostic> Entries = utils_intent_matcher::Get_ScanDiagnostics(_Matcher);

        Assert_Equals_Int(Entries.Num(), 2,
            "the ring is newest-first and keeps what came before");

        if (Entries.Num() != 2)
        { return; }

        auto Entry = Entries[0];

        Assert_True(Entry.Get_Outcome() == ECk_Intent_ScanOutcome::Matched,
            "the motion was behind the press this time");
        Assert_Equals_Int(Entry.Get_FailedStepIndex(), -1,
            "a matched scan died on no step");

        TArray<FCk_Intent_ScanStepDiagnostic> Steps = Entry.Get_Steps();

        Assert_Equals_Int(Steps.Num(), 3,
            "every step of the definition was walked and every one of them is reported");

        if (Steps.Num() != 3)
        { return; }

        Assert_Equals_Int(Steps[0].Get_StepIndex(), 2, "walk order: the terminal");
        Assert_Equals_Int(Steps[1].Get_StepIndex(), 1, "then the direction before it");
        Assert_Equals_Int(Steps[2].Get_StepIndex(), 0, "then the one before that");

        Assert_True(Steps[0].Get_Outcome() == ECk_Intent_ScanStepOutcome::Matched &&
                    Steps[1].Get_Outcome() == ECk_Intent_ScanStepOutcome::Matched &&
                    Steps[2].Get_Outcome() == ECk_Intent_ScanStepOutcome::Matched,
            "a matched scan matched all of them");

        Assert_True(Steps[0].Get_MatchedAtFrame() > Steps[1].Get_MatchedAtFrame(),
            "the walk runs backwards in time, so each step matched on an earlier row than the one after it");
        Assert_True(Steps[1].Get_MatchedAtFrame() > Steps[2].Get_MatchedAtFrame(),
            "and the first step of the move is the oldest row of the three");

        Assert_True(Steps[2].Get_FramesExamined() > 0,
            "reaching the oldest step cost the walk rows, and the count is what a reader compares against the window");
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
    private void Check_RingWarm(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_FrameCount(_Sampler) >= 12);
    }

    UFUNCTION()
    private void Check_SetActive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_HasActiveSet(_Matcher) &&
                utils_intent_matcher::Get_RegisteredCaptureKeys(_Matcher).Contains(_PunchKey));
    }

    UFUNCTION()
    private void Check_PressRecorded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoFind_LatestPressFrame() >= 0);
    }

    UFUNCTION()
    private void Check_Released(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!DoContainsPunch(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Held()));
    }

    UFUNCTION()
    private void Check_DiagnosticsEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_ScanDiagnosticsEnabled());
    }

    UFUNCTION()
    private void Check_OneEntry(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_ScanDiagnostics(_Matcher).Num() >= 1);
    }

    UFUNCTION()
    private void Check_TwoEntries(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_matcher::Get_ScanDiagnostics(_Matcher).Num() >= 2);
    }

    UFUNCTION()
    private void Check_AwaitedOctant(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_intent_sampler::Get_LatestFrame(_Sampler).Get_Octant() == _AwaitedOctant);
    }

    //------------------------------------------------------------------------

    private void DoSwap(const FString& InNotation)
    {
        auto Parsed = utils_intent_grammar::Parse(InNotation, n"AS_Diag_Motion", 100, FGameplayTag());

        Assert_True(Parsed.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture notation must parse before the bake can mean anything");

        TArray<FCk_Intent_Definition> Definitions;
        Definitions.Add(Parsed.Get_Definition());

        TArray<FCk_Intent_ButtonNameRow> Rows;
        Rows.Add(FCk_Intent_ButtonNameRow(n"P", DoMake_PhysicalButton(_PunchKey)));

        auto Baked = utils_intent_grammar::Bake(Definitions, Rows, 3);

        Assert_True(Baked.Get_Outcome() == ECk_SucceededFailed::Succeeded,
            "the fixture set must compile before the matcher can run it");

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()));
    }

    private FCk_Input_ButtonId DoMake_PhysicalButton(FKey InKey)
    {
        return FCk_Input_ButtonId(ECk_Input_ButtonTier::Physical, InKey.GetKeyName());
    }

    private void DoDriveAxes(float InX, float InY)
    {
        DoInjectAxis(EKeys::Gamepad_LeftX, InX);
        DoInjectAxis(EKeys::Gamepad_LeftY, InY);
    }

    private void DoInjectAxis(FKey InAxisKey, float InAnalogValue)
    {
        auto Event = FCk_InputSource_RawEvent(
            ECk_InputSource_DeviceClass::Gamepad,
            InAxisKey,
            ECk_InputSource_EventType::AnalogAxis);

        Event.Set_AnalogValue(InAnalogValue);

        utils_input_source::Request_InjectRawEvent(_Source,
            FCk_Request_InputSource_InjectRawEvent(Event));
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

    private bool DoContainsPunch(const TArray<FCk_Input_ButtonId>& InButtons)
    {
        for (auto Index = 0; Index < InButtons.Num(); Index++)
        {
            if (InButtons[Index].Get_Tier() != ECk_Input_ButtonTier::Physical)
            { continue; }

            if (InButtons[Index].Get_Name() == _PunchButtonName)
            { return true; }
        }

        return false;
    }

    private int32 DoFind_LatestPressFrame()
    {
        auto Count = utils_intent_sampler::Get_FrameCount(_Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(_Sampler, Offset);

            if (DoContainsPunch(Row.Get_Pressed()))
            { return Row.Get_FrameIndex(); }
        }

        return -1;
    }
}
