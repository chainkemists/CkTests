// Language=angelscript

//============================================================================
// CK INTENT FIGHTING GYM — DEFERRED VS INSTANT STATION
//============================================================================
//
// Two buttons, side by side, whose presses are answered on completely different
// frames — and the whole point is that the difference is EARNED rather than
// configured. A press is acted on immediately unless waiting is the only way to
// be right, and this panel shows both sides of that sentence at once.
//
//   the LEFT button  is half of a two-button chord as well as a move on its own,
//                    so a lone press might still be the first half of something.
//                    That ambiguity reaches FORWARD, so the press waits out the
//                    chord window and the counter reads the window.
//
//   the RIGHT button is the terminal of a bare move AND of a motion. That
//                    ambiguity reaches BACKWARD only — the motion either already
//                    happened or it did not — so the press is answered on its
//                    own frame and the counter reads zero.
//
// ONE SET, ONE SESSION. Either half alone would also pass against a broken
// implementation: a matcher that waited for everything would satisfy the left
// column, and one that waited for nothing would satisfy the right. Only the two
// together say that the wait is opt-in and earned.
//
// NO STICK NEEDED. The motion sharing the right button's terminal is never
// expected to be performed — its presence in the set is the entire reason that
// button is a shared terminal. That is what makes this station the one a viewer
// with only a keyboard can fully drive.
//============================================================================

class UCk_EntityScript_IntentGym_DeferredVsInstant : UCk_GenericEntityScript_UE
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

    private int32 _ChordVerdict_Hold  = -1;
    private int32 _ChordVerdict_Chord = -1;
    private int32 _SuffixVerdict_Hold  = -1;
    private int32 _SuffixVerdict_Chord = -1;

    private FCkIntentGym_Attempt _ChordAttempt;
    private FCkIntentGym_Attempt _SuffixAttempt;
    private int32                _ReportTicks = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_DeferredVsInstant);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Contrast_Arm);

        _StepConfig.Description = "One button that has to wait, one that never does, in the same move set.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Contrast_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Contrast_Await,  "Waiting for you to press both buttons"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Contrast_Report, "Reading back both frame gaps"));

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

    private void DoTryCompose()
    {
        if (intent_gym::Request_EnsureSourceComposed() == false)
        { return; }

        if (ck::Is_NOT_Valid(_Matcher))
        {
            auto Source = intent_gym::TryGet_PlayerSource();
            auto SelfEntity = ck::ToEntity(this);

            _Layer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_DeferredVsInstant));

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

        // Every terminal has to be minted before the swap, not just one: the
        // swap resolves all of them and rejects the WHOLE set if a single one
        // answers no key.
        auto ChordAReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_ChordA).Num() > 0;
        auto ChordBReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_ChordB).Num() > 0;
        auto SuffixReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Suffix).Num() > 0;

        if (ChordAReady == false || ChordBReady == false || SuffixReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_moves::MoveTable_DeferredVsInstant.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"CA", intent_gym::Make_PhysicalButton(intent_gym::k_Key_ChordA)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"CB", intent_gym::Make_PhysicalButton(intent_gym::k_Key_ChordB)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"SF", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Suffix)));

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
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_ChordA));
        auto SuffixVerdict = utils_intent_grammar::Get_DeferralVerdict(
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Suffix));

        _ChordVerdict_Hold   = ChordVerdict.Get_HoldSiblingFrames();
        _ChordVerdict_Chord  = ChordVerdict.Get_ChordMemberFrames();
        _SuffixVerdict_Hold  = SuffixVerdict.Get_HoldSiblingFrames();
        _SuffixVerdict_Chord = SuffixVerdict.Get_ChordMemberFrames();

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

        // The chord's terminal is two buttons; the gap is measured from the
        // AMBIGUOUS one, because that is the press whose answer was held back.
        auto ChordAName = intent_gym::k_Key_ChordA.GetKeyName();
        auto SuffixName = intent_gym::k_Key_Suffix.GetKeyName();

        auto ChordLanded =
            intent_gym::Request_RecordAttempt(_ChordAttempt, _Matcher, Sampler, n"Gym_Chord_Pair", ChordAName) ||
            intent_gym::Request_RecordAttempt(_ChordAttempt, _Matcher, Sampler, n"Gym_Chord_Bare", ChordAName);

        auto SuffixLanded =
            intent_gym::Request_RecordAttempt(_SuffixAttempt, _Matcher, Sampler, n"Gym_Suffix_Bare",   SuffixName) ||
            intent_gym::Request_RecordAttempt(_SuffixAttempt, _Matcher, Sampler, n"Gym_Suffix_Motion", SuffixName);

        if (ChordLanded || SuffixLanded)
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
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Suffix);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Contrast_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Contrast_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Contrast_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Contrast_Await);
            return;
        }

        auto BothSeen = _ChordAttempt.Recorded && _SuffixAttempt.Recorded;

        if (_ReportTicks == 0 && BothSeen && Current == UCk_IntentGym_Step_Contrast_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Contrast_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Contrast_Report)
        { return; }

        _ReportTicks++;

        if (_ReportTicks > 90)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Contrast_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Suffix, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_ChordColumn(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_SuffixColumn(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto ChordA = intent_gym::Format_Key(intent_gym::k_Key_ChordA);
        auto ChordB = intent_gym::Format_Key(intent_gym::k_Key_ChordB);
        auto Suffix = intent_gym::Format_Key(intent_gym::k_Key_Suffix);

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Tap {Suffix} on its own. It answers instantly.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Tap {ChordA} on its own. It visibly hesitates first.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Then tap {ChordA} and {ChordB} together - the hesitation was for this.", gym_palette::Cyan);
    }

    private void Add_ChordColumn(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto ChordA = intent_gym::Format_Key(intent_gym::k_Key_ChordA);
        auto Window = intent_gym::k_ChordWindowFrames;

        intent_gym::Add_Line(OutLines, f"LEFT BUTTON [{ChordA}] - HAS TO WAIT", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  It ends a move on its own AND completes a two-button pair, so a", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  lone press might still be half of something that has not arrived.", gym_palette::White);

        if (_ChordVerdict_Chord < 0)
        {
            intent_gym::Add_Line(OutLines, "  (the compiled set has not been read back yet)", gym_palette::Grey);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames it is told to wait",
            f"{Window}", f"{_ChordVerdict_Chord}", _ChordVerdict_Chord == Window);
        intent_gym::Add_Verdict(OutLines, "frames it waits on a hold  ",
            "0", f"{_ChordVerdict_Hold}", _ChordVerdict_Hold == 0);

        if (_ChordAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames it actually waited", f"{Window} or more");
            return;
        }

        auto MoveName = _ChordAttempt.IntentName;
        intent_gym::Add_Line(OutLines, f"  move that came out       {MoveName}", gym_palette::White);

        if (_ChordAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so this attempt cannot", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  be measured. Try again.", gym_palette::Amber);
            return;
        }

        // The partner arriving and the window expiring are the two ways the wait
        // ends, and they are different verdicts. A partner that landed INSIDE
        // the window is the wait paying off; a bare move answering after it is
        // the wait being spent. Anything else would mean the window was not
        // honoured.
        if (MoveName == n"Gym_Chord_Pair")
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

    private void Add_SuffixColumn(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Suffix = intent_gym::Format_Key(intent_gym::k_Key_Suffix);

        intent_gym::Add_Line(OutLines, f"RIGHT BUTTON [{Suffix}] - NEVER WAITS", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  A motion ends on this button too, and that motion either already", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  happened or it did not. Nothing about it lies in the future.", gym_palette::White);

        if (_SuffixVerdict_Chord < 0)
        {
            intent_gym::Add_Line(OutLines, "  (the compiled set has not been read back yet)", gym_palette::Grey);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames it is told to wait",
            "0", f"{_SuffixVerdict_Chord}", _SuffixVerdict_Chord == 0);
        intent_gym::Add_Verdict(OutLines, "frames it waits on a hold  ",
            "0", f"{_SuffixVerdict_Hold}", _SuffixVerdict_Hold == 0);

        if (_SuffixAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames it actually waited", "0");
            return;
        }

        auto MoveName = _SuffixAttempt.IntentName;
        intent_gym::Add_Line(OutLines, f"  move that came out       {MoveName}", gym_palette::White);

        if (_SuffixAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so this attempt cannot", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  be measured. Try again.", gym_palette::Amber);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames it actually waited",
            "0", f"{_SuffixAttempt.DeferralFrames}", _SuffixAttempt.DeferralFrames == 0);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_Chord_Pair",    "both buttons together");
        Add_PhaseRow(OutLines, n"Gym_Chord_Bare",    "left button alone");
        Add_PhaseRow(OutLines, n"Gym_Suffix_Motion", "motion + right button (needs a stick)");
        Add_PhaseRow(OutLines, n"Gym_Suffix_Bare",   "right button alone");
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
