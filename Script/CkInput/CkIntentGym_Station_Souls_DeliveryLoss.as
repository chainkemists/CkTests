// Language=angelscript

//============================================================================
// CK INTENT SOULS GYM — DELIVERY LOSS STATION
//============================================================================
//
// A menu opens while you are mid-charge, and two things are true at once:
//
//   the FACT   your thumb never moved. The record still says the button is
//              down, frame by frame, because a record that lied about the
//              hardware would be useless for replay and for debugging alike.
//   the POLICY this layer stopped receiving the input, so its charge is over.
//              v1 ships the conservative default pair and this is the loss half
//              of it: Cancel. The episode ends, everything it was waiting on
//              goes Failed, and the accumulator is dropped.
//
// Then the menu closes, and the second half of the pair is what a player
// actually feels: RequireRePress. A button that is merely still physically down
// starts nothing. No wait re-opens, no charge resumes, and the thing that was
// interrupted does not come back on its own — only a fresh press edge opens a
// new episode. That is deliberately loud. A charge that quietly resumed would
// be a charge the player could not account for.
//
// THE MENU IS A REAL LAYER, NOT A FLAG. Pressing the menu key adds a Consume
// capture for the charge key on a HIGHER-PRIORITY layer, which is the same
// mechanism a modal, a vehicle or a cutscene uses; closing it removes the
// capture. Nothing here tells the matcher anything — the matcher works out on
// its own that it is no longer the one receiving that key, which is the whole
// claim being demonstrated.
//
// NOTHING ON THIS PANEL IS RED FOR BEING CANCELLED. A cancelled charge is the
// module answering correctly, so the verdicts that check it are GREEN when they
// match and the Failed phase itself is AMBER — a value legitimately in flight,
// per CkIntent anti-pattern 24. Red here would mean the policy did not fire.
//============================================================================

class UCk_EntityScript_IntentGym_Souls_DeliveryLoss : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    private FCk_Handle_InputLayer    _MoveLayer;
    private FCk_Handle_InputLayer    _MenuLayer;
    private FCk_Handle_IntentMatcher _Matcher;

    private FCk_Handle_StateMachine _StepMachine;
    private FCkGym_SmConfig         _StepConfig;

    private bool    _SwapRequested = false;
    private bool    _SwapRejected  = false;
    private FString _AuthoringError;

    private int32 _Verdict_Hold = -1;

    // The menu is toggled off a press EDGE read out of the record, so the key
    // needs no capture of its own and no second delivery channel. Priming stops
    // a press the player made seconds ago — the ring is four seconds deep and
    // outlives this station's composition — from opening a menu nobody asked
    // for on the first tick.
    private bool  _MenuOpen        = false;
    private bool  _MenuPollPrimed  = false;
    private int32 _MenuPressFrame  = -1;

    // What was true at the moment the charge died. Captured once, so the panel
    // still answers after the latch has decayed and the phases have gone quiet.
    private bool  _SawCancel               = false;
    private int32 _CancelFrame             = -1;
    private int32 _CancelPressFrame        = -1;
    private bool  _Cancel_MenuWasOpen      = false;
    private bool  _Cancel_QuickAlsoFailed  = false;
    private int32 _Cancel_CompletionFrame  = -1;
    private bool  _Cancel_ButtonStillDown  = false;

    private bool  _SawFreshPress        = false;
    private int32 _FreshPressFrame      = -1;
    private bool  _FreshPressOpenedWait = false;

    private int32 _ReportTicks = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_Souls_DeliveryLoss);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Souls_Loss_Arm);

        _StepConfig.Description = "A charge, a menu opening over it, and what is left when the menu closes.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_Loss_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_Loss_Await,  "Waiting for you to charge, then open the menu"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Souls_Loss_Report, "Reading back what the menu did to it"));

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
        DoPollMenuToggle();
        DoTrackCancel();
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

            _MoveLayer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Souls_DeliveryLoss));

            if (ck::Is_NOT_Valid(_MoveLayer))
            { return; }

            // The modal. It is created empty and stays empty until the player
            // opens it: a layer with no captures ends no walk, so an unopened
            // menu is indistinguishable from one that does not exist.
            _MenuLayer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Souls_Menu));

            if (ck::Is_NOT_Valid(_MenuLayer))
            { return; }

            auto MatcherParams = FCk_Fragment_IntentMatcher_ParamsData();
            MatcherParams.Set_LatchDecayFrames(intent_gym::k_LatchDecayFrames);

            FCk_Handle LayerEntity = _MoveLayer;
            _Matcher = utils_intent_matcher::Add(LayerEntity, MatcherParams);
        }

        if (ck::Is_NOT_Valid(_Matcher) || _SwapRequested)
        { return; }

        auto ButtonMap = intent_gym::TryGet_ButtonMap();
        if (ck::Is_NOT_Valid(ButtonMap))
        { return; }

        auto KeyReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Souls_Loss_Kb).Num() > 0;
        auto PadReady = utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Souls_Loss_Pad).Num() > 0;

        if (KeyReady == false || PadReady == false)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_souls_moves::MoveTable_Souls_DeliveryLoss.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"LS",  intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_Loss_Kb)));
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"LSP", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_Loss_Pad)));

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
            Set, intent_gym::Make_PhysicalButton(intent_gym::k_Key_Souls_Loss_Kb));

        _Verdict_Hold = Verdict.Get_HoldSiblingFrames();

        utils_intent_matcher::Request_SwapSet(_Matcher,
            FCk_Request_IntentMatcher_SwapSet(Set),
            FCk_Delegate_Request_OnCompleted(this, n"OnSwapCompleted"));

        _SwapRequested = true;
    }

    //------------------------------------------------------------------------
    // The menu
    //------------------------------------------------------------------------

    private void DoPollMenuToggle()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_MenuLayer))
        { return; }

        auto PressFrame = Get_LatestMenuPressFrame(Sampler);

        if (_MenuPollPrimed == false)
        {
            _MenuPollPrimed = true;
            _MenuPressFrame = PressFrame;
            return;
        }

        if (PressFrame < 0 || PressFrame == _MenuPressFrame)
        { return; }

        _MenuPressFrame = PressFrame;
        DoSetMenuOpen(_MenuOpen == false);
    }

    private void DoSetMenuOpen(bool InOpen)
    {
        _MenuOpen = InOpen;

        if (InOpen)
        {
            utils_input_layer::Request_AddCapture(_MenuLayer, FCk_Request_InputLayer_AddCapture(
                utils_input_layer::Make_KeyCapture(intent_gym::k_Key_Souls_Loss_Kb, ECk_InputLayer_CaptureBehavior::Consume)));

            utils_input_layer::Request_AddCapture(_MenuLayer, FCk_Request_InputLayer_AddCapture(
                utils_input_layer::Make_KeyCapture(intent_gym::k_Key_Souls_Loss_Pad, ECk_InputLayer_CaptureBehavior::Consume)));

            return;
        }

        utils_input_layer::Request_RemoveCapture(_MenuLayer, FCk_Request_InputLayer_RemoveCapture(
            ECk_InputLayer_CaptureMatch::Key, intent_gym::k_Key_Souls_Loss_Kb));

        utils_input_layer::Request_RemoveCapture(_MenuLayer, FCk_Request_InputLayer_RemoveCapture(
            ECk_InputLayer_CaptureMatch::Key, intent_gym::k_Key_Souls_Loss_Pad));
    }

    private int32 Get_LatestMenuPressFrame(FCk_Handle_IntentSampler InSampler)
    {
        auto KeyFrame = intent_gym::Get_LatestPressFrame(InSampler, intent_gym::k_Key_Souls_Menu_Kb.GetKeyName());
        auto PadFrame = intent_gym::Get_LatestPressFrame(InSampler, intent_gym::k_Key_Souls_Menu_Pad.GetKeyName());

        if (PadFrame > KeyFrame)
        { return PadFrame; }

        return KeyFrame;
    }

    //------------------------------------------------------------------------
    // Reading the result
    //------------------------------------------------------------------------

    private void DoTrackCancel()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        if (_SawCancel == false && Get_ChargeFailed())
        {
            _SawCancel = true;
            _CancelFrame = intent_gym::Get_LiveFrameIndex(Sampler);
            _CancelPressFrame = Get_LatestChargePressFrame(Sampler);
            _Cancel_MenuWasOpen = _MenuOpen;
            _Cancel_QuickAlsoFailed = Get_QuickFailed();
            _Cancel_CompletionFrame = Get_ChargeCompletionFrame();
            _Cancel_ButtonStillDown = Get_ChargeHeld(Sampler);
            return;
        }

        if (_SawCancel == false)
        { return; }

        auto PressFrame = Get_LatestChargePressFrame(Sampler);

        if (_SawFreshPress == false)
        {
            if (PressFrame <= _CancelPressFrame)
            { return; }

            _SawFreshPress = true;
            _FreshPressFrame = PressFrame;
        }

        if (_FreshPressOpenedWait == false && Get_ChargeWaiting())
        { _FreshPressOpenedWait = true; }
    }

    private bool Get_ChargeWaiting()
    {
        if (utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Full_Key") == ECk_Intent_Phase::Pending)
        { return true; }

        return utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Full_Pad") == ECk_Intent_Phase::Pending;
    }

    private bool Get_ChargeFailed()
    {
        if (utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Full_Key") == ECk_Intent_Phase::Failed)
        { return true; }

        return utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Full_Pad") == ECk_Intent_Phase::Failed;
    }

    private bool Get_QuickFailed()
    {
        if (utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Quick_Key") == ECk_Intent_Phase::Failed)
        { return true; }

        return utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Quick_Pad") == ECk_Intent_Phase::Failed;
    }

    private bool Get_ChargeCompleted()
    {
        if (utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Full_Key") == ECk_Intent_Phase::Completed)
        { return true; }

        return utils_intent_matcher::Get_IntentPhase_ByName(_Matcher, n"Gym_SoulsLoss_Full_Pad") == ECk_Intent_Phase::Completed;
    }

    private int32 Get_ChargeCompletionFrame()
    {
        auto KeyFrame = utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"Gym_SoulsLoss_Full_Key");

        if (KeyFrame >= 0)
        { return KeyFrame; }

        return utils_intent_matcher::TryGet_CompletionFrame_ByName(_Matcher, n"Gym_SoulsLoss_Full_Pad");
    }

    private int32 Get_LatestChargePressFrame(FCk_Handle_IntentSampler InSampler)
    {
        auto KeyFrame = intent_gym::Get_LatestPressFrame(InSampler, intent_gym::k_Key_Souls_Loss_Kb.GetKeyName());
        auto PadFrame = intent_gym::Get_LatestPressFrame(InSampler, intent_gym::k_Key_Souls_Loss_Pad.GetKeyName());

        if (PadFrame > KeyFrame)
        { return PadFrame; }

        return KeyFrame;
    }

    private bool Get_ChargeHeld(FCk_Handle_IntentSampler InSampler)
    {
        if (intent_gym::Get_IsButtonHeld(InSampler, intent_gym::k_Key_Souls_Loss_Kb.GetKeyName()))
        { return true; }

        return intent_gym::Get_IsButtonHeld(InSampler, intent_gym::k_Key_Souls_Loss_Pad.GetKeyName());
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Souls_Loss_Kb);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Souls_Loss_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Loss_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Souls_Loss_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Loss_Await);
            return;
        }

        if (_ReportTicks == 0 && _SawCancel && Current == UCk_IntentGym_Step_Souls_Loss_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Loss_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Souls_Loss_Report)
        { return; }

        _ReportTicks++;

        if (_ReportTicks > 150)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Souls_Loss_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Souls_Loss_Kb, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_MenuState(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_LayerStack(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Delivery(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_CancelVerdicts(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_RePressVerdicts(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto ChargeKey = intent_gym::Format_Key(intent_gym::k_Key_Souls_Loss_Kb);
        auto MenuName  = intent_gym::Format_Key(intent_gym::k_Key_Souls_Menu_Kb);
        auto PadName   = intent_gym::Format_Key(intent_gym::k_Key_Souls_Loss_Pad);
        auto Threshold = intent_gym::k_Souls_LossFrames;

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  1. Press and HOLD {ChargeKey}. It is a {Threshold}-frame charge.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  2. While still holding it, tap {MenuName}. That opens a menu over you.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  3. KEEP HOLDING. Watch the charge die.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  4. Tap {MenuName} again to close the menu, and STILL keep holding.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "     Nothing comes back. Only letting go and pressing again starts one.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  On a pad the charge is {PadName}.", gym_palette::Cyan);
    }

    private void Add_MenuState(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "THE MENU", gym_palette::White);

        if (_MenuOpen)
        {
            intent_gym::Add_Line(OutLines, "  OPEN - it is consuming the charge key, so this station receives none of it", gym_palette::Amber);
            return;
        }

        intent_gym::Add_Line(OutLines, "  closed - nothing above this station is ending the walk", gym_palette::Grey);
    }

    private void Add_LayerStack(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto MenuPriority = intent_gym::k_LayerPriority_Souls_Menu;
        auto MovePriority = intent_gym::k_LayerPriority_Souls_DeliveryLoss;

        intent_gym::Add_Line(OutLines, "THE LAYER STACK, AS THIS STATION SEES IT", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  layers this station owns   2  (top to bottom)", gym_palette::White);

        auto MenuLine = "no captures - ends no walk";
        auto MenuColour = gym_palette::Grey;

        if (_MenuOpen)
        {
            MenuLine = "consuming the charge key";
            MenuColour = gym_palette::Amber;
        }

        intent_gym::Add_Line(OutLines, f"  {MenuPriority}  the menu       {MenuLine}", MenuColour);
        intent_gym::Add_Line(OutLines, f"  {MovePriority}  the move set   the matcher's own captures live here", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  A layer only ever sees what nothing above it consumed, which is the", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  whole of how a modal silences a move set without either one knowing", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  the other exists.", gym_palette::White);
    }

    // Read off the RECORD's delivery outcomes rather than off anything this
    // station remembers: the router writes one row per routed event saying what
    // it did with it, and that is the only account of the walk there is.
    private void Add_Delivery(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHO RECEIVED YOUR LAST PRESS OF THE CHARGE KEY", gym_palette::White);

        auto Sampler = intent_gym::TryGet_Sampler();

        if (ck::Is_NOT_Valid(Sampler))
        {
            intent_gym::Add_Line(OutLines, "  no record yet - waiting for the local player's controller", gym_palette::Grey);
            return;
        }

        auto Count = utils_intent_sampler::Get_FrameCount(Sampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(Sampler, Offset);
            auto Routed = Row.Get_RoutedEvents();

            for (auto Index = 0; Index < Routed.Num(); Index++)
            {
                auto EventKey = Routed[Index].Get_Event().Get_Key();

                if (EventKey != intent_gym::k_Key_Souls_Loss_Kb && EventKey != intent_gym::k_Key_Souls_Loss_Pad)
                { continue; }

                Add_DeliveryRow(OutLines, Row.Get_FrameIndex(), Routed[Index]);
                Add_DeliveryCaveat(OutLines);
                return;
            }
        }

        intent_gym::Add_Line(OutLines, "  nothing yet - press the charge key", gym_palette::Grey);
    }

    private void Add_DeliveryRow(
        TArray<FCkGym_ColoredLine>& OutLines,
        int32 InFrame,
        const FCk_InputLayer_RoutedEvent&in InRouted)
    {
        auto Outcome = InRouted.Get_Outcome();

        if (Outcome != ECk_InputLayer_DeliveryOutcome::ConsumedByLayer)
        {
            intent_gym::Add_Line(OutLines, f"  frame {InFrame}  nothing ended the walk  ({Outcome :n})", gym_palette::White);
            return;
        }

        if (InRouted.Get_ConsumingLayer() == _MenuLayer)
        {
            intent_gym::Add_Line(OutLines, f"  frame {InFrame}  the MENU layer ended the walk - this station never saw it", gym_palette::Amber);
            return;
        }

        if (InRouted.Get_ConsumingLayer() == _MoveLayer)
        {
            intent_gym::Add_Line(OutLines, f"  frame {InFrame}  this station's move layer received it", gym_palette::Green);
            return;
        }

        intent_gym::Add_Line(OutLines, f"  frame {InFrame}  a layer that is neither of this station's ended the walk", gym_palette::White);
    }

    private void Add_DeliveryCaveat(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "  Delivery outcomes describe EVENTS. A button that is merely still down", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  routes nothing, so this line only moves when you press again - which is", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  exactly why the module asks the question live instead of reading a row.", gym_palette::White);
    }

    private void Add_CancelVerdicts(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto Threshold = intent_gym::k_Souls_LossFrames;

        intent_gym::Add_Line(OutLines, "WHAT THE MENU DID TO THE CHARGE", gym_palette::White);

        if (_Verdict_Hold >= 0)
        {
            intent_gym::Add_Verdict(OutLines, "frames this button waits on a hold",
                f"{Threshold}", f"{_Verdict_Hold}", _Verdict_Hold == Threshold);
        }

        if (_SawCancel == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "the interrupted charge  ", "cancelled, and nothing completed");
            return;
        }

        auto CancelFrame = _CancelFrame;

        intent_gym::Add_Line(OutLines, f"  the charge was cancelled on frame {CancelFrame}", gym_palette::Amber);
        intent_gym::Add_Line(OutLines, "  The menu ate your charge. That is the DEFAULT policy and it is loud on", gym_palette::Amber);
        intent_gym::Add_Line(OutLines, "  purpose: a charge that quietly survived a modal would be one the player", gym_palette::Amber);
        intent_gym::Add_Line(OutLines, "  could not account for.", gym_palette::Amber);

        intent_gym::Add_Verdict(OutLines, "the menu was open when it died",
            "yes", intent_gym::Format_Bool(_Cancel_MenuWasOpen), _Cancel_MenuWasOpen);

        intent_gym::Add_Verdict(OutLines, "the quick move died with it   ",
            "yes", intent_gym::Format_Bool(_Cancel_QuickAlsoFailed), _Cancel_QuickAlsoFailed);

        intent_gym::Add_Verdict(OutLines, "frame the charge completed on ",
            "none", f"{_Cancel_CompletionFrame}", _Cancel_CompletionFrame < 0);

        intent_gym::Add_Verdict(OutLines, "the record still says it is down",
            "yes", intent_gym::Format_Bool(_Cancel_ButtonStillDown), _Cancel_ButtonStillDown);

        intent_gym::Add_Line(OutLines, "  The last two together are the whole point: the FACT that your thumb", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  never moved, and the POLICY that this layer's charge is over anyway.", gym_palette::White);
    }

    private void Add_RePressVerdicts(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHAT HAPPENS IF YOU JUST KEEP HOLDING", gym_palette::White);

        if (_SawCancel == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "holding on after the menu ", "no new charge");
            intent_gym::Add_Verdict_Pending(OutLines, "pressing again            ", "a new charge opens");
            return;
        }

        auto Sampler = intent_gym::TryGet_Sampler();

        if (ck::Is_NOT_Valid(Sampler))
        { return; }

        if (_SawFreshPress == false)
        {
            auto StillDown = Get_ChargeHeld(Sampler);
            auto ReArmed = Get_ChargeWaiting() || Get_ChargeCompleted();

            if (StillDown == false)
            {
                intent_gym::Add_Line(OutLines, "  you let go - press again to see a fresh charge open", gym_palette::Grey);
            }

            auto ReArmedText = "nothing opened";
            if (ReArmed)
            { ReArmedText = "a charge opened with no fresh press"; }

            intent_gym::Add_Verdict(OutLines, "holding on after the menu ",
                "no new charge", ReArmedText, ReArmed == false);

            intent_gym::Add_Verdict_Pending(OutLines, "pressing again            ", "a new charge opens");
            return;
        }

        intent_gym::Add_Verdict(OutLines, "holding on after the menu ",
            "no new charge", "nothing opened, then you pressed again", true);

        if (_FreshPressOpenedWait)
        {
            intent_gym::Add_Verdict(OutLines, "pressing again            ",
                "a new charge opens", "it opened", true);
            return;
        }

        auto Now = intent_gym::Get_LiveFrameIndex(Sampler);
        auto FramesSince = Now - _FreshPressFrame;

        if (FramesSince < 10)
        {
            intent_gym::Add_Line(OutLines, "  a fresh press just landed - waiting for the new charge to open", gym_palette::Amber);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "pressing again            ",
            "a new charge opens", "nothing opened", false);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_SoulsLoss_Full_Key",  "the charge   (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_SoulsLoss_Quick_Key", "let go early (keyboard)");
        Add_PhaseRow(OutLines, n"Gym_SoulsLoss_Full_Pad",  "the charge   (gamepad) ");
        Add_PhaseRow(OutLines, n"Gym_SoulsLoss_Quick_Pad", "let go early (gamepad) ");

        intent_gym::Add_Line(OutLines, "  Failed here is not a fault. It is the honest answer to a press that", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  ended up matching nothing at all, so it is amber and it clears itself", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  the next time you press.", gym_palette::White);
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
