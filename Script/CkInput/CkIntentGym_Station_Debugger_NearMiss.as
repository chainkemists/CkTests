// Language=angelscript

//============================================================================
// CK INTENT DEBUGGER GYM — NEAR-MISS CORPUS STATION
//============================================================================
//
// The near-miss view is a LIST, and a list with one row in it teaches nothing
// about reading a list. This station fills it, on one press, with three rows a
// viewer can tell apart without knowing anything about the moves — because the
// three moves are the same motion three times over and differ ONLY in how many
// frames the walk is allowed:
//
//   tight   eight frames. An unhurried quarter-circle cannot beat it, and it
//           gives up having read the fewest rows of the three.
//   medium  twenty. It gives up too, later, having read more.
//   open    no declared window, so the walk is bounded only by what the ring
//           still holds. It is the one that matches, and it is the move that
//           comes out.
//
// SO ONE MOTION PRODUCES A DIAGNOSIS PER CANDIDATE, IN PRIORITY ORDER, and the
// frames-examined column climbs down the list. That column is the point: it is
// how many rows the WALK read, bounded by `w=` and by the ring's retention — not
// how late the player was — and three rows differing only in their window is the
// cheapest way to make that concrete.
//
// THE SWITCH IS GLOBAL AND IS TURNED OFF ON THE WAY OUT.
// `ck.Intent.RecordScanDiagnostics` writes an entry per scan ATTEMPT on every
// matcher in the session, so a gym that left it on would be paying for rings
// nobody reads (CkIntent/CLAUDE.md anti-pattern 33). It is armed when this
// station arms and cleared in DoEndPlay.
//
// FAILING HERE IS THE EXERCISE, NOT A DEFECT. Two exhausted windows out of three
// is the correct answer to an unhurried motion, so those rows are white and
// explained in cyan. Red on this panel means a press the ring owes an answer for
// and did not give.
//============================================================================

class UCk_EntityScript_IntentGym_Debugger_NearMiss : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    private FCk_Handle_InputLayer    _Layer;
    private FCk_Handle_IntentMatcher _Matcher;

    private FCk_Handle_StateMachine _StepMachine;
    private FCkGym_SmConfig         _StepConfig;

    private bool    _SwapRequested = false;
    private bool    _SwapRejected  = false;
    private FString _AuthoringError;

    private bool  _DiagnosticsArmed = false;
    private int32 _LastPressFrame   = -1;
    private int32 _TicksSincePress  = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_Debugger_NearMiss);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Debugger_Corpus_Arm);

        _StepConfig.Description = "One motion, three windows, and a list you can read down.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Corpus_Arm,    "Load the set and start recording"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Corpus_Await,  "Waiting for an unhurried motion"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Corpus_Report, "Reading back the three verdicts"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // The switch outlives PIE, so clearing it belongs to the one hook that runs
    // whether the viewer cycled to the next gym or stopped the session outright.
    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 0");
    }

    UFUNCTION()
    private void OnSwapCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SwapRejected = InResult != ECk_Request_OperationResult::Succeeded;
    }

    UFUNCTION()
    private void OnDisplayTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DoTryCompose();
        DoTrackPresses();
        DoAdvanceSteps();
        DoRender();
    }

    //------------------------------------------------------------------------
    // Composition
    //------------------------------------------------------------------------

    private void DoTryCompose()
    {
        if (intent_gym::Request_EnsureSourceComposed() == false)
        { return; }

        if (ck::Is_NOT_Valid(_Matcher))
        {
            auto Source = intent_gym::TryGet_PlayerSource();
            auto SelfEntity = ck::ToEntity(this);

            _Layer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Debugger_NearMiss));

            if (ck::Is_NOT_Valid(_Layer))
            { return; }

            auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
            MatcherParams.Set_LatchDecayFrames(intent_gym::k_LatchDecayFrames);

            FCk_Handle LayerEntity = _Layer;
            _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);
        }

        if (ck::Is_NOT_Valid(_Matcher) || _SwapRequested)
        { return; }

        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        { return; }

        auto KeyReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_Corpus_Kb).Num() > 0;
        auto PadReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_Corpus_Pad).Num() > 0;

        if (KeyReady == false || PadReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_debugger_moves::MoveTable_Debugger_NearMiss.Rows;

        TArray<FCk_Intent_Definition> Definitions;

        for (auto Index = 0; Index < Rows.Num(); Index++)
        {
            auto Row = Rows[Index];
            auto Parsed = utils_intent_grammar::Parse(Row._Notation, Row._Name, Row._Priority, FGameplayTag());

            if (Parsed.Get_Outcome() != ECk_SucceededFailed::Succeeded)
            {
                auto MoveName = Row._Name;
                auto Notation = Row._Notation;
                auto Error = Parsed.Get_Error();
                _AuthoringError = f"move '{MoveName}' ({Notation}) rejected as {Error :n}";
                _SwapRequested = true;
                _SwapRejected = true;
                return;
            }

            Definitions.Add(Parsed.Get_Definition());
        }

        TArray<FCk_Intent_ButtonNameRow> ButtonRows;
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"NC",  intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Corpus_Kb)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"NCP", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Corpus_Pad)));

        auto Baked = utils_intent_grammar::Bake(Definitions, ButtonRows, intent_gym::k_ChordWindowFrames);

        if (Baked.Get_Outcome() != ECk_SucceededFailed::Succeeded)
        {
            auto Error = Baked.Get_Error();
            auto Offending = Baked.Get_OffendingIntent();
            _AuthoringError = f"the set did not compile: {Error :n} on move '{Offending}'";
            _SwapRequested = true;
            _SwapRejected = true;
            return;
        }

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Baked.Get_CompiledSet()),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

        _SwapRequested = true;
    }

    //------------------------------------------------------------------------
    // Watching for a press the ring owes an answer for
    //------------------------------------------------------------------------

    private void DoTrackPresses()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        auto KeyPress = intent_gym::Get_LatestPressFrame(Sampler, intent_gym::k_Key_Debugger_Corpus_Kb.GetKeyName());
        auto PadPress = intent_gym::Get_LatestPressFrame(Sampler, intent_gym::k_Key_Debugger_Corpus_Pad.GetKeyName());
        auto Newest = PadPress > KeyPress ? PadPress : KeyPress;

        if (Newest >= 0 && Newest != _LastPressFrame)
        {
            _LastPressFrame = Newest;
            _TicksSincePress = 0;
            return;
        }

        if (_LastPressFrame >= 0)
        { _TicksSincePress++; }
    }

    // The ring is newest-first, and every entry a single press produced carries
    // that press's terminal frame — so the run of entries at the top sharing one
    // terminal frame IS the corpus of the last attempt. Nothing is recomputed:
    // this groups recorded entries by a value they already carry.
    private int32 Get_CorpusCount(TArray<FCk_Intent_ScanDiagnostic>& InEntries)
    {
        if (InEntries.Num() == 0)
        { return 0; }

        auto TerminalFrame = InEntries[0].Get_TerminalFrame();
        auto Count = 0;

        for (auto Index = 0; Index < InEntries.Num(); Index++)
        {
            if (InEntries[Index].Get_TerminalFrame() != TerminalFrame)
            { return Count; }

            Count++;
        }

        return Count;
    }

    // The walk stops where it died, so the LAST recorded step is the one that
    // ran out — and its own frames-read is the number the debugger's row shows
    // for that move. One recorded value, not a total this panel invented.
    private int32 Get_FramesReadWhereItStopped(const FCk_Intent_ScanDiagnostic&in InEntry)
    {
        TArray<FCk_Intent_ScanStepDiagnostic> Steps = InEntry.Get_Steps();

        if (Steps.Num() == 0)
        { return -1; }

        return Steps[Steps.Num() - 1].Get_FramesExamined();
    }

    private bool Get_IsTightMove(FName InName)
    {
        return InName == n"Gym_Dbg_Corpus_Tight_Kb" || InName == n"Gym_Dbg_Corpus_Tight_Pad";
    }

    private bool Get_IsMediumMove(FName InName)
    {
        return InName == n"Gym_Dbg_Corpus_Medium_Kb" || InName == n"Gym_Dbg_Corpus_Medium_Pad";
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Debugger_Corpus_Kb);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Debugger_Corpus_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Corpus_Arm); }
            return;
        }

        // Armed is the moment the ring has something to record, so it is the
        // moment the switch goes on — not construct, which would arm a recorder
        // for a matcher with no set.
        if (_DiagnosticsArmed == false)
        {
            System::ExecuteConsoleCommand("ck.Intent.RecordScanDiagnostics 1");
            _DiagnosticsArmed = true;
        }

        if (Current == UCk_IntentGym_Step_Debugger_Corpus_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Corpus_Await);
            return;
        }

        auto HasEntry = utils_intent_matcher::Get_ScanDiagnostics(_Matcher).Num() > 0;

        if (HasEntry && _TicksSincePress < 90 && Current == UCk_IntentGym_Step_Debugger_Corpus_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Corpus_Report);
            return;
        }

        if (Current == UCk_IntentGym_Step_Debugger_Corpus_Report && _TicksSincePress > 180)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Corpus_Await); }
    }

    //------------------------------------------------------------------------
    // The panel
    //------------------------------------------------------------------------

    private void DoRender()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto Sampler = intent_gym::TryGet_Sampler();
        auto Lines = TArray<FCkGym_ColoredLine>();

        intent_gym::Add_SmSteps(Lines, _StepConfig, _StepMachine);
        intent_gym::Add_Spacer(Lines, gym_palette::White);
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Debugger_Corpus_Kb, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_WhatTheViewShouldShow(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        intent_gym::Add_LiveInput(Lines, Sampler);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Recorder(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Corpus(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto PadKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Corpus_Pad);
        auto KbKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Corpus_Kb);
        auto Tight = intent_gym::k_Debugger_Window_Tight;
        auto Medium = intent_gym::k_Debugger_Window_Medium;

        intent_gym::Add_Line(OutLines, "DO THIS - UNHURRIED, ON PURPOSE", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  Roll the LEFT STICK down, down-forward, forward at a comfortable", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  pace, then press {PadKey}. One press, three verdicts: the {Tight}-frame", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  move and the {Medium}-frame move both run out, and the one with no", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  declared window is what comes out.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  Then do it FAST and press again - the tight row flips to Matched and", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  the list gets shorter, because the walk stops at the first move that", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  builds.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  No pad? Press {KbKey} - a keyboard moves no stick, so all three run", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  out and the corpus is the same three rows every time.", gym_palette::White);
    }

    private void Add_WhatTheViewShouldShow(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Tight = intent_gym::k_Debugger_Window_Tight;
        auto Medium = intent_gym::k_Debugger_Window_Medium;

        auto Priority = intent_gym::k_LayerPriority_Debugger_NearMiss;

        intent_gym::Add_DebuggerViewHeader(OutLines, "NEAR MISSES VIEW");
        intent_gym::Add_Line(OutLines, f"  Select this station's layer (priority {Priority}) on the left first -", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  the ring belongs to a matcher, and every station on this gym has one.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  EXPECT three rows at the top of the list naming three DIFFERENT", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  moves, newest first, all three from the one press you just made.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  EXPECT the {Tight}-frame move to read WindowExhausted with FEWER frames", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  examined than the {Medium}-frame one - same motion, smaller allowance.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  The view carries a banner naming the CVar when recording is off, so", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  an empty list is never mistaken for 'the matcher never scanned'.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  The rows below are the same ring, newest first, with the same names.", gym_palette::White);
    }

    private void Add_Recorder(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Enabled = utils_intent_matcher::Get_ScanDiagnosticsEnabled();

        intent_gym::Add_Line(OutLines, "THE RECORDER", gym_palette::White);

        intent_gym::Add_Verdict(OutLines, "recording",
            "yes", intent_gym::Format_Bool(Enabled), Enabled);

        intent_gym::Add_Line(OutLines, "  It is off by default and costs every scan an entry while it is on,", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  so leaving this gym turns it back off.", gym_palette::White);
    }

    private void Add_Corpus(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHAT YOUR LAST PRESS PRODUCED", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        TArray<FCk_Intent_ScanDiagnostic> Entries = utils_intent_matcher::Get_ScanDiagnostics(_Matcher);

        if (Entries.Num() == 0)
        {
            // A press with no entry behind it is the ONE true failure this panel
            // can report — but only once the scan has actually had time to run.
            if (utils_intent_matcher::Get_ScanDiagnosticsEnabled() && _LastPressFrame >= 0 && _TicksSincePress > 60)
            {
                intent_gym::Add_Line(OutLines, "  A press was recorded and the recorder is on, yet the ring is", gym_palette::Red);
                intent_gym::Add_Line(OutLines, "  empty. The scan that answered that press wrote nothing down.", gym_palette::Red);
                return;
            }

            intent_gym::Add_Line(OutLines, "  Nothing attempted yet - do the motion above.", gym_palette::Grey);
            return;
        }

        auto Count = Get_CorpusCount(Entries);
        auto TerminalFrame = Entries[0].Get_TerminalFrame();

        intent_gym::Add_Line(OutLines, f"  press it scanned back from   frame {TerminalFrame}", gym_palette::White);

        auto TightFrames = -1;
        auto MediumFrames = -1;

        for (auto Index = 0; Index < Count; Index++)
        {
            auto Entry = Entries[Index];
            auto MoveName = Entry.Get_IntentName();
            auto Examined = Get_FramesReadWhereItStopped(Entry);
            auto Outcome = Entry.Get_Outcome();

            auto Colour = gym_palette::White;
            if (Outcome == ECk_Intent_ScanOutcome::Matched)
            { Colour = gym_palette::Green; }

            intent_gym::Add_Line(OutLines, f"    {MoveName}  {Outcome :n}  -  {Examined} frames read", Colour);

            if (Get_IsTightMove(MoveName))
            { TightFrames = Examined; }

            if (Get_IsMediumMove(MoveName))
            { MediumFrames = Examined; }
        }

        intent_gym::Add_Verdict(OutLines, "rows behind that one press",
            "1..3", f"{Count}", Count >= 1 && Count <= 3);

        if (TightFrames < 0 || MediumFrames < 0)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "tight read fewer frames than medium", "yes");
        }
        else
        {
            intent_gym::Add_Verdict(OutLines, "tight read fewer frames than medium",
                "yes", intent_gym::Format_Bool(TightFrames <= MediumFrames), TightFrames <= MediumFrames);
        }

        intent_gym::Add_Spacer(OutLines, gym_palette::White);
        Add_NewestSteps(OutLines, Entries[0]);
    }

    // The walk runs backwards and stops where it died, so a part it never got to
    // look for has no row here — inventing one would be reporting work that did
    // not happen.
    private void Add_NewestSteps(TArray<FCkGym_ColoredLine>& OutLines, const FCk_Intent_ScanDiagnostic&in InEntry)
    {
        auto MoveName = InEntry.Get_IntentName();

        intent_gym::Add_Line(OutLines, f"  the newest row in detail - {MoveName}", gym_palette::White);

        TArray<FCk_Intent_ScanStepDiagnostic> Steps = InEntry.Get_Steps();

        if (Steps.Num() == 0)
        {
            intent_gym::Add_Line(OutLines, "    the walk recorded no steps at all", gym_palette::White);
            return;
        }

        for (auto Index = 0; Index < Steps.Num(); Index++)
        {
            auto Step = Steps[Index];
            auto Outcome = Step.Get_Outcome();
            auto Colour = gym_palette::White;

            if (Outcome == ECk_Intent_ScanStepOutcome::Matched)
            { Colour = gym_palette::Green; }

            auto Where = FString("never found");
            if (Step.Get_MatchedAtFrame() >= 0)
            { Where = f"found on frame {Step.Get_MatchedAtFrame()}"; }

            intent_gym::Add_Line(OutLines,
                f"    part {Step.Get_StepIndex()}  {Outcome :n}  -  {Where}, {Step.Get_FramesExamined()} frames read",
                Colour);
        }

        intent_gym::Add_Line(OutLines, "  Frames read is how many rows the WALK looked at, bounded by the move's", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  own window and by what the ring still holds. It is not how late you", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  were - a motion that missed by a hundred frames inside a ten-frame", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  window still reports nine, because nine is all it was allowed to see.", gym_palette::Cyan);
    }
}
