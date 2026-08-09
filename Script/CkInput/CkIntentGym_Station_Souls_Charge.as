// Language=angelscript

//============================================================================
// CK INTENT SOULS GYM — CHARGE ACCUMULATOR STATION
//============================================================================
//
// The same law as the station beside it, stretched to two seconds so the parts a
// short hold hides become visible one at a time:
//
//   the WAIT     the press sits `Pending` for the whole descent. Pending does
//                not mean "about to complete" — it means the matcher has not
//                chosen and the answer may still be the other move — so it is
//                amber for two seconds rather than a colour that promises
//                anything.
//   the COUNT    the frames remaining, shown as a countdown. It is DISPLAY
//                arithmetic over two recorded facts (the press row this episode
//                opened on, and the row the record is currently writing), and
//                it is labelled as display because the accumulator that
//                actually decides is not readable and does not have to agree
//                with a subtraction.
//   the RESTART  let go and press again and the countdown starts from the top.
//                The episode is not resumed and the accumulator is not carried:
//                a fresh press opens a fresh wait, which is the behaviour that
//                makes a charge feel like a charge.
//
// The completion is still exact. Two seconds of waiting does not soften the
// contract — the charged move answers on the frame its threshold is reached, and
// the panel subtracts the two recorded frames and says so.
//============================================================================

class UCk_EntityScript_IntentGym_Souls_Charge : UCk_GenericEntityScript_UE
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

    // The press row the CURRENT wait opened on, and how many waits this station
    // has seen opened. Both are read off press frames rather than off the phase,
    // because the phase is latched and a poller branching on it alone re-reads
    // one answer forever (CkIntent/CLAUDE.md anti-pattern 15).
    private int32 _EpisodePressFrame = -1;
    private int32 _EpisodeCount      = 0;

    private FCkIntentGym_Attempt _FullAttempt;
    private FCkIntentGym_Attempt _QuickAttempt;
    private int32                _ReportTicks = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_Souls_Charge);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Souls_Charge_Arm);

        _StepConfig.Description = "A two-second charge, counted down while the press waits to be answered.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_Charge_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_Charge_Await,  "Waiting for you to hold it all the way down"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_Charge_Report, "Reading back the charge that landed"));

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

    private void DoTryCompose()
    {
        if (intent_gym::Request_EnsureSourceComposed() == false)
        { return; }

        if (ck::Is_NOT_Valid(_Matcher))
        {
            auto Source = intent_gym::TryGet_PlayerSource();
            auto SelfEntity = ck::ToEntity(this);

            _Layer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Souls_Charge));

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

        auto KeyReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Souls_Charge_Kb).Num() > 0;
        auto PadReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Souls_Charge_Pad).Num() > 0;

        if (KeyReady == false || PadReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_souls_moves::MoveTable_Souls_Charge.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"CH",  intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_Charge_Kb)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"CHP", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_Charge_Pad)));

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
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_Charge_Kb));

        _Verdict_Hold  = Verdict.Get_HoldSiblingFrames();
        _Verdict_Chord = Verdict.Get_ChordMemberFrames();

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Set),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

        _SwapRequested = true;
    }

    //------------------------------------------------------------------------
    // Reading the result
    //------------------------------------------------------------------------

    // A new press frame under a live wait is a new EPISODE. Nothing here reads
    // the accumulator — it is not readable — only the two facts the record does
    // carry: which row the press landed on, and that the matcher is waiting.
    private void DoTrackEpisodes()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        if (Get_IsWaiting() == false)
        { return; }

        auto PressFrame = Get_LatestChargePressFrame(Sampler);

        if (PressFrame < 0 || PressFrame == _EpisodePressFrame)
        { return; }

        _EpisodePressFrame = PressFrame;
        _EpisodeCount++;
    }

    private void DoTryRecordAttempts()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        auto KeyName = intent_gym::k_Key_Souls_Charge_Kb.GetKeyName();
        auto PadName = intent_gym::k_Key_Souls_Charge_Pad.GetKeyName();

        auto FullLanded =
            intent_gym::Request_RecordAttempt(_FullAttempt, _Matcher, Sampler, n"Gym_SoulsCharge_Full_Key", KeyName) ||
            intent_gym::Request_RecordAttempt(_FullAttempt, _Matcher, Sampler, n"Gym_SoulsCharge_Full_Pad", PadName);

        auto QuickLanded =
            intent_gym::Request_RecordAttempt(_QuickAttempt, _Matcher, Sampler, n"Gym_SoulsCharge_Quick_Key", KeyName) ||
            intent_gym::Request_RecordAttempt(_QuickAttempt, _Matcher, Sampler, n"Gym_SoulsCharge_Quick_Pad", PadName);

        if (FullLanded || QuickLanded)
        { _ReportTicks = 0; }
    }

    private bool Get_IsWaiting()
    {
        if (ck::Is_NOT_Valid(_Matcher))
        { return false; }

        if (utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsCharge_Full_Key") == ECk_Intent_Phase::Pending)
        { return true; }

        return utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsCharge_Full_Pad") == ECk_Intent_Phase::Pending;
    }

    private int32 Get_LatestChargePressFrame(FCk_Handle_IntentSampler InSampler)
    {
        auto KeyFrame = intent_gym::Get_LatestPressFrame(InSampler, intent_gym::k_Key_Souls_Charge_Kb.GetKeyName());
        auto PadFrame = intent_gym::Get_LatestPressFrame(InSampler, intent_gym::k_Key_Souls_Charge_Pad.GetKeyName());

        if (PadFrame > KeyFrame)
        { return PadFrame; }

        return KeyFrame;
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Souls_Charge_Kb);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Souls_Charge_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Charge_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Souls_Charge_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Charge_Await);
            return;
        }

        if (_ReportTicks == 0 && _FullAttempt.Recorded && Current == UCk_IntentGym_Step_Souls_Charge_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Charge_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Souls_Charge_Report)
        { return; }

        _ReportTicks++;

        if (_ReportTicks > 90)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Charge_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Souls_Charge_Kb, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_BakedVerdict(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Countdown(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Episodes(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Outcomes(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto KeyName   = intent_gym::Format_Key(intent_gym::k_Key_Souls_Charge_Kb);
        auto PadName   = intent_gym::Format_Key(intent_gym::k_Key_Souls_Charge_Pad);
        auto Threshold = intent_gym::k_Souls_ChargeFrames;

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  Hold {KeyName} down and watch the countdown. At {Threshold} frames the", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  charge lands on its own.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  Then try letting go halfway and pressing it again - the count starts", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  over from the top, it does not resume.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  On a pad the same charge is on {PadName}.", gym_palette::Cyan);
    }

    private void Add_BakedVerdict(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Threshold = intent_gym::k_Souls_ChargeFrames;

        intent_gym::Add_Line(OutLines, "WHAT THE COMPILED SET SAYS THIS BUTTON MUST DO", gym_palette::White);

        if (_Verdict_Hold < 0)
        {
            intent_gym::Add_Line(OutLines, "  (the compiled set has not been read back yet)", gym_palette::Grey);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames it waits on a hold ",
            f"{Threshold}", f"{_Verdict_Hold}", _Verdict_Hold == Threshold);
        intent_gym::Add_Verdict(OutLines, "frames it waits on a chord",
            "0", f"{_Verdict_Chord}", _Verdict_Chord == 0);
    }

    // DISPLAY arithmetic on two recorded facts, and nothing else: the press row
    // this wait opened on, and the row the record is writing now. The count that
    // actually decides lives in the matcher and is not readable — which is why
    // this is a countdown to read, not the thing the outcome is graded from.
    private void Add_Countdown(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Sampler = intent_gym::TryGet_Sampler();

        intent_gym::Add_Line(OutLines, "THE WAIT", gym_palette::White);

        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no record yet - waiting for the local player's controller", gym_palette::Grey);
            return;
        }

        if (Get_IsWaiting() == false)
        {
            intent_gym::Add_Line(OutLines, "  no charge in flight - press and hold to open one", gym_palette::Grey);
            return;
        }

        auto Threshold = intent_gym::k_Souls_ChargeFrames;
        auto Now       = intent_gym::Get_LiveFrameIndex(Sampler);
        auto Remaining = _EpisodePressFrame + Threshold - Now;

        if (Remaining < 0)
        { Remaining = 0; }

        intent_gym::Add_Line(OutLines, "  the press is being held open - the matcher has not chosen yet", gym_palette::Amber);
        intent_gym::Add_Line(OutLines, f"  frames remaining  {Remaining}  (display: press frame + {Threshold} - now)", gym_palette::Amber);
        intent_gym::Add_Line(OutLines, "  Pending does not mean 'about to complete'. Let go now and the quick", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  move is what comes out instead.", gym_palette::White);
    }

    private void Add_Episodes(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "HOW MANY CHARGES YOU HAVE STARTED", gym_palette::White);

        auto Count = _EpisodeCount;
        auto Colour = Count > 0 ? gym_palette::Cyan : gym_palette::Grey;

        intent_gym::Add_Line(OutLines, f"  charges started   {Count}", Colour);
        intent_gym::Add_Line(OutLines, "  Counted off fresh press rows. Every press opens a NEW wait from zero;", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  a button that is merely still down carries nothing over.", gym_palette::White);
    }

    private void Add_Outcomes(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Threshold = intent_gym::k_Souls_ChargeFrames;
        auto Latest    = Threshold - 1;

        intent_gym::Add_Line(OutLines, "WHAT CAME OUT", gym_palette::White);

        if (_FullAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "charge  frames from press to answer", f"{Threshold} exactly");
        }
        else
        {
            auto FullName = _FullAttempt.IntentName;
            intent_gym::Add_Line(OutLines, f"  charge move that came out   {FullName}", gym_palette::White);

            if (_FullAttempt.PressFrame < 0)
            {
                intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so that charge cannot be", gym_palette::Amber);
                intent_gym::Add_Line(OutLines, "  measured. Hold another one.", gym_palette::Amber);
            }
            else
            {
                auto FullGap = _FullAttempt.DeferralFrames;
                intent_gym::Add_Verdict(OutLines, "charge  frames from press to answer", f"{Threshold} exactly",
                    f"{FullGap}", FullGap == Threshold);
            }
        }

        if (_QuickAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "abandon frames from press to answer", f"0..{Latest}");
            return;
        }

        if (_QuickAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The abandoned charge's press edge has left the record.", gym_palette::Amber);
            return;
        }

        auto QuickGap = _QuickAttempt.DeferralFrames;
        intent_gym::Add_Verdict(OutLines, "abandon frames from press to answer", f"0..{Latest}",
            f"{QuickGap}", QuickGap >= 0 && QuickGap < Threshold);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_SoulsCharge_Full_Key",  "full charge  (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_SoulsCharge_Quick_Key", "let go early (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_SoulsCharge_Full_Pad",  "full charge  (gamepad) ");
        Add_PhaseRow(OutLines, n"Gym_SoulsCharge_Quick_Pad", "let go early (gamepad) ");
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
