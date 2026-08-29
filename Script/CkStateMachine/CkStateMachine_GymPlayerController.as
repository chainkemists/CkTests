class ACk_SmTest_GymPlayerController : ACk_Gym_Base_PlayerController
{
    // ========================================================================
    // STATION DEFINITION
    // ========================================================================

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.AutoCycle");
            Station.Title = FText::FromString("AUTO CYCLE");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("State machine cycles: Idle -> Patrol -> Alert."));
            Description.Add(FText::FromString("Tests SM creation, auto-start, transitions, and signal binding."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.PauseResume");
            Station.Title = FText::FromString("PAUSE / RESUME");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("State machine pauses after 6 transitions, resumes after 3 seconds."));
            Description.Add(FText::FromString("Tests SM pause and resume functionality."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.Complex");
            Station.Title = FText::FromString("COMPLEX GRAPH");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("6-state SM: Idle, Patrol, Chase, Attack, Search, Flee."));
            Description.Add(FText::FromString("Tests branching, bidirectional, multi-condition transitions, polled + event conditions, tasks."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.Hierarchical");
            Station.Title = FText::FromString("HIERARCHICAL (SUB-SM)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Parent SM: Approach -> Engage -> Retreat."));
            Description.Add(FText::FromString("Engage spawns a child SM: WindUp -> Strike -> Recover (cycles)."));
            Description.Add(FText::FromString("Tests UCk_SmTask_SubStateMachine, context propagation, viewer drill-down."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.GraphWalkRegression");
            Station.Title = FText::FromString("GRAPH-WALK REGRESSION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Guards CkFoundation PR #643: graph-walk temp entities must not fire task DoEnterTask bodies."));
            Description.Add(FText::FromString("Constructs two 5-state linear SMs (top-level + sub-SM) gated by polled-false conditions."));
            Description.Add(FText::FromString("PASS = only initial states incremented counters, both SMs still Running."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.DivergenceFirstBranch");
            Station.Title = FText::FromString("DIVERGENCE FIRST-BRANCH");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Sub-SM with a divergence-point state (two outgoing transitions). Asserts that the first-added transition's target state-task chain is built exactly once when that branch is chosen."));
            Description.Add(FText::FromString("Vacuous-transition variant: linear hops have no conditions, so transitions Pass on first evaluation. Exercises the fast-path race window between transition-firing and source-state teardown."));
            Description.Add(FText::FromString("Two passes (Pass A: AddLeft-first + ChooseLeft; Pass B: AddRight-first + ChooseRight) confirm doubling tracks add-order, not state class or direction."));
            Description.Add(FText::FromString("PASS = every per-state task counter == 1. FAIL = first-added-and-chosen branch counter == 2."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.DivergenceTimed");
            Station.Title = FText::FromString("DIVERGENCE FIRST-BRANCH (TIMED)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Same divergence-point assertion as DIVERGENCE FIRST-BRANCH, but every linear transition is gated by a 0.05s event-driven timer condition. Exercises the slow-path race: condition Pass arrives asynchronously while the source state is in PendingExit."));
            Description.Add(FText::FromString("Together with the vacuous variant, covers both immediate-Pass and timer-Pass divergence handling during state teardown."));
            Description.Add(FText::FromString("Toggle the framework fix off and rebuild to confirm this station FAILs with the bug present (chosen-and-first-added counter reads 2)."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.RacingEventDriven");
            Station.Title = FText::FromString("RACING EVENT-DRIVEN");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("State with two racing event-driven transitions: ToDestA (slow timer, declared FIRST) and ToDestB (fast timer, declared SECOND)."));
            Description.Add(FText::FromString("Guards FProcessor_SmState_Evaluate's first-Undetermined-Break behavior. With the bug, only the slow timer ever starts ticking; SM lands on DestA at the slower delay."));
            Description.Add(FText::FromString("PASS = SM lands on DestB (the second-declared, faster transition wins)."));
            Description.Add(FText::FromString("FAIL = SM lands on DestA (state evaluator Break'd on ToDestA's Undetermined and never inspected ToDestB)."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.StateMachine.EventDrivenMultiCondition");
            Station.Title = FText::FromString("EVENT-DRIVEN MULTI-CONDITION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Single transition Idle->Finish gated by TWO event-driven timer conditions: FastEvent (resolves at 0.1s) and SlowEvent (resolves at 0.4s)."));
            Description.Add(FText::FromString("Guards the framework contract that event-driven cond Pass results are preserved across transition Reset cycles. Between 0.1s and 0.4s the transition is in Fail (one Pass, one Fail) and state.Evaluate cycles through Reset many times; FastEvent's Pass MUST survive those cycles."));
            Description.Add(FText::FromString("PASS = Counter_Finish == 1 (transition fired after SlowEvent resolved). FAIL = Counter_Finish == 0 (FastEvent's Pass was lost across Reset)."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    // ========================================================================
    // STARTUP
    // ========================================================================

    void Request_StartGym() override
    {
        Request_StartAutoCycle();
        Request_StartPauseResume();
        Request_StartComplex();
        Request_StartHierarchical();
        Request_StartGraphWalkRegression();
        Request_StartDivergenceFirstBranch();
        Request_StartDivergenceTimed();
        Request_StartRacingEventDriven();
        Request_StartEventDrivenMultiCondition();
        ck::Trace("SM Gym - All stations started");
    }

    // ========================================================================
    // AUTO CYCLE STATION
    // ========================================================================

    void Request_StartAutoCycle()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.AutoCycle", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.CycleDuration = 2.0f;
        FinishSpawningActor(SpawnedActor);
    }

    // ========================================================================
    // PAUSE/RESUME STATION
    // ========================================================================

    void Request_StartPauseResume()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.PauseResume", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.CycleDuration = 1.5f;
        SpawnedActor.EnablePauseResume = true;
        SpawnedActor.PauseAfterTransitions = 6;
        SpawnedActor.PauseDuration = 3.0f;
        FinishSpawningActor(SpawnedActor);
    }

    // ========================================================================
    // COMPLEX GRAPH STATION
    // ========================================================================

    void Request_StartComplex()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.Complex", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.CycleDuration = 1.0f;
        SpawnedActor.InitialStateClass = UCk_SmTest_Complex_State_Idle;
        FinishSpawningActor(SpawnedActor);
    }

    // ========================================================================
    // HIERARCHICAL (SUB-SM) STATION
    // ========================================================================

    void Request_StartHierarchical()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.Hierarchical", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.InitialStateClass = UCk_SmTest_Hier_Parent_Spawn;
        FinishSpawningActor(SpawnedActor);
    }

    // ========================================================================
    // GRAPH-WALK REGRESSION STATION
    // ========================================================================

    void Request_StartGraphWalkRegression()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.GraphWalkRegression", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_GraphWalkRegression_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        // Pass the station handle so the actor can push PASS/FAIL straight
        // to the station's BP_DemoDisplay panel via dynamic fragment.
        SpawnedActor.StationHandle = Get_StationHandle("Gym.StateMachine.GraphWalkRegression");

        FinishSpawningActor(SpawnedActor);
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // A state machine that has already settled shows nothing, so every station has to be RE-RUN to be
    // watched - and re-running was console-only. The divergence and racing stations especially: their whole
    // point is the transition that happens once.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "STATE MACHINE";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("RE-RUN A STATION"));
        Rows.Add(CkGym_Control::Numbered(0, "Auto cycle", false));
        Rows.Add(CkGym_Control::Numbered(1, "Pause / resume", false));
        Rows.Add(CkGym_Control::Numbered(2, "Complex", false));
        Rows.Add(CkGym_Control::Numbered(3, "Hierarchical", false));
        Rows.Add(CkGym_Control::Numbered(4, "GraphWalk regression", false));
        Rows.Add(CkGym_Control::Numbered(5, "Divergence: first branch", false));
        Rows.Add(CkGym_Control::Numbered(6, "Divergence: timed", false));
        Rows.Add(CkGym_Control::Numbered(7, "Racing: event-driven", false));
        Rows.Add(CkGym_Control::Numbered(8, "Event-driven multi-cond", false));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Row 0 is the header, which holds no key and never arrives here.
        if (InRowIndex == 1) { Request_StartAutoCycle(); }
        else if (InRowIndex == 2) { Request_StartPauseResume(); }
        else if (InRowIndex == 3) { Request_StartComplex(); }
        else if (InRowIndex == 4) { Request_StartHierarchical(); }
        else if (InRowIndex == 5) { Request_StartGraphWalkRegression(); }
        else if (InRowIndex == 6) { Request_StartDivergenceFirstBranch(); }
        else if (InRowIndex == 7) { Request_StartDivergenceTimed(); }
        else if (InRowIndex == 8) { Request_StartRacingEventDriven(); }
        else if (InRowIndex == 9) { Request_StartEventDrivenMultiCondition(); }
    }

    // ========================================================================
    // DIVERGENCE FIRST-BRANCH STATION
    // ========================================================================

    void Request_StartDivergenceFirstBranch()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.DivergenceFirstBranch", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_DivergenceFirstBranch_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.StationHandle = Get_StationHandle("Gym.StateMachine.DivergenceFirstBranch");

        FinishSpawningActor(SpawnedActor);
    }

    // ========================================================================
    // DIVERGENCE FIRST-BRANCH (TIMED) STATION
    // ========================================================================

    void Request_StartDivergenceTimed()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.DivergenceTimed", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_DivergenceTimed_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.StationHandle = Get_StationHandle("Gym.StateMachine.DivergenceTimed");

        FinishSpawningActor(SpawnedActor);
    }

    // ========================================================================
    // RACING EVENT-DRIVEN STATION
    // ========================================================================

    void Request_StartRacingEventDriven()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.RacingEventDriven", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_RacingEventDriven_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        // Watchable timings for the visual gym (autotest uses defaults).
        SpawnedActor.SlowDelaySeconds = 2.0f;
        SpawnedActor.FastDelaySeconds = 0.5f;
        SpawnedActor.SettleSeconds    = 2.5f;

        SpawnedActor.StationHandle = Get_StationHandle("Gym.StateMachine.RacingEventDriven");

        FinishSpawningActor(SpawnedActor);
    }

    // ========================================================================
    // EVENT-DRIVEN MULTI-CONDITION STATION
    // ========================================================================

    void Request_StartEventDrivenMultiCondition()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.EventDrivenMultiCondition", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_EventDrivenMultiCondition_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        // Watchable timings for the visual gym (autotest uses defaults).
        SpawnedActor.FastDelaySeconds = 0.5f;
        SpawnedActor.SlowDelaySeconds = 2.0f;
        SpawnedActor.SettleSeconds    = 2.5f;

        SpawnedActor.StationHandle = Get_StationHandle("Gym.StateMachine.EventDrivenMultiCondition");

        FinishSpawningActor(SpawnedActor);
    }
};

// ============================================================================
