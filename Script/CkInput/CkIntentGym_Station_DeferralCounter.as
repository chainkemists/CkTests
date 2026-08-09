// Language=angelscript

//============================================================================
// CK INTENT FIGHTING GYM — DEFERRAL COUNTER STATION
//============================================================================
//
// The latency claim the whole module is shaped around, put in front of a human
// with a counter on it: do a quarter-circle-forward and punch, and the number of
// frames between the punch landing in the record and the move coming out must be
// ZERO. Not "fast". Zero.
//
// That is only possible because the matcher scans BACKWARDS. A forward matcher
// would have to notice 2, then 3, then wait to see whether 6+punch ever arrives,
// and the earliest frame it could answer on is the frame after the press. Here
// the press is the question and the record behind it is the answer, so the two
// share a frame index by construction.
//
// THE BARE PUNCH IS IN THE SET ON PURPOSE. With one candidate there is no
// ambiguity to have resolved and a zero would prove nothing. A bare punch
// sharing the motion's terminal is the case a naive matcher gets wrong — it
// holds the punch back "in case a motion is coming" — so the zero on this panel
// is a statement about SHARING a terminal, not about a thin set.
//
// COMPLETION IS LATCHED, so the counter cannot branch on the phase: a poller
// that did would re-read the same completion every frame until the latch decayed
// (CkIntent/CLAUDE.md anti-pattern 15). The freshness test here is the
// COMPLETION FRAME against the one already on screen, which is what turns a
// latch into an edge.
//============================================================================

class UCk_EntityScript_IntentGym_DeferralCounter : UCk_GenericEntityScript_UE
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
    // set is the thing that decides whether a press waits, so the panel quotes
    // it rather than restating what the notation was supposed to mean.
    private int32 _Verdict_HoldFrames  = -1;
    private int32 _Verdict_ChordFrames = -1;

    private FCkIntentGym_Attempt _LastAttempt;
    private int32                _ReportTicks = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_DeferralCounter);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Counter_Arm);

        _StepConfig.Description = "A motion and a bare press on one button, and the frame gap between them.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Counter_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Counter_Await,  "Waiting for you to do the motion"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Counter_Report, "Reading back what came out"));

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
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_DeferralCounter));

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
        // derivation request drains, so the swap waits for the key to be minted
        // rather than being rejected for a terminal that only looks unresolvable.
        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        { return; }

        if (utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Punch_Pad).Num() == 0)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_moves::MoveTable_DeferralCounter.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"P",  intent_gym::Make_PhysicalButton(intent_gym::k_Key_Punch_Pad)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"PK", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Punch_Kb)));

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
        auto Verdict = utils_intent_grammar::Get_DeferralVerdict(
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Punch_Pad));

        _Verdict_HoldFrames = Verdict.Get_HoldSiblingFrames();
        _Verdict_ChordFrames = Verdict.Get_ChordMemberFrames();

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

        auto PadName = intent_gym::k_Key_Punch_Pad.GetKeyName();
        auto KeyName = intent_gym::k_Key_Punch_Kb.GetKeyName();

        auto Landed =
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Qcf_Punch_Pad",  PadName) ||
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Punch_Bare_Pad", PadName) ||
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Qcf_Punch_Key",  KeyName) ||
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Punch_Bare_Key", KeyName);

        if (Landed)
        { _ReportTicks = 0; }
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
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Punch_Pad);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Counter_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Counter_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Counter_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Counter_Await);
            return;
        }

        if (_ReportTicks == 0 && _LastAttempt.Recorded && Current == UCk_IntentGym_Step_Counter_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Counter_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Counter_Report)
        { return; }

        _ReportTicks++;

        // Back to waiting once the answer has had time to be read AND the
        // player's finger is off the button — returning while the terminal is
        // still down would invite a second press the panel would attribute to
        // the wrong step.
        auto Sampler = intent_gym::TryGet_Sampler();
        auto StillHeld =
            intent_gym::Get_IsButtonHeld(Sampler, intent_gym::k_Key_Punch_Pad.GetKeyName()) ||
            intent_gym::Get_IsButtonHeld(Sampler, intent_gym::k_Key_Punch_Kb.GetKeyName());

        if (_ReportTicks > 90 && StillHeld == false)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Counter_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Punch_Pad, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        intent_gym::Add_LiveInput(Lines, Sampler);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Law(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Counter(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto PadPunch = intent_gym::Format_Key(intent_gym::k_Key_Punch_Pad);
        auto KeyPunch = intent_gym::Format_Key(intent_gym::k_Key_Punch_Kb);

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  Roll the LEFT STICK down, then down-forward, then forward,", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  and press {PadPunch} as the stick reaches forward.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  No pad? Press {KeyPunch} on the keyboard for the bare-press half.", gym_palette::Cyan);
    }

    private void Add_Law(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "THE RULE THIS STATION IS PROVING", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  A button that several moves end on still answers on the frame", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  it was pressed. The motion either already happened or it did not,", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  so there is nothing in the future worth waiting for.", gym_palette::White);

        if (_Verdict_HoldFrames < 0)
        {
            intent_gym::Add_Line(OutLines, "  (the compiled set has not been read back yet)", gym_palette::Grey);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames this button waits on a hold ",
            "0", f"{_Verdict_HoldFrames}", _Verdict_HoldFrames == 0);
        intent_gym::Add_Verdict(OutLines, "frames this button waits on a chord",
            "0", f"{_Verdict_ChordFrames}", _Verdict_ChordFrames == 0);
    }

    private void Add_Counter(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "THE COUNTER", gym_palette::White);

        if (_LastAttempt.Recorded == false)
        {
            intent_gym::Add_Line(OutLines, "  Nothing performed yet - do the motion above.", gym_palette::Grey);
            intent_gym::Add_Verdict_Pending(OutLines, "frames of delay", "0");
            return;
        }

        auto MoveName = _LastAttempt.IntentName;

        intent_gym::Add_Line(OutLines, f"  move that came out   {MoveName}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  press landed on frame    {_LastAttempt.PressFrame}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  move came out on frame   {_LastAttempt.CompletionFrame}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  attempts so far          {_LastAttempt.AttemptCount}", gym_palette::White);

        if (_LastAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge has already been overwritten in the record, so the", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  gap cannot be measured for this attempt. Try again.", gym_palette::Amber);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames of delay",
            "0", f"{_LastAttempt.DeferralFrames}", _LastAttempt.DeferralFrames == 0);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_Qcf_Punch_Pad",  "quarter-circle + punch (pad)");
        Add_PhaseRow(OutLines, n"Gym_Punch_Bare_Pad", "bare punch (pad)");
        Add_PhaseRow(OutLines, n"Gym_Qcf_Punch_Key",  "quarter-circle + punch (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_Punch_Bare_Key", "bare punch (keyboard)");
    }

    // Phase colours are STATUS, not verdicts: Idle is the resting state of a
    // move nobody has asked for, so it is grey rather than red.
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
