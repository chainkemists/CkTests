// Language=angelscript

//============================================================================
// CK INTENT SOULS GYM — TAP VS HOLD STATION
//============================================================================
//
// One button, two moves, and the only ambiguity in this module that genuinely
// reaches forward. A tap and a hold cannot be told apart at the moment of the
// press — the difference is entirely in what happens NEXT — so the press is
// held open and the panel grades the two boundaries of that wait:
//
//   let go early   the tap wins, and it answers BEFORE the threshold. There is
//                  no hold left that could still come out, so waiting longer
//                  would buy nothing.
//   hold on        the charge wins, and it answers EXACTLY on the threshold
//                  frame. Not the frame after, not "about then" — the module's
//                  own automation test asserts that number as exact frame
//                  arithmetic against the press row, and this panel asserts the
//                  same one against the same two frames.
//
// THE BARE TAP IS IN THE SET ON PURPOSE, AND IT IS WHAT MAKES THE HOLD REAL. A
// `hold=` on a terminal only one intent ends on defers for nothing: the verdict
// needs a rival. A viewer reading "45" off the compiled set below is reading the
// consequence of the two moves sharing this button, not a number somebody typed
// into the matcher.
//
// THE PROGRESS BAR IS NOT THE ASSERTION. The frames-down count is walked out of
// the RECORD's held rows — the physical fact, which keeps counting through
// anything — and it is labelled as display for the reason CkIntent anti-pattern
// 23 gives: the matcher's accumulator is the policy-applied count, it is not
// readable, and a station that graded an outcome from its own timer would agree
// with the module right up until the frame it mattered.
//============================================================================

class UCk_EntityScript_IntentGym_Souls_TapVsHold : UCk_GenericEntityScript_UE
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
    private int32 _Verdict_Hold_Key  = -1;
    private int32 _Verdict_Chord_Key = -1;
    private int32 _Verdict_Hold_Pad  = -1;

    private FCkIntentGym_Attempt _TapAttempt;
    private FCkIntentGym_Attempt _HoldAttempt;
    private int32                _ReportTicks = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_Souls_TapVsHold);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Souls_TapHold_Arm);

        _StepConfig.Description = "A tap and a hold on one button, and the frame each of them answers on.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_TapHold_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_TapHold_Await,  "Waiting for you to tap it and to hold it"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_TapHold_Report, "Reading back both frame gaps"));

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
        DoTryRecordAttempts();
        DoAdvanceSteps();
        DoRender();
    }

    //------------------------------------------------------------------------
    // Composition
    //------------------------------------------------------------------------
    //
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
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Souls_TapVsHold));

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
        // derivation request drains, so the swap waits for BOTH terminals to be
        // minted rather than being rejected for a key that only looks
        // unresolvable — the swap resolves every terminal and rejects the whole
        // set if a single one answers no key.
        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        { return; }

        auto KeyReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Souls_TapHold_Kb).Num() > 0;
        auto PadReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Souls_TapHold_Pad).Num() > 0;

        if (KeyReady == false || PadReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_souls_moves::MoveTable_Souls_TapVsHold.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"TH",  intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_TapHold_Kb)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"THP", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_TapHold_Pad)));

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

        auto KeyVerdict = utils_intent_grammar::Get_DeferralVerdict(
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_TapHold_Kb));
        auto PadVerdict = utils_intent_grammar::Get_DeferralVerdict(
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_TapHold_Pad));

        _Verdict_Hold_Key  = KeyVerdict.Get_HoldSiblingFrames();
        _Verdict_Chord_Key = KeyVerdict.Get_ChordMemberFrames();
        _Verdict_Hold_Pad  = PadVerdict.Get_HoldSiblingFrames();

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Set),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

        _SwapRequested = true;
    }

    //------------------------------------------------------------------------
    // Reading the result
    //------------------------------------------------------------------------

    private void DoTryRecordAttempts()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        auto KeyName = intent_gym::k_Key_Souls_TapHold_Kb.GetKeyName();
        auto PadName = intent_gym::k_Key_Souls_TapHold_Pad.GetKeyName();

        auto TapLanded =
            intent_gym::Request_RecordAttempt(_TapAttempt, _Matcher, Sampler, n"Gym_Souls_Tap_Key", KeyName) ||
            intent_gym::Request_RecordAttempt(_TapAttempt, _Matcher, Sampler, n"Gym_Souls_Tap_Pad", PadName);

        auto HoldLanded =
            intent_gym::Request_RecordAttempt(_HoldAttempt, _Matcher, Sampler, n"Gym_Souls_Hold_Key", KeyName) ||
            intent_gym::Request_RecordAttempt(_HoldAttempt, _Matcher, Sampler, n"Gym_Souls_Hold_Pad", PadName);

        if (TapLanded || HoldLanded)
        { _ReportTicks = 0; }
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Souls_TapHold_Kb);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Souls_TapHold_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_TapHold_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Souls_TapHold_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_TapHold_Await);
            return;
        }

        auto BothSeen = _TapAttempt.Recorded && _HoldAttempt.Recorded;

        if (_ReportTicks == 0 && BothSeen && Current == UCk_IntentGym_Step_Souls_TapHold_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_TapHold_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Souls_TapHold_Report)
        { return; }

        _ReportTicks++;

        if (_ReportTicks > 90)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_TapHold_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Souls_TapHold_Kb, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_BakedVerdict(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_LiveHold(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_TapColumn(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_HoldColumn(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto KeyName   = intent_gym::Format_Key(intent_gym::k_Key_Souls_TapHold_Kb);
        auto PadName   = intent_gym::Format_Key(intent_gym::k_Key_Souls_TapHold_Pad);
        auto Threshold = intent_gym::k_Souls_TapHoldFrames;

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Tap {KeyName} and let go quickly. The QUICK move comes out.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Now press {KeyName} and keep holding it. At {Threshold} frames the", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  CHARGED move comes out on its own, before you let go.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  On a pad the same two moves are on {PadName}.", gym_palette::Cyan);
    }

    private void Add_BakedVerdict(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Threshold = intent_gym::k_Souls_TapHoldFrames;

        intent_gym::Add_Line(OutLines, "WHAT THE COMPILED SET SAYS THIS BUTTON MUST DO", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  Two moves share this button and one of them declares a hold, so the", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  press cannot be answered when it lands. Nothing else here waits.", gym_palette::White);

        if (_Verdict_Hold_Key < 0)
        {
            intent_gym::Add_Line(OutLines, "  (the compiled set has not been read back yet)", gym_palette::Grey);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames it waits on a hold  (keyboard)",
            f"{Threshold}", f"{_Verdict_Hold_Key}", _Verdict_Hold_Key == Threshold);
        intent_gym::Add_Verdict(OutLines, "frames it waits on a hold  (gamepad) ",
            f"{Threshold}", f"{_Verdict_Hold_Pad}", _Verdict_Hold_Pad == Threshold);
        intent_gym::Add_Verdict(OutLines, "frames it waits on a chord           ",
            "0", f"{_Verdict_Chord_Key}", _Verdict_Chord_Key == 0);
    }

    // DISPLAY ONLY — see the file header. This is the record's physical fact,
    // walked out of the held rows, and it is here because a viewer needs to see
    // the count climbing to believe the number below it. The outcome is graded
    // from the phases, never from this.
    private void Add_LiveHold(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Sampler = intent_gym::TryGet_Sampler();

        intent_gym::Add_Line(OutLines, "HOW LONG THE BUTTON HAS BEEN DOWN (DISPLAY ONLY)", gym_palette::White);

        if (ck::Is_NOT_Valid(Sampler))
        {
            intent_gym::Add_Line(OutLines, "  no record yet - waiting for the local player's controller", gym_palette::Grey);
            return;
        }

        auto Threshold = intent_gym::k_Souls_TapHoldFrames;

        auto Run = intent_gym::Get_HeldRunFrames(Sampler, intent_gym::k_Key_Souls_TapHold_Kb.GetKeyName());
        auto PadRun = intent_gym::Get_HeldRunFrames(Sampler, intent_gym::k_Key_Souls_TapHold_Pad.GetKeyName());

        if (PadRun > Run)
        { Run = PadRun; }

        auto Colour = gym_palette::Grey;
        if (Run > 0)          { Colour = gym_palette::Amber; }
        if (Run >= Threshold) { Colour = gym_palette::Cyan; }

        intent_gym::Add_Line(OutLines, f"  frames down     {Run} / {Threshold}", Colour);
        intent_gym::Add_Line(OutLines, "  Counted off the record's held rows - the physical fact, which keeps", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  counting no matter who is receiving the input. It is NOT what decides", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  the outcome; the frames below are.", gym_palette::White);
    }

    private void Add_TapColumn(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Threshold = intent_gym::k_Souls_TapHoldFrames;
        auto Latest    = Threshold - 1;

        intent_gym::Add_Line(OutLines, "LET GO EARLY - THE QUICK MOVE", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  The button came up before the threshold, so the charged move can no", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  longer win and the wait has nothing left to decide.", gym_palette::White);

        if (_TapAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames from press to answer", f"0..{Latest}");
            return;
        }

        auto MoveName = _TapAttempt.IntentName;
        intent_gym::Add_Line(OutLines, f"  move that came out       {MoveName}", gym_palette::White);

        if (_TapAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so this attempt cannot", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  be measured. Try again.", gym_palette::Amber);
            return;
        }

        auto Gap = _TapAttempt.DeferralFrames;

        intent_gym::Add_Verdict(OutLines, "frames from press to answer", f"0..{Latest}", f"{Gap}",
            Gap >= 0 && Gap < Threshold);
    }

    private void Add_HoldColumn(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Threshold = intent_gym::k_Souls_TapHoldFrames;

        intent_gym::Add_Line(OutLines, "HOLD ON - THE CHARGED MOVE", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  A hold completes on the frame its threshold is reached - not a frame", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  early, not a frame late, and not on the release.", gym_palette::White);

        if (_HoldAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames from press to answer", f"{Threshold} exactly");
            return;
        }

        auto MoveName = _HoldAttempt.IntentName;
        intent_gym::Add_Line(OutLines, f"  move that came out       {MoveName}", gym_palette::White);

        if (_HoldAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so this attempt cannot", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  be measured. Try again.", gym_palette::Amber);
            return;
        }

        auto Gap = _HoldAttempt.DeferralFrames;

        intent_gym::Add_Verdict(OutLines, "frames from press to answer", f"{Threshold} exactly", f"{Gap}",
            Gap == Threshold);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_Souls_Hold_Key", "hold it     (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_Souls_Tap_Key",  "tap it      (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_Souls_Hold_Pad", "hold it     (gamepad) ");
        Add_PhaseRow(OutLines, n"Gym_Souls_Tap_Pad",  "tap it      (gamepad) ");

        intent_gym::Add_Line(OutLines, "  Pending is the press being held open. It is the thing this station is", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  about, so it is amber - a value legitimately in flight, never a fault.", gym_palette::White);
    }

    // Pending is the honest reading of a press the matcher has not chosen for
    // yet, and Failed is the honest reading of one that answered nothing at all
    // — so both are amber, the colour of a value in flight. Red on this gym
    // means a check that should have matched and did not.
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
