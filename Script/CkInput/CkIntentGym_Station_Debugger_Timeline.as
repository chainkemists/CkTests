// Language=angelscript

//============================================================================
// CK INTENT DEBUGGER GYM — TIMELINE AND EPISODES STATION
//============================================================================
//
// A press that has to wait is the only thing the timeline's BLOCKED lane ever
// draws, and it is not something a viewer can produce by accident. This station
// makes it producible on demand, from BOTH causes, with one button each:
//
//   the CHORD half  a lone press of the first chord button might still be half
//                   of a pair that has not arrived, so the wait is the chord
//                   window and it ends the moment the partner lands.
//   the HOLD half   a tap and a hold on one button cannot be told apart at the
//                   press, so the wait is the hold threshold and it ends when
//                   the threshold is reached or the button comes up.
//
// WHAT THE PANEL COUNTS IS NOT WHAT THE LANE DRAWS, AND THE DIFFERENCE IS
// PRINTED. One episode puts EVERY candidate on its terminal into `Pending`, so
// two moves sharing a button read as two Pending rows for one marker. The panel
// therefore prints both numbers and says which one the BLOCKED lane should
// agree with — a station that printed only the row count would have a viewer
// chasing a discrepancy that is the module working correctly.
//
// NOTHING HERE IS RECOMPUTED. Pending is read off the phase surface, the frame
// gaps are two recorded frames subtracted, and the wait lengths are read off the
// COMPILED SET rather than restated from the notation. The debugger reads the
// same four things, which is what makes disagreeing with it meaningful.
//============================================================================

class UCk_EntityScript_IntentGym_Debugger_Timeline : UCk_GenericEntityScript_UE
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

    // Read off the compiled artifact at bake time, not asserted from memory: the
    // set is the thing that decides whether a press waits and for how long, so
    // the panel quotes it rather than restating what the notation was supposed
    // to mean.
    private int32 _ChordVerdict_Chord = -1;
    private int32 _ChordVerdict_Hold  = -1;
    private int32 _HoldVerdict_Hold   = -1;
    private int32 _HoldVerdict_Chord  = -1;

    private FCkIntentGym_Attempt _ChordAttempt;
    private FCkIntentGym_Attempt _HoldAttempt;
    private int32                _ReportTicks = 0;

    // The most episodes this station has had open at once since it armed. A
    // viewer comparing markers to a live number would be comparing a number that
    // has already gone back to zero by the time they look at the other window.
    private int32 _PeakBlockedTerminals = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_Debugger_Timeline);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Debugger_Timeline_Arm);

        _StepConfig.Description = "Two ways to make a press wait, and the lane that draws them.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Timeline_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Timeline_Await,  "Waiting for you to open a wait"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Timeline_Report, "Reading back both frame gaps"));

        return ECk_EntityScript_ConstructionFlow::Finished;
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
        DoTrackEpisodes();
        DoTryRecordAttempts();
        DoAdvanceSteps();
        DoRender();
    }

    //------------------------------------------------------------------------
    // Composition
    //------------------------------------------------------------------------

    // Composed from the TICK rather than from DoConstruct because the player's
    // input source does not exist until the local player has a PlayerController,
    // and the subsystem gives up quietly until it does. Idempotent at every
    // step, so "compose it the moment it appears" is the only shape that cannot
    // race the engine's startup order.
    private void DoTryCompose()
    {
        if (intent_gym::Request_EnsureSourceComposed() == false)
        { return; }

        if (ck::Is_NOT_Valid(_Matcher))
        {
            auto Source = intent_gym::TryGet_PlayerSource();
            auto SelfEntity = ck::ToEntity(this);

            _Layer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Debugger_Timeline));

            if (ck::Is_NOT_Valid(_Layer))
            { return; }

            auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
            MatcherParams.Set_LatchDecayFrames(intent_gym::k_LatchDecayFrames);

            FCk_Handle LayerEntity = _Layer;
            _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);
        }

        if (ck::Is_NOT_Valid(_Matcher) || _SwapRequested)
        { return; }

        // The map is EMPTY on the calling stack of Add and fills in when its
        // derivation request drains, so the swap waits for every terminal to be
        // minted rather than being rejected for a key that only looks
        // unresolvable — the swap resolves all of them and rejects the WHOLE set
        // if a single one answers no key.
        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        { return; }

        auto ChordAReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_ChordA).Num() > 0;
        auto ChordBReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_ChordB).Num() > 0;
        auto HoldReady   = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_Hold).Num() > 0;

        if (ChordAReady == false || ChordBReady == false || HoldReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_debugger_moves::MoveTable_Debugger_Timeline.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"TA", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_ChordA)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"TB", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_ChordB)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"TH", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Hold)));

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

        auto Set = Baked.Get_CompiledSet();

        auto ChordVerdict = utils_intent_grammar::Get_DeferralVerdict(
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_ChordA));
        auto HoldVerdict = utils_intent_grammar::Get_DeferralVerdict(
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Hold));

        _ChordVerdict_Chord = ChordVerdict.Get_ChordMemberFrames();
        _ChordVerdict_Hold  = ChordVerdict.Get_HoldSiblingFrames();
        _HoldVerdict_Hold   = HoldVerdict.Get_HoldSiblingFrames();
        _HoldVerdict_Chord  = HoldVerdict.Get_ChordMemberFrames();

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Set),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

        _SwapRequested = true;
    }

    //------------------------------------------------------------------------
    // Reading the result
    //------------------------------------------------------------------------

    private void DoTrackEpisodes()
    {
        auto Blocked = Get_BlockedTerminalCount();

        if (Blocked > _PeakBlockedTerminals)
        { _PeakBlockedTerminals = Blocked; }
    }

    private void DoTryRecordAttempts()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        // The chord's terminal is two buttons; the gap is measured from the
        // AMBIGUOUS one, because that is the press whose answer was held back.
        auto ChordName = intent_gym::k_Key_Debugger_ChordA.GetKeyName();
        auto HoldName  = intent_gym::k_Key_Debugger_Hold.GetKeyName();

        auto ChordLanded =
            intent_gym::Request_RecordAttempt(_ChordAttempt, _Matcher, Sampler, n"Gym_Dbg_Chord_Pair", ChordName) ||
            intent_gym::Request_RecordAttempt(_ChordAttempt, _Matcher, Sampler, n"Gym_Dbg_Chord_Bare", ChordName);

        auto HoldLanded =
            intent_gym::Request_RecordAttempt(_HoldAttempt, _Matcher, Sampler, n"Gym_Dbg_Hold_Full", HoldName) ||
            intent_gym::Request_RecordAttempt(_HoldAttempt, _Matcher, Sampler, n"Gym_Dbg_Hold_Tap",  HoldName);

        if (ChordLanded || HoldLanded)
        { _ReportTicks = 0; }
    }

    private bool Get_IsPending(FName InIntentName)
    {
        return utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, InIntentName) == ECk_Intent_Phase::Pending;
    }

    private int32 Get_PendingRowCount()
    {
        if (ck::Is_NOT_Valid(_Matcher))
        { return 0; }

        auto Count = 0;

        if (Get_IsPending(n"Gym_Dbg_Chord_Pair")) { Count++; }
        if (Get_IsPending(n"Gym_Dbg_Chord_Bare")) { Count++; }
        if (Get_IsPending(n"Gym_Dbg_Hold_Full"))  { Count++; }
        if (Get_IsPending(n"Gym_Dbg_Hold_Tap"))   { Count++; }

        return Count;
    }

    // One episode belongs to one TERMINAL, and every candidate on that terminal
    // goes Pending together — so grouping the Pending rows by the button they
    // end on is what turns the phase surface into the number the BLOCKED lane
    // draws. This groups recorded phases; it computes nothing the module has not
    // already decided.
    private int32 Get_BlockedTerminalCount()
    {
        if (ck::Is_NOT_Valid(_Matcher))
        { return 0; }

        auto Count = 0;

        if (Get_IsPending(n"Gym_Dbg_Chord_Pair") || Get_IsPending(n"Gym_Dbg_Chord_Bare"))
        { Count++; }

        if (Get_IsPending(n"Gym_Dbg_Hold_Full") || Get_IsPending(n"Gym_Dbg_Hold_Tap"))
        { Count++; }

        return Count;
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    // The transition is the PLAYER, so the station drives the graph off what it
    // just read rather than off a dwell that would advance the panel while
    // somebody was still mid-motion.
    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Debugger_ChordA);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Debugger_Timeline_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Timeline_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Debugger_Timeline_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Timeline_Await);
            return;
        }

        auto BothSeen = _ChordAttempt.Recorded && _HoldAttempt.Recorded;

        if (_ReportTicks == 0 && BothSeen && Current == UCk_IntentGym_Step_Debugger_Timeline_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Timeline_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Debugger_Timeline_Report)
        { return; }

        _ReportTicks++;

        if (_ReportTicks > 90)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Timeline_Await); }
    }

    //------------------------------------------------------------------------
    // The panel
    //------------------------------------------------------------------------

    private void DoRender()
    {
        auto SelfEntity = ck::ToEntity(this);
        auto Lines = TArray<FCkGym_ColoredLine>();

        intent_gym::Add_SmSteps(Lines, _StepConfig, _StepMachine);
        intent_gym::Add_Spacer(Lines, gym_palette::White);
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Debugger_ChordA, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_WhatTheViewShouldShow(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_LiveEpisodes(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_BakedVerdicts(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_ChordColumn(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_HoldColumn(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto ChordA = intent_gym::Format_Key(intent_gym::k_Key_Debugger_ChordA);
        auto ChordB = intent_gym::Format_Key(intent_gym::k_Key_Debugger_ChordB);
        auto HoldKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Hold);
        auto Threshold = intent_gym::k_Debugger_HoldFrames;

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Tap {ChordA} on its own. It hesitates, then answers.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Tap {ChordA} and {ChordB} together. The hesitation ends early.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Press {HoldKey} and keep holding. At {Threshold} frames the held move", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  answers on its own; let go early and the tap answers instead.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  This station is keyboard-only - no stick is needed for any of it.", gym_palette::White);
    }

    private void Add_WhatTheViewShouldShow(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto ChordA = intent_gym::Format_Key(intent_gym::k_Key_Debugger_ChordA);
        auto Priority = intent_gym::k_LayerPriority_Debugger_Timeline;

        intent_gym::Add_DebuggerViewHeader(OutLines, "TIMELINE VIEW");
        intent_gym::Add_Line(OutLines, f"  Select this station's layer (priority {Priority}) on the left first.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  EXPECT an amber marker on the BLOCKED lane naming {ChordA} on the frame", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  you tap it, and a phase span opening on that move's own lane at the", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  same frame - one lane per move in the set, four of them.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  CLICK the marker: the timeline scrubs to that logic frame, and it is", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  the PRESS FRAME printed further down this panel.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  The axis counts LOGIC FRAMES, not seconds, so it and this panel are", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  quoting the same numbers even through a hitch.", gym_palette::White);
    }

    private void Add_LiveEpisodes(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHAT IS BEING HELD OPEN RIGHT NOW", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        auto Rows = Get_PendingRowCount();
        auto Terminals = Get_BlockedTerminalCount();
        auto Colour = Terminals > 0 ? gym_palette::Amber : gym_palette::Grey;

        intent_gym::Add_Line(OutLines, f"  moves sitting Pending      {Rows}", Colour);
        intent_gym::Add_Line(OutLines, f"  buttons actually blocked   {Terminals}", Colour);
        intent_gym::Add_Line(OutLines, f"  most blocked at once so far  {_PeakBlockedTerminals}", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  The BLOCKED lane draws one marker per EPISODE, and an episode belongs", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  to a button - so it is the second number the lane agrees with. Every", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  move on a blocked button goes Pending together, which is why the", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  first number is larger and is not a discrepancy.", gym_palette::White);
    }

    private void Add_BakedVerdicts(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Window = intent_gym::k_ChordWindowFrames;
        auto Threshold = intent_gym::k_Debugger_HoldFrames;

        intent_gym::Add_Line(OutLines, "WHAT THE COMPILED SET SAYS EACH BUTTON MUST DO", gym_palette::White);

        if (_ChordVerdict_Chord < 0)
        {
            intent_gym::Add_Line(OutLines, "  (the compiled set has not been read back yet)", gym_palette::Grey);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "chord button - frames it waits on a chord",
            f"{Window}", f"{_ChordVerdict_Chord}", _ChordVerdict_Chord == Window);
        intent_gym::Add_Verdict(OutLines, "chord button - frames it waits on a hold ",
            "0", f"{_ChordVerdict_Hold}", _ChordVerdict_Hold == 0);
        intent_gym::Add_Verdict(OutLines, "hold button  - frames it waits on a hold ",
            f"{Threshold}", f"{_HoldVerdict_Hold}", _HoldVerdict_Hold == Threshold);
        intent_gym::Add_Verdict(OutLines, "hold button  - frames it waits on a chord",
            "0", f"{_HoldVerdict_Chord}", _HoldVerdict_Chord == 0);
    }

    private void Add_ChordColumn(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Window = intent_gym::k_ChordWindowFrames;

        intent_gym::Add_Line(OutLines, "THE CHORD EPISODE", gym_palette::White);

        if (_ChordAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames it actually waited", f"{Window} or fewer");
            return;
        }

        auto MoveName = _ChordAttempt.IntentName;
        intent_gym::Add_Line(OutLines, f"  move that came out       {MoveName}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  press landed on frame    {_ChordAttempt.PressFrame}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  move came out on frame   {_ChordAttempt.CompletionFrame}", gym_palette::White);

        if (_ChordAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so this attempt cannot", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  be measured. Try again.", gym_palette::Amber);
            return;
        }

        // The partner arriving and the window expiring are the two ways the wait
        // ends, and they are different verdicts.
        if (MoveName == n"Gym_Dbg_Chord_Pair")
        {
            intent_gym::Add_Verdict(OutLines, "frames it actually waited",
                f"0..{Window} (partner arrived)", f"{_ChordAttempt.DeferralFrames}",
                _ChordAttempt.DeferralFrames >= 0 && _ChordAttempt.DeferralFrames <= Window);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames it actually waited",
            f"{Window} or more (no partner)", f"{_ChordAttempt.DeferralFrames}",
            _ChordAttempt.DeferralFrames >= Window);
    }

    private void Add_HoldColumn(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Threshold = intent_gym::k_Debugger_HoldFrames;
        auto Latest = Threshold - 1;

        intent_gym::Add_Line(OutLines, "THE HOLD EPISODE", gym_palette::White);

        if (_HoldAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames it actually waited", f"{Threshold} exactly, or 0..{Latest} if you let go");
            return;
        }

        auto MoveName = _HoldAttempt.IntentName;
        intent_gym::Add_Line(OutLines, f"  move that came out       {MoveName}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  press landed on frame    {_HoldAttempt.PressFrame}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  move came out on frame   {_HoldAttempt.CompletionFrame}", gym_palette::White);

        if (_HoldAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so this attempt cannot", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  be measured. Try again.", gym_palette::Amber);
            return;
        }

        auto Gap = _HoldAttempt.DeferralFrames;

        if (MoveName == n"Gym_Dbg_Hold_Full")
        {
            intent_gym::Add_Verdict(OutLines, "frames it actually waited",
                f"{Threshold} exactly", f"{Gap}", Gap == Threshold);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames it actually waited",
            f"0..{Latest} (you let go first)", f"{Gap}", Gap >= 0 && Gap < Threshold);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_Dbg_Chord_Pair", "both chord buttons ");
        Add_PhaseRow(OutLines, n"Gym_Dbg_Chord_Bare", "first chord button ");
        Add_PhaseRow(OutLines, n"Gym_Dbg_Hold_Full",  "hold it            ");
        Add_PhaseRow(OutLines, n"Gym_Dbg_Hold_Tap",   "tap it             ");

        intent_gym::Add_Line(OutLines, "  These four names are the four intent lanes on the timeline, in this", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  order. A span drawn there is a phase that stood; a phase here with no", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  span behind it happened before the debugger window was opened.", gym_palette::White);
    }

    // Pending is the honest reading of a press the matcher has not chosen for
    // yet, and on THIS station it is the thing the viewer is meant to catch — so
    // it is amber, the colour of a value legitimately in flight, never red.
    private void Add_PhaseRow(TArray<FCkGym_ColoredLine>& OutLines, FName InIntentName, FString InLabel)
    {
        auto Phase = utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, InIntentName);
        auto Colour = gym_palette::Grey;

        if (Phase == ECk_Intent_Phase::Completed) { Colour = gym_palette::Green; }
        if (Phase == ECk_Intent_Phase::Pending)   { Colour = gym_palette::Amber; }
        if (Phase == ECk_Intent_Phase::Failed)    { Colour = gym_palette::Amber; }

        intent_gym::Add_Line(OutLines, f"  {InLabel}  ->  {intent_gym::Format_Phase(Phase)}", Colour);
    }
}
