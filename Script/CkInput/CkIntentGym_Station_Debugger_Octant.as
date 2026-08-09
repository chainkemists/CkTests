// Language=angelscript

//============================================================================
// CK INTENT DEBUGGER GYM — OCTANT SWEEP AND KEY STATE STATION
//============================================================================
//
// The key/state view's rosette is the one place in the debugger where a reader
// can catch the module lying to them, and it is built to make that possible: it
// lights the ROW'S OWN octant and draws the conditioned axis pair as a separate
// dot, rather than deriving one from the other. A dot sitting inside one wedge
// while a neighbouring spoke is lit is not a bug in either — it IS the
// hysteresis, rendered instead of recomputed.
//
// This station is the traffic for that. A slow full circle walks the dot through
// every boundary in turn, and the panel prints the same three readings the view
// is drawing, off the same row:
//
//   the OCTANT   the row's `_Octant`, hysteresis-damped against the previous
//                row. Never recomputed here — a panel that ran atan2 over the
//                axis pair would agree with the view on every frame except the
//                ones the damping exists for.
//   the AXES     the conditioned pair, which is where the dot goes.
//   the CLEANED  the SOCD cardinals, which are a different question with a
//                different answer: a stick moves the octant and leaves both
//                cleaned slots Neutral, and the keyboard quad moves the cleaned
//                slots and leaves the octant Neutral.
//
// AND ONE THING THE VIEW CANNOT SAY. Which move came out confirms which octant
// the MATCHER used, not just which one the row printed — so the direction move
// and its bare rival are what turn a picture into a check.
//
// MOTION IS STICK-ONLY. The record's octant is derived from the sampler's axis
// pair and nothing else, so no key on any keyboard can move it. The keyboard
// leg here is the terminal button and the SOCD quad; the circle needs a pad.
//============================================================================

class UCk_EntityScript_IntentGym_Debugger_Octant : UCk_GenericEntityScript_UE
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

    private int32 _Verdict_Hold  = -1;
    private int32 _Verdict_Chord = -1;

    // Every octant the record has reported since this station armed, one bit
    // each. A sweep is only complete when the viewer has been through all eight,
    // and a panel that could not say so would leave "did I actually cover the
    // whole circle" to memory. The enum's order is the ANGLE order with Neutral
    // in slot zero, so the eight directions are bits 1 through 8 and nothing has
    // to be looked up.
    private int32 _OctantsSeenMask = 0;

    private FCkIntentGym_Attempt _LastAttempt;
    private int32                _ReportTicks = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_Debugger_Octant);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Debugger_Octant_Arm);

        _StepConfig.Description = "A slow circle on the stick, read against the rosette drawn beside it.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Octant_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Octant_Await,  "Waiting for you to sweep the stick"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Octant_Report, "Reading back which move the octant built"));

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
        DoTrackSweep();
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
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Debugger_Octant));

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

        auto KeyReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_Octant_Kb).Num() > 0;
        auto PadReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_Octant_Pad).Num() > 0;

        if (KeyReady == false || PadReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_debugger_moves::MoveTable_Debugger_Octant.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"OS",  intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Octant_Kb)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"OSP", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Octant_Pad)));

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
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Octant_Pad));

        _Verdict_Hold  = Verdict.Get_HoldSiblingFrames();
        _Verdict_Chord = Verdict.Get_ChordMemberFrames();

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Set),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

        _SwapRequested = true;
    }

    //------------------------------------------------------------------------
    // Reading the sweep
    //------------------------------------------------------------------------

    private void DoTrackSweep()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler))
        { return; }

        auto Octant = intent_gym::Get_LiveOctant(Sampler);

        if (Octant == ECk_Intent_Octant::Neutral)
        { return; }

        _OctantsSeenMask = _OctantsSeenMask | (1 << int32(Octant));
    }

    private int32 Get_OctantsSeenCount()
    {
        auto Count = 0;

        for (auto Index = 1; Index <= 8; Index++)
        {
            if ((_OctantsSeenMask & (1 << Index)) != 0)
            { Count++; }
        }

        return Count;
    }

    private void DoTryRecordAttempts()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        auto KeyName = intent_gym::k_Key_Debugger_Octant_Kb.GetKeyName();
        auto PadName = intent_gym::k_Key_Debugger_Octant_Pad.GetKeyName();

        auto Landed =
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Dbg_Octant_East_Pad", PadName) ||
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Dbg_Octant_Bare_Pad", PadName) ||
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Dbg_Octant_East_Kb",  KeyName) ||
            intent_gym::Request_RecordAttempt(_LastAttempt, _Matcher, Sampler, n"Gym_Dbg_Octant_Bare_Kb",  KeyName);

        if (Landed)
        { _ReportTicks = 0; }
    }

    private bool Get_IsSocdPairHeld(FName InFirst, FName InSecond)
    {
        auto Sampler = intent_gym::TryGet_Sampler();

        if (intent_gym::Get_IsButtonHeld(Sampler, InFirst) == false)
        { return false; }

        return intent_gym::Get_IsButtonHeld(Sampler, InSecond);
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Debugger_Octant_Pad);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Debugger_Octant_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Octant_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Debugger_Octant_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Octant_Await);
            return;
        }

        if (_ReportTicks == 0 && _LastAttempt.Recorded && Current == UCk_IntentGym_Step_Debugger_Octant_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Octant_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Debugger_Octant_Report)
        { return; }

        _ReportTicks++;

        if (_ReportTicks > 90)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Octant_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Debugger_Octant_Pad, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_WhatTheViewShouldShow(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_LiveRow(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Socd(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Sweep(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_WhichMoveTheOctantBuilt(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto PadKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Octant_Pad);
        auto KbKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Octant_Kb);
        auto SocdLeft = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Socd_Left);
        auto SocdRight = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Socd_Right);

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  Roll the LEFT STICK all the way around, once, SLOWLY - slow enough", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  that you can watch a boundary go past rather than flick over it.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  With the stick held forward, press {PadKey}: the direction move comes", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  out. Press it anywhere else and the bare move comes out instead.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Then hold {SocdLeft} and {SocdRight} together - both ends of one axis.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  No pad? {KbKey} presses the button, but a keyboard cannot move the", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  stick reading at all: the octant comes from the axis pair and nothing", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  else, so the sweep half of this station needs a gamepad.", gym_palette::White);
    }

    private void Add_WhatTheViewShouldShow(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Priority = intent_gym::k_LayerPriority_Debugger_Octant;

        intent_gym::Add_DebuggerViewHeader(OutLines, "KEY / STATE VIEW");
        intent_gym::Add_Line(OutLines, f"  The row is the SOURCE's, so any layer selects it - this station owns", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  priority {Priority} if you want its phases beside the rosette.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  EXPECT the rosette's LIT SPOKE to equal the OCTANT printed below at", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  every instant of the sweep - if they ever disagree, one of the two is", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  wrong and that is worth stopping for.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  EXPECT the DOT to cross a wedge boundary BEFORE the lit spoke follows", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  it. That lag is the recorded hysteresis: the dot is the conditioned", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  axis pair, the spoke is the row's own octant, and the row keeps the", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  previous octant until the angle clears the margin past the boundary.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  EXPECT the view's held-button list and cleaned cardinals to match the", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  two blocks below, button for button.", gym_palette::Cyan);
    }

    private void Add_LiveRow(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Sampler = intent_gym::TryGet_Sampler();

        intent_gym::Add_Line(OutLines, "THE ROW THE VIEW IS DRAWING", gym_palette::White);

        if (ck::Is_NOT_Valid(Sampler))
        {
            intent_gym::Add_Line(OutLines, "  no record yet - waiting for the local player's controller", gym_palette::Grey);
            return;
        }

        auto Row = utils_intent_sampler::Get_LatestFrame(Sampler);
        auto Octant = Row.Get_Octant();
        auto OctantColour = Octant == ECk_Intent_Octant::Neutral ? gym_palette::Grey : gym_palette::Cyan;

        auto AxisX = Row.Get_ConditionedAxisX();
        auto AxisY = Row.Get_ConditionedAxisY();

        intent_gym::Add_Line(OutLines, f"  logic frame   {Row.Get_FrameIndex()}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  OCTANT        {intent_gym::Format_Octant(Octant)}", OctantColour);
        intent_gym::Add_Line(OutLines, f"  axis pair     X {AxisX :.2}   Y {AxisY :.2}", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  The axis pair is where the dot goes; the octant is what lights a", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  spoke. Neither is computed from the other on this panel.", gym_palette::White);

        Add_HeldSet(OutLines, Sampler);
    }

    private void Add_HeldSet(TArray<FCkGym_ColoredLine>& OutLines, FCk_Handle_IntentSampler InSampler)
    {
        TArray<FName> Held = intent_gym::Get_HeldButtonNames(InSampler);

        if (Held.Num() == 0)
        {
            intent_gym::Add_Line(OutLines, "  held buttons  none", gym_palette::Grey);
            return;
        }

        for (auto Index = 0; Index < Held.Num(); Index++)
        {
            auto Name = Held[Index];
            intent_gym::Add_Line(OutLines, f"  held button   {Name}", gym_palette::Cyan);
        }
    }

    private void Add_Socd(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Sampler = intent_gym::TryGet_Sampler();

        intent_gym::Add_Line(OutLines, "THE OTHER DIRECTION READING - CLEANED CARDINALS", gym_palette::White);

        if (ck::Is_NOT_Valid(Sampler))
        {
            intent_gym::Add_Line(OutLines, "  no record yet", gym_palette::Grey);
            return;
        }

        auto Row = utils_intent_sampler::Get_LatestFrame(Sampler);
        auto Horizontal = Row.Get_CleanedHorizontal();
        auto Vertical = Row.Get_CleanedVertical();

        intent_gym::Add_Line(OutLines, f"  horizontal    {intent_gym::Format_CleanedAxis(Horizontal)}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  vertical      {intent_gym::Format_CleanedAxis(Vertical)}", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  These come from the four keyboard cardinals, NOT from the stick - a", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  stick moves the octant and leaves both of these Neutral. No direction", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  step is ever matched against them; they are a separate reading a", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  consumer chooses between.", gym_palette::White);

        auto BothHorizontal = Get_IsSocdPairHeld(
            intent_gym::k_Key_Debugger_Socd_Left.GetKeyName(),
            intent_gym::k_Key_Debugger_Socd_Right.GetKeyName());

        if (BothHorizontal == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "both ends of the horizontal axis", "Neutral");
            return;
        }

        intent_gym::Add_Verdict(OutLines, "both ends of the horizontal axis",
            "Neutral", intent_gym::Format_CleanedAxis(Horizontal),
            Horizontal == ECk_Intent_CleanedAxis::Neutral);

        intent_gym::Add_Line(OutLines, "  Left and right at once reads as neither. That is the tournament", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  standard and the only policy that cannot produce a reading the", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  hardware it emulates could not give.", gym_palette::White);
    }

    private void Add_Sweep(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "HOW MUCH OF THE CIRCLE YOU HAVE COVERED", gym_palette::White);

        auto Seen = Get_OctantsSeenCount();
        auto Colour = gym_palette::Grey;
        if (Seen > 0) { Colour = gym_palette::Amber; }
        if (Seen >= 8) { Colour = gym_palette::Cyan; }

        intent_gym::Add_Line(OutLines, f"  directions visited   {Seen} / 8", Colour);
        intent_gym::Add_Line(OutLines, "  Counted off the record's own octant, so a direction the row never", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  reported does not count here either - which is itself the finding if", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  a full circle leaves one uncovered.", gym_palette::White);
    }

    private void Add_WhichMoveTheOctantBuilt(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHICH MOVE THE OCTANT ACTUALLY BUILT", gym_palette::White);

        if (_Verdict_Chord >= 0)
        {
            intent_gym::Add_Verdict(OutLines, "frames this button waits on a chord",
                "0", f"{_Verdict_Chord}", _Verdict_Chord == 0);
            intent_gym::Add_Verdict(OutLines, "frames this button waits on a hold ",
                "0", f"{_Verdict_Hold}", _Verdict_Hold == 0);
            intent_gym::Add_Line(OutLines, "  A DIRECTION in a chord never defers - only a second BUTTON does - so", gym_palette::White);
            intent_gym::Add_Line(OutLines, "  the direction move answers on the frame you pressed it.", gym_palette::White);
        }

        if (_LastAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames from press to answer", "0");
            return;
        }

        auto MoveName = _LastAttempt.IntentName;
        intent_gym::Add_Line(OutLines, f"  move that came out   {MoveName}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  press landed on frame  {_LastAttempt.PressFrame}", gym_palette::White);

        if (_LastAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so this attempt cannot", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  be measured. Press again.", gym_palette::Amber);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames from press to answer",
            "0", f"{_LastAttempt.DeferralFrames}", _LastAttempt.DeferralFrames == 0);

        intent_gym::Add_Line(OutLines, "  Scrub the timeline to that frame and read the octant the key/state", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  view shows there: a direction move means the matcher saw the same", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  direction the row recorded, which no picture on its own can say.", gym_palette::White);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_Dbg_Octant_East_Pad", "forward + button (gamepad) ");
        Add_PhaseRow(OutLines, n"Gym_Dbg_Octant_Bare_Pad", "button alone     (gamepad) ");
        Add_PhaseRow(OutLines, n"Gym_Dbg_Octant_East_Kb",  "forward + button (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_Dbg_Octant_Bare_Kb",  "button alone     (keyboard)");
    }

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
