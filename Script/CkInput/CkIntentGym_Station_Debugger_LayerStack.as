// Language=angelscript

//============================================================================
// CK INTENT DEBUGGER GYM — LAYER STACK AND MASKING STATION
//============================================================================
//
// Two layers, one key, and a masker the viewer arms and disarms by hand. The
// layer-stack view is the debugger's selection surface and the one panel a
// reader is looking at when they ask "why did nothing happen" — so this station
// exists to make that view MOVE while they watch it, and to print the same three
// facts it is showing so the two can be compared line for line:
//
//   the STACK     two rows, adjacent priorities, top-down. The higher one is a
//                 masker that carries nothing until you arm it.
//   the CAPTURES  a layer's declarative rows. An armed masker has exactly one,
//                 a Consume for this station's key; a disarmed one has none, and
//                 a layer with no captures ends no walk.
//   the DELIVERY  who ended the routing walk for your last press. That is not a
//                 property of the stack, it is the router's own account of one
//                 event, and it is the only thing that can say a press was eaten
//                 rather than merely unmatched.
//
// THE MASKER IS A REAL LAYER, NOT A FLAG. Arming it adds a Consume capture on a
// higher-priority layer, which is the same mechanism a modal, a vehicle or a
// cutscene uses. Nothing tells the matcher anything — it simply stops being the
// one that receives the key, and the phases go quiet on their own.
//
// A CAPTURE EDIT IS NOT VISIBLE THIS FRAME, and the panel says so rather than
// hiding it. `Get_Captures` reads the DRAINED state, so the row count trails the
// keypress by a frame; the debugger reads the same function and trails it
// identically, which is exactly why the two are worth comparing.
//============================================================================

class UCk_EntityScript_IntentGym_Debugger_LayerStack : UCk_GenericEntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    UPROPERTY(ExposeOnSpawn)
    FString StationTitle;

    UPROPERTY(ExposeOnSpawn)
    FString StationDescription;

    private FCk_Handle_InputLayer    _MoveLayer;
    private FCk_Handle_InputLayer    _MaskLayer;
    private FCk_Handle_IntentMatcher _Matcher;

    private FCk_Handle_StateMachine _StepMachine;
    private FCkGym_SmConfig         _StepConfig;

    private bool    _SwapRequested = false;
    private bool    _SwapRejected  = false;
    private FString _AuthoringError;

    // The masker is toggled off a press EDGE read out of the record, so the key
    // needs no capture of its own and no second delivery channel. Priming stops
    // a press the player made seconds ago — the ring is four seconds deep and
    // outlives this station's composition — from arming a mask nobody asked for
    // on the first tick.
    private bool  _MaskArmed        = false;
    private bool  _TogglePrimed     = false;
    private int32 _TogglePressFrame = -1;

    // What was true for the last press of the masked key: the frame, whether the
    // mask was armed at the time, and the router's account of where it went.
    // Paired at capture time because the viewer will arm and disarm again while
    // reading, and a verdict re-derived later would be about a different press.
    private int32 _LastPress_Frame      = -1;
    private bool  _LastPress_MaskArmed  = false;
    private bool  _LastPress_HasOutcome = false;
    private bool  _LastPress_ByMask     = false;
    private bool  _LastPress_ByMove     = false;

    private ECk_InputLayer_DeliveryOutcome _LastPress_Outcome = ECk_InputLayer_DeliveryOutcome::PassedThrough;

    private FCkIntentGym_Attempt _MoveAttempt;
    private int32                _ReportTicks = 0;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow
    DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        utils_entity_tag::Add(InHandle, intent_gym::k_Tag_Debugger_LayerStack);
        utils_timer::Create_Tick(InHandle, FCk_Delegate_Timer(this, n"OnDisplayTick"));

        _StepMachine = gym_sm::Setup(InHandle, UCk_IntentGym_Step_Debugger_Mask_Arm);

        _StepConfig.Description = "Two layers on one key, and the moment the upper one takes it away.";
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Mask_Arm,    "Load the move set"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Mask_Await,  "Waiting for a press, masked or not"));
        _StepConfig.Steps.Add(FCkGym_SmStep(UCk_IntentGym_Step_Debugger_Mask_Report, "Reading back who received it"));

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
        DoPollMaskToggle();
        DoTrackPresses();
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

            _MoveLayer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Debugger_LayerStack));

            if (ck::Is_NOT_Valid(_MoveLayer))
            { return; }

            // The masker. It is created empty and stays empty until the player
            // arms it: a layer with no captures ends no walk, so a disarmed
            // masker is indistinguishable from one that does not exist.
            _MaskLayer = utils_input_layer::Create(SelfEntity,
                FCk_Fragment_InputLayer_ParamsData(Source, intent_gym::k_LayerPriority_Debugger_Mask));

            if (ck::Is_NOT_Valid(_MaskLayer))
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

        if (utils_input_button_map::Get_ButtonIdsForKey(ButtonMap, intent_gym::k_Key_Debugger_Masked).Num() == 0)
        { return; }

        DoRequestSwap();
    }

    private void DoRequestSwap()
    {
        TArray<FCkTests_Intent_MoveRow> Rows = intent_gym_debugger_moves::MoveTable_Debugger_LayerStack.Rows;

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
        ButtonRows.Add(FCk_Intent_ButtonNameRow(n"LM", intent_gym::Make_PhysicalButton(intent_gym::k_Key_Debugger_Masked)));

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
    // The masker
    //------------------------------------------------------------------------

    private void DoPollMaskToggle()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_MaskLayer))
        { return; }

        auto PressFrame = intent_gym::Get_LatestPressFrame(Sampler, intent_gym::k_Key_Debugger_Menu.GetKeyName());

        if (_TogglePrimed == false)
        {
            _TogglePrimed = true;
            _TogglePressFrame = PressFrame;
            return;
        }

        if (PressFrame < 0 || PressFrame == _TogglePressFrame)
        { return; }

        _TogglePressFrame = PressFrame;
        DoSetMaskArmed(_MaskArmed == false);
    }

    private void DoSetMaskArmed(bool InArmed)
    {
        _MaskArmed = InArmed;

        if (InArmed)
        {
            utils_input_layer::Request_AddCapture(_MaskLayer, FCk_Request_InputLayer_AddCapture(
                utils_input_layer::Make_KeyCapture(intent_gym::k_Key_Debugger_Masked, ECk_InputLayer_CaptureBehavior::Consume)));

            return;
        }

        utils_input_layer::Request_RemoveCapture(_MaskLayer, FCk_Request_InputLayer_RemoveCapture(
            ECk_InputLayer_CaptureMatch::Key, intent_gym::k_Key_Debugger_Masked));
    }

    //------------------------------------------------------------------------
    // Reading the result
    //------------------------------------------------------------------------

    private void DoTrackPresses()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler))
        { return; }

        auto PressFrame = intent_gym::Get_LatestPressFrame(Sampler, intent_gym::k_Key_Debugger_Masked.GetKeyName());

        if (PressFrame >= 0 && PressFrame != _LastPress_Frame)
        {
            _LastPress_Frame = PressFrame;
            _LastPress_MaskArmed = _MaskArmed;
            _LastPress_HasOutcome = false;
            _LastPress_ByMask = false;
            _LastPress_ByMove = false;
        }

        if (_LastPress_Frame < 0 || _LastPress_HasOutcome)
        { return; }

        DoReadDeliveryForLastPress(Sampler);
    }

    // Read off the RECORD's delivery outcomes rather than off anything this
    // station remembers: the router writes one row per routed event saying what
    // it did with it, and that is the only account of the walk there is.
    private void DoReadDeliveryForLastPress(FCk_Handle_IntentSampler InSampler)
    {
        auto Count = utils_intent_sampler::Get_FrameCount(InSampler);

        for (auto Offset = 0; Offset < Count; Offset++)
        {
            auto Row = utils_intent_sampler::TryGet_FrameAtOffset(InSampler, Offset);

            if (Row.Get_FrameIndex() != _LastPress_Frame)
            { continue; }

            auto Routed = Row.Get_RoutedEvents();

            for (auto Index = 0; Index < Routed.Num(); Index++)
            {
                if (Routed[Index].Get_Event().Get_Key() != intent_gym::k_Key_Debugger_Masked)
                { continue; }

                _LastPress_Outcome = Routed[Index].Get_Outcome();
                _LastPress_ByMask = Routed[Index].Get_ConsumingLayer() == _MaskLayer;
                _LastPress_ByMove = Routed[Index].Get_ConsumingLayer() == _MoveLayer;
                _LastPress_HasOutcome = true;
                return;
            }

            return;
        }
    }

    private void DoTryRecordAttempts()
    {
        auto Sampler = intent_gym::TryGet_Sampler();
        if (ck::Is_NOT_Valid(Sampler) || ck::Is_NOT_Valid(_Matcher))
        { return; }

        auto KeyName = intent_gym::k_Key_Debugger_Masked.GetKeyName();

        auto Landed =
            intent_gym::Request_RecordAttempt(_MoveAttempt, _Matcher, Sampler, n"Gym_Dbg_Mask_Move",   KeyName) ||
            intent_gym::Request_RecordAttempt(_MoveAttempt, _Matcher, Sampler, n"Gym_Dbg_Mask_Motion", KeyName);

        if (Landed)
        { _ReportTicks = 0; }
    }

    private int32 Get_MaskCaptureCount()
    {
        if (ck::Is_NOT_Valid(_MaskLayer))
        { return 0; }

        return utils_input_layer::Get_Captures(_MaskLayer).Num();
    }

    //------------------------------------------------------------------------
    // The graph
    //------------------------------------------------------------------------

    private void DoAdvanceSteps()
    {
        if (ck::Is_NOT_Valid(_StepMachine))
        { return; }

        auto Current = utils_state_machine::Get_CurrentStateClass(_StepMachine);
        auto Armed = intent_gym::Get_IsArmed(_Matcher, intent_gym::k_Key_Debugger_Masked);

        if (Armed == false)
        {
            if (Current != UCk_IntentGym_Step_Debugger_Mask_Arm)
            { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Mask_Arm); }
            return;
        }

        if (Current == UCk_IntentGym_Step_Debugger_Mask_Arm)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Mask_Await);
            return;
        }

        if (_ReportTicks == 0 && _LastPress_HasOutcome && Current == UCk_IntentGym_Step_Debugger_Mask_Await)
        {
            gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Mask_Report);
            return;
        }

        if (Current != UCk_IntentGym_Step_Debugger_Mask_Report)
        { return; }

        _ReportTicks++;

        if (_ReportTicks > 90)
        { gym_sm::Request_GoToStep(_StepMachine, UCk_IntentGym_Step_Debugger_Mask_Await); }
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
        intent_gym::Add_ArmingStatus(Lines, _Matcher, intent_gym::k_Key_Debugger_Masked, _SwapRejected);

        if (_AuthoringError != "")
        { intent_gym::Add_Line(Lines, f"  {_AuthoringError}", gym_palette::Red); }

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Instruction(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_WhatTheViewShouldShow(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_LayerStack(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Delivery(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Verdicts(Lines);

        intent_gym::Add_Spacer(Lines, gym_palette::White);
        Add_Phases(Lines);

        CkGym_Common::Update_StationDisplay_Colored(
            SelfEntity, StationTitle, Lines, StationDescription);
    }

    private void Add_Instruction(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto MoveKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Masked);
        auto MenuKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Menu);

        intent_gym::Add_Line(OutLines, "DO THIS", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  1. Tap {MoveKey}. The move answers on the frame you pressed it.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  2. Tap {MenuKey} to ARM the masker above this station.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  3. Tap {MoveKey} again. Nothing comes out - and nothing is broken.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  4. Tap {MenuKey} again to disarm it, and press once more.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  This station is keyboard-only - no stick is needed for any of it.", gym_palette::White);
    }

    private void Add_WhatTheViewShouldShow(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto MaskPriority = intent_gym::k_LayerPriority_Debugger_Mask;
        auto MovePriority = intent_gym::k_LayerPriority_Debugger_LayerStack;
        auto MoveKey = intent_gym::Format_Key(intent_gym::k_Key_Debugger_Masked);
        auto MoveCount = intent_gym_debugger_moves::k_LayerStack_MoveCount;

        intent_gym::Add_DebuggerViewHeader(OutLines, "LAYER STACK VIEW");
        intent_gym::Add_Line(OutLines, f"  EXPECT this station's two layers at priorities {MaskPriority} and {MovePriority},", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  adjacent and in that order, the masker above the move set.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  While the masker is ARMED it grows one capture row naming {MoveKey} with", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  behaviour Consume; while it is disarmed it has none at all.", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, f"  The lower row's matcher summary keeps its {MoveCount} moves and its", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  registered terminal key EITHER WAY - masking is not unloading, and", gym_palette::Cyan);
        intent_gym::Add_Line(OutLines, "  that is the distinction this station exists to show.", gym_palette::Cyan);
    }

    private void Add_LayerStack(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto MaskPriority = intent_gym::k_LayerPriority_Debugger_Mask;
        auto MovePriority = intent_gym::k_LayerPriority_Debugger_LayerStack;

        intent_gym::Add_Line(OutLines, "THE SAME TWO LAYERS, AS THIS STATION SEES THEM", gym_palette::White);

        if (ck::Is_NOT_Valid(_MaskLayer) || ck::Is_NOT_Valid(_MoveLayer))
        {
            intent_gym::Add_Line(OutLines, "  no layers yet - waiting for the local player's input source", gym_palette::Grey);
            return;
        }

        auto MaskColour = _MaskArmed ? gym_palette::Amber : gym_palette::Grey;
        auto MaskCaptures = Get_MaskCaptureCount();
        auto MoveCaptures = utils_input_layer::Get_Captures(_MoveLayer).Num();

        intent_gym::Add_Line(OutLines, f"  {MaskPriority}  the masker     captures {MaskCaptures}", MaskColour);
        Add_CaptureRows(OutLines, _MaskLayer);

        intent_gym::Add_Line(OutLines, f"  {MovePriority}  the move set   captures {MoveCaptures}", gym_palette::White);
        Add_CaptureRows(OutLines, _MoveLayer);

        intent_gym::Add_Line(OutLines, "  The move set's captures are not this station's doing - they follow the", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  SET, registered by the swap and moved by a rebind. A capture edit is", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  deferred, so these counts land a frame after the key that changed them.", gym_palette::White);
    }

    private void Add_CaptureRows(TArray<FCkGym_ColoredLine>& OutLines, FCk_Handle_InputLayer InLayer)
    {
        TArray<FCk_InputLayer_Capture> Captures = utils_input_layer::Get_Captures(InLayer);

        for (auto Index = 0; Index < Captures.Num(); Index++)
        {
            auto Behavior = Captures[Index].Get_Behavior();
            auto MatchMode = Captures[Index].Get_MatchMode();
            auto KeyName = intent_gym::Format_Key(Captures[Index].Get_Key());

            intent_gym::Add_Line(OutLines, f"        {MatchMode :n}  {KeyName}  {Behavior :n}", gym_palette::White);
        }
    }

    private void Add_Delivery(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHO RECEIVED YOUR LAST PRESS", gym_palette::White);

        if (_LastPress_Frame < 0)
        {
            intent_gym::Add_Line(OutLines, "  nothing yet - press the station's key", gym_palette::Grey);
            return;
        }

        if (_LastPress_HasOutcome == false)
        {
            intent_gym::Add_Line(OutLines, f"  frame {_LastPress_Frame}  the record has the press, no routed row for it", gym_palette::Amber);
            return;
        }

        auto Outcome = _LastPress_Outcome;

        if (_LastPress_ByMask)
        {
            intent_gym::Add_Line(OutLines, f"  frame {_LastPress_Frame}  the MASKER ended the walk - the move set never saw it", gym_palette::Amber);
        }
        else if (_LastPress_ByMove)
        {
            intent_gym::Add_Line(OutLines, f"  frame {_LastPress_Frame}  this station's move layer received it", gym_palette::Green);
        }
        else if (Outcome == ECk_InputLayer_DeliveryOutcome::ConsumedByLayer)
        {
            intent_gym::Add_Line(OutLines, f"  frame {_LastPress_Frame}  a layer that is neither of this station's ended the walk", gym_palette::White);
        }
        else
        {
            intent_gym::Add_Line(OutLines, f"  frame {_LastPress_Frame}  nothing ended the walk  ({Outcome :n})", gym_palette::White);
        }

        intent_gym::Add_Line(OutLines, f"  the masker was armed when it landed   {intent_gym::Format_Bool(_LastPress_MaskArmed)}", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  Delivery outcomes describe EVENTS. A button that is merely still down", gym_palette::White);
        intent_gym::Add_Line(OutLines, "  routes nothing, so this line only moves when you press again.", gym_palette::White);
    }

    private void Add_Verdicts(TArray<FCkGym_ColoredLine>& OutLines)
    {
        auto MoveCount = intent_gym_debugger_moves::k_LayerStack_MoveCount;

        intent_gym::Add_Line(OutLines, "WHAT MUST BE TRUE", gym_palette::White);

        auto Captures = Get_MaskCaptureCount();
        auto ExpectedCaptures = _MaskArmed ? 1 : 0;

        auto CaptureState = FString("disarmed");
        if (_MaskArmed)
        { CaptureState = "armed"; }

        intent_gym::Add_Verdict(OutLines, f"masker captures while {CaptureState}",
            f"{ExpectedCaptures}", f"{Captures}", Captures == ExpectedCaptures);

        if (ck::IsValid(_Matcher))
        {
            auto Loaded = utils_intent_matcher::Get_ActiveIntentCount(_Matcher);

            intent_gym::Add_Verdict(OutLines, "moves still loaded under the mask",
                f"{MoveCount}", f"{Loaded}", Loaded == MoveCount);
        }

        if (_LastPress_HasOutcome == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "where the last press went  ", "the masker if it was armed, this station if not");
            return;
        }

        if (_LastPress_MaskArmed)
        {
            auto Got = FString("not the masker");
            if (_LastPress_ByMask)
            { Got = "eaten by the masker"; }

            intent_gym::Add_Verdict(OutLines, "where the last press went  ",
                "eaten by the masker", Got, _LastPress_ByMask);
            return;
        }

        auto GotUnmasked = FString("somewhere else");
        if (_LastPress_ByMove)
        { GotUnmasked = "this station's move layer"; }

        intent_gym::Add_Verdict(OutLines, "where the last press went  ",
            "this station's move layer", GotUnmasked, _LastPress_ByMove);
    }

    private void Add_Phases(TArray<FCkGym_ColoredLine>& OutLines)
    {
        intent_gym::Add_Line(OutLines, "WHERE EACH MOVE STANDS", gym_palette::White);

        if (ck::Is_NOT_Valid(_Matcher))
        {
            intent_gym::Add_Line(OutLines, "  no matcher yet", gym_palette::Grey);
            return;
        }

        Add_PhaseRow(OutLines, n"Gym_Dbg_Mask_Move",   "the press           ");
        Add_PhaseRow(OutLines, n"Gym_Dbg_Mask_Motion", "motion + the press  ");

        if (_MoveAttempt.Recorded == false)
        {
            intent_gym::Add_Verdict_Pending(OutLines, "frames from press to answer", "0");
            return;
        }

        if (_MoveAttempt.PressFrame < 0)
        {
            intent_gym::Add_Line(OutLines, "  The press edge is no longer in the record, so the last unmasked", gym_palette::Amber);
            intent_gym::Add_Line(OutLines, "  attempt cannot be measured. Press again.", gym_palette::Amber);
            return;
        }

        intent_gym::Add_Verdict(OutLines, "frames from press to answer",
            "0", f"{_MoveAttempt.DeferralFrames}", _MoveAttempt.DeferralFrames == 0);
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
