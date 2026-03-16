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
        ck::Trace("SM Gym - All stations started");
    }

    // ========================================================================
    // AUTO CYCLE STATION
    // ========================================================================

    void Request_StartAutoCycle()
    {
        auto StationTransform = Get_StationTransform("Gym.StateMachine.AutoCycle");

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
        auto StationTransform = Get_StationTransform("Gym.StateMachine.PauseResume");

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
        auto StationTransform = Get_StationTransform("Gym.StateMachine.Complex");

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
        auto StationTransform = Get_StationTransform("Gym.StateMachine.Hierarchical");

        auto SpawnedActor = SpawnActor(
            ACk_SmTest_GymActor,
            StationTransform.GetLocation(),
            FRotator(0, 180, 0),
            NAME_None,
            true);

        SpawnedActor.InitialStateClass = UCk_SmTest_Hier_Parent_Approach;
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
};

// ============================================================================
