// Language=angelscript

//============================================================================
// CK INTENT FIGHTING GYM — NEAR MISS STATION
//============================================================================
//
// "I did the motion and nothing came out." A failed backward scan leaves no
// trace anywhere else — the record shows the press, the phase rows show Idle, no
// signal fires — so that sentence is unanswerable unless something writes down
// what the walk actually looked for. This station instructs the failure on
// purpose, then reads the answer back.
//
// FAILING HERE IS THE EXERCISE, NOT A DEFECT. The set bakes a deliberately tight
// window, so a quarter-circle performed at a comfortable pace runs out of frames
// before the walk finds its first step. That outcome is rendered white and
// explained in cyan; it is never red. Red on this panel means the ring itself
// did not answer a press it should have.
//
// `lenient` is load-bearing in the notation. Without it the walk would die on
// the first neutral row as a CONTIGUITY break, which is a different diagnosis
// with a different fix. This station is about the other one: the input was there
// in spirit and the player was too slow.
//
// THE SWITCH IS GLOBAL AND IS TURNED OFF ON THE WAY OUT.
// `ck.Intent.RecordScanDiagnostics` writes an entry per scan ATTEMPT on every
// matcher in the session, so a gym that left it on would be paying for rings
// nobody reads (CkIntent/CLAUDE.md anti-pattern 33). It is armed when this
// station arms and cleared in DoEndPlay.
//============================================================================

class UCk_EntityScript_IntentGym_NearMiss : UCk_GenericEntityScript_UE
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
    private int32 _EntriesAtPress   = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_NearMiss);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_NearMiss_Arm);

        _StepConfig.Description = "A motion that misses its window, and the record of exactly how.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_NearMiss_Arm,    "Load the set and start recording"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_NearMiss_Await,  "Waiting for you to miss on purpose"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_NearMiss_Report, "Reading back what the walk looked for"));

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
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_NearMiss));

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

        auto PadReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_NearMiss_Pad).Num() > 0;
        auto KeyReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_NearMiss_Kb).Num() > 0;

        if (PadReady == false || KeyReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_moves::MoveTable_NearMiss.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"NM",  intent_gym::Make_PhysicalButton(intent_gym::k_Key_NearMiss_Pad)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"NMK", intent_gym::Make_PhysicalButton(intent_gym::k_Key_NearMiss_Kb)));

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

        auto PadPress = intent_gym::Get_LatestPressFrame(Sampler, intent_gym::k_Key_NearMiss_Pad.GetKeyName());
        auto KeyPress = intent_gym::Get_LatestPressFrame(Sampler, intent_gym::k_Key_NearMiss_Kb.GetKeyName());
        auto Newest = PadPress > KeyPress ? PadPress : KeyPress;

        if (Newest >= 0 && Newest != _LastPressFrame)
        {
            _LastPressFrame = Newest;
            _TicksSincePress = 0;
            _EntriesAtPress = utils_intent_matcher::Get_ScanDiagnostics(_Matcher).Num();
            return;
        }

        if (_LastPressFrame >= 0)
        { _TicksSincePress++; }
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_NearMiss_Pad);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_NearMiss_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_NearMiss_Arm); }
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

        if (Current == UCk_IntentGym_Step_NearMiss_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_NearMiss_Await);
            return;
        }

        auto HasEntry = utils_intent_matcher::Get_ScanDiagnostics(_Matcher).Num() > 0;

        if (HasEntry && _TicksSincePress < 90 && Current == UCk_IntentGym_Step_NearMiss_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_NearMiss_Report);
            return;
        }

        if (Current == UCk_IntentGym_Step_NearMiss_Report && _TicksSincePress > 180)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_NearMiss_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_NearMiss_Pad, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        intent_gym::Add_LiveInput(Lines, Sampler);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Recorder(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Diagnostic(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_WhereElseToLook(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto PadKey = intent_gym::Format_Key(intent_gym::k_Key_NearMiss_Pad);
        auto KbKey = intent_gym::Format_Key(intent_gym::k_Key_NearMiss_Kb);
        auto Window = intent_gym::k_NearMissWindowFrames;

        intent_gym::Add_Line(OutLines, "DO THIS - AND DO IT TOO SLOWLY ON PURPOSE", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  Roll the LEFT STICK down, down-forward, forward - unhurried -", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  then press {PadKey}. Nothing will come out. That is the point.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  This move allows {Window} logic frames for the whole motion.", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  No pad? Press {KbKey} - a keyboard moves no stick, so it misses", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  the same way and reports the same diagnosis.", gym_palette::Cyan);
    }

    private void Add_Recorder(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Enabled = utils_intent_matcher::Get_ScanDiagnosticsEnabled();

        intent_gym::Add_Line(OutLines, "THE RECORDER", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  A failed motion leaves no trace anywhere else - not in the record,", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  not in the move's status, and no event is raised. This ring is the", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  only thing that can say which part of the motion was missing.", gym_palette::White);

        intent_gym::Add_Verdict(OutLines, "recording",
            "yes", intent_gym::Format_Bool(Enabled), Enabled);

        intent_gym::Add_Line(OutLines, "  It is off by default and costs every scan an entry while it is on,", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  so leaving this gym turns it back off.", gym_palette::White);
    }

    private void Add_Diagnostic(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHAT THE LAST ATTEMPT LOOKED FOR", gym_palette::White);

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

        // Newest first, which is the order a near-miss list is read in.
        auto Entry = Entries[0];
        auto MoveName = Entry.Get_IntentName();
        auto Outcome = Entry.Get_Outcome();

        intent_gym::Add_Line(OutLines, f"  move it tried to build   {MoveName}", gym_palette::White);
        intent_gym::Add_Line(OutLines, f"  press it scanned back from   frame {Entry.Get_TerminalFrame()}", gym_palette::White);

        if (Outcome == ECk_Intent_ScanOutcome::Matched)
        {
            intent_gym::Add_Line(OutLines, "  You beat the window - the whole motion was behind the press.", gym_palette::Green);
        }
        else
        {
            intent_gym::Add_Line(OutLines, f"  it gave up on part {Entry.Get_FailedStepIndex()} of the motion", gym_palette::White);
        }

        intent_gym::Add_Spacer(OutLines, gym_palette::White);
        intent_gym::Add_Line(OutLines, "  each part of the motion, newest first:", gym_palette::White);

        TArray<FCk_Intent_ScanStepDiagnostic> Steps = Entry.Get_Steps();

        for (auto Index = 0; Index < Steps.Num(); Index++)
        {
            Add_StepRow(OutLines, Steps[Index]);
        }

        intent_gym::Add_Spacer(OutLines, gym_palette::White);
        Add_Diagnosis(OutLines, Steps);
    }

    // The walk runs backwards and stops where it died, so a part it never got to
    // look for has no row here — inventing one would be reporting work that did
    // not happen.
    private void Add_StepRow(TArray<FCkGym_ColoredLine>& OutLines, const FCk_Intent_ScanStepDiagnostic&in InStep)
    {
        auto Outcome = InStep.Get_Outcome();
        auto Colour = Outcome == ECk_Intent_ScanStepOutcome::Matched ? gym_palette::Green : gym_palette::White;

        auto Where = FString("never found");
        if (InStep.Get_MatchedAtFrame() >= 0)
        { Where = f"found on frame {InStep.Get_MatchedAtFrame()}"; }

        intent_gym::Add_Line(OutLines,
            f"    part {InStep.Get_StepIndex()}  {Outcome :n}  -  {Where}, {InStep.Get_FramesExamined()} frames read",
            Colour);
    }

    // Three failures, three different fixes. Naming which one a viewer is
    // looking at is the whole value of the ring — a list of frame counts with no
    // reading attached is a debugger's output, not a station's.
    private void Add_Diagnosis(TArray<FCkGym_ColoredLine>& OutLines, TArray<FCk_Intent_ScanStepDiagnostic>& InSteps)
    {
        if (InSteps.Num() == 0)
        { return; }

        auto Last = InSteps[InSteps.Num() - 1];
        auto Outcome = Last.Get_Outcome();

        if (Outcome == ECk_Intent_ScanStepOutcome::WindowExhausted)
        {
            intent_gym::Add_Line(OutLines, "  WHAT THAT MEANS: the input was there in spirit and you were too", gym_palette::Cyan);
            intent_gym::Add_Line(OutLines, "  slow. This is the miss this station is asking you to make.", gym_palette::Cyan);
            return;
        }

        if (Outcome == ECk_Intent_ScanStepOutcome::ContiguityBroken)
        {
            intent_gym::Add_Line(OutLines, "  WHAT THAT MEANS: the stick passed through a direction the move", gym_palette::Cyan);
            intent_gym::Add_Line(OutLines, "  never mentions. A lenient move would have tolerated it.", gym_palette::Cyan);
            return;
        }

        if (Outcome == ECk_Intent_ScanStepOutcome::NotSatisfied)
        {
            intent_gym::Add_Line(OutLines, "  WHAT THAT MEANS: the press itself was wrong for this move - the", gym_palette::Cyan);
            intent_gym::Add_Line(OutLines, "  direction was not being held when the button went down.", gym_palette::Cyan);
            return;
        }

        intent_gym::Add_Line(OutLines, "  WHAT THAT MEANS: every part was found. The move came out.", gym_palette::Cyan);
    }

    private void Add_WhereElseToLook(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "THE SAME DATA, IN THE DEBUGGER", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  Open the Ck Intent Debugger and select its Near Miss view: the same", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  ring, every entry rather than the newest, with the definition each", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  one was scanning against beside it.", gym_palette::Cyan);
    }
}
