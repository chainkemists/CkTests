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
            Station.Tags.Add(n"Gym.StateMachine.DivergencePolled");
            Station.Title = FText::FromString("DIVERGENCE FIRST-BRANCH (POLLED)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Polled mirror of DIVERGENCE FIRST-BRANCH (TIMED). Same topology, but every linear hop's gate is a polled time-elapsed condition (DoEvaluate returns true after 0.05s) instead of an event-driven timer."));
            Description.Add(FText::FromString("Diagnostic comparison: lets us observe whether the pump-budget cascade we see in the Timed variant also reproduces under polled-only conditions, or is specific to event-driven activation."));
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
        Request_StartDivergencePolled();
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

    // ========================================================================
    // CONSOLE COMMANDS
    // ========================================================================

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Auto Cycle")
    void Ck_GymSm_RestartAutoCycle()
    {
        Request_StartAutoCycle();
    }

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Pause/Resume")
    void Ck_GymSm_RestartPauseResume()
    {
        Request_StartPauseResume();
    }

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Complex")
    void Ck_GymSm_RestartComplex()
    {
        Request_StartComplex();
    }

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Hierarchical")
    void Ck_GymSm_RestartHierarchical()
    {
        Request_StartHierarchical();
    }

    UFUNCTION(Exec, DisplayName="SM Gym - Restart GraphWalk Regression")
    void Ck_GymSm_RestartGraphWalkRegression()
    {
        Request_StartGraphWalkRegression();
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

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Divergence FirstBranch")
    void Ck_GymSm_RestartDivergenceFirstBranch()
    {
        Request_StartDivergenceFirstBranch();
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

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Divergence Timed")
    void Ck_GymSm_RestartDivergenceTimed()
    {
        Request_StartDivergenceTimed();
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

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Racing Event-Driven")
    void Ck_GymSm_RestartRacingEventDriven()
    {
        Request_StartRacingEventDriven();
    }

    // ========================================================================
    // DIVERGENCE FIRST-BRANCH (POLLED) STATION
    // ========================================================================

    void Request_StartDivergencePolled()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.StateMachine.DivergencePolled", ECk_GymStation_Anchor::PanelCenter);

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_DivergencePolled_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.StationHandle = Get_StationHandle("Gym.StateMachine.DivergencePolled");

        FinishSpawningActor(SpawnedActor);
    }

    UFUNCTION(Exec, DisplayName="SM Gym - Restart Divergence Polled")
    void Ck_GymSm_RestartDivergencePolled()
    {
        Request_StartDivergencePolled();
    }
};

// ============================================================================
