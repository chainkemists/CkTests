// Language=angelscript

class ACk_EqsGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Stations.Add(MakeStationPayload(n"Gym.Eqs.SimpleGrid", "SimpleGrid + Distance",
            "5x5 SimpleGrid (~25 candidates).\nDistance test scores closer-to-querier higher.\nSingleBest run mode."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.Donut", "Donut + Dot",
            "3 rings x 8 points = 24 candidates.\nDot test favours forward-facing candidates.\nSingleBest run mode."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.Cone", "Cone Generator",
            "Forward-cone candidate spread (no tests).\nAllMatchingSorted run mode.\nDemonstrates pure generator output."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.Immediate", "Immediate Sync",
            "Same SimpleGrid + Distance config\nbut via Request_RunQuery_Immediate.\nSync result, no broadcast."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.RandomBest", "RandomBest5Pct",
            "SimpleGrid + Distance test.\nRandomBest5Pct picks one of the\ntop 5% candidates each restart."));

        // v1.1 stations.
        Stations.Add(MakeStationPayload(n"Gym.Eqs.NavProjection", "NavProjection",
            "5x5 SimpleGrid with _ProjectOntoNav=true.\nCandidates snap to floor's navmesh\nvia UNavigationSystemV1::ProjectPointToNavigation."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.OnCircle", "OnCircle Generator",
            "8 evenly-spaced points on a 300uu ring.\nDistance test scores candidates.\nAllMatchingSorted run mode."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.VolumeCheck", "VolumeCheck Filter",
            "5x5 SimpleGrid filtered by an AABB at the\nstation origin (HalfExtent 150,150,50).\nInner 3x3 = 9 candidates survive."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.Random", "Random Tiebreaker",
            "Distance + Random tests on a SimpleGrid.\nRandom (Weight=0.1) tiebreaks equal-score\ncandidates each restart."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.Trace", "Trace (LOS)",
            "5x5 SimpleGrid + LineTrace LOS test.\nA wall blocks part of the grid; only\ncandidates with clear LOS survive."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.EntitiesWithTag", "EntitiesWithTag",
            "Generator returns 5 spawned target entities\non a 250uu ring (tagged Gym.Eqs.Target).\nDistance scoring picks the closest."));

        Stations.Add(MakeStationPayload(n"Gym.Eqs.Overlap", "Overlap Test",
            "5x5 SimpleGrid + Overlap test.\nThree probe markers near the grid score\ncandidates by neighbour count."));

        return Stations;
    }

    private FCkGym_Station_SpawnParams_Payload MakeStationPayload(FName InTag, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Desc = TArray<FText>();
        Desc.Add(FText::FromString(InDesc));
        Station.Description = Desc;
        return Station;
    }

    void Request_StartGym() override
    {
        SpawnFloor();

        SpawnStation("Gym.Eqs.SimpleGrid", "SIMPLEGRID + DISTANCE",
            "5x5 grid centered on station, 100uu spacing.\nDistance test (InverseLinear) scores nearest highest.\nSingleBest mode returns one candidate.",
            ECkEqsGym_Scenario::SimpleGrid_Distance);

        SpawnStation("Gym.Eqs.Donut", "DONUT + DOT",
            "3 rings (200-500uu) x 8 points = 24 candidates.\nDot test (NormalizedDot) favours forward-facing.\nWatch best-pick rotate as querier rotation changes.",
            ECkEqsGym_Scenario::Donut_Dot);

        SpawnStation("Gym.Eqs.Cone", "CONE GENERATOR",
            "Forward 90deg cone, 500uu range, 15deg/100uu step.\nNo tests - generator output only.\nAllMatchingSorted returns every candidate.",
            ECkEqsGym_Scenario::Cone_Generator);

        SpawnStation("Gym.Eqs.Immediate", "IMMEDIATE SYNC",
            "Same query as SimpleGrid + Distance,\nrouted through Request_RunQuery_Immediate.\nResults available before the call returns.\nNo OnComplete broadcast (P3-E5).",
            ECkEqsGym_Scenario::Immediate_Sync);

        SpawnStation("Gym.Eqs.RandomBest", "RANDOM BEST 5%",
            "SimpleGrid + Distance, RandomBest5Pct mode.\nFinal pick is sampled from the top 5%\nof scored candidates each run.",
            ECkEqsGym_Scenario::RandomBest5Pct);

        // v1.1 stations.
        SpawnStation("Gym.Eqs.NavProjection", "NAVPROJECTION",
            "SimpleGrid 5x5 + _ProjectOntoNav=true.\nCandidates snap to the floor's navmesh.\nThe floor must be navmesh-bakeable\n(scale Z >= 0.5).",
            ECkEqsGym_Scenario::NavProjection);

        SpawnStation("Gym.Eqs.OnCircle", "ONCIRCLE GENERATOR",
            "8 evenly-spaced points on a 300uu ring.\nDistance test for scoring; AllMatchingSorted\nreturns every candidate ranked.",
            ECkEqsGym_Scenario::OnCircle);

        SpawnStation("Gym.Eqs.VolumeCheck", "VOLUMECHECK FILTER",
            "SimpleGrid filtered by an AABB at the\nstation origin (HalfExtent 150,150,50).\nFilterMin=0.5 eliminates raw=0 candidates.\nResult: 3x3 = 9 of 25 candidates survive.",
            ECkEqsGym_Scenario::VolumeCheck);

        SpawnStation("Gym.Eqs.Random", "RANDOM TIEBREAKER",
            "SimpleGrid + Distance score + Random tiebreaker.\nRandom test (Weight=0.1) breaks deterministic\nordering on equal-distance candidates each run.",
            ECkEqsGym_Scenario::Random);

        SpawnStation("Gym.Eqs.Trace", "TRACE (LOS)",
            "SimpleGrid + LineTrace LOS test.\nThe wall spawned beside this station blocks\nLOS for some candidates; FilterMin=0.5\ndrops the blocked ones.",
            ECkEqsGym_Scenario::Trace);
        SpawnTraceWall();

        SpawnStation("Gym.Eqs.EntitiesWithTag", "ENTITIESWITHTAG",
            "Generator returns 5 child entities\nspawned by the station on a 250uu ring,\neach tagged Gym.Eqs.Target.\nDistance test picks the closest.",
            ECkEqsGym_Scenario::EntitiesWithTag);

        SpawnStation("Gym.Eqs.Overlap", "OVERLAP TEST",
            "SimpleGrid + Overlap test.\nThree probe markers (Gym.Eqs.OverlapMarker)\nspawned by the station near the grid;\ncandidates near a marker score higher.",
            ECkEqsGym_Scenario::Overlap);
    }

    // The Trace station needs a physical wall to block LOS. SpawnActor is only available on
    // the controller (not on entity scripts) so we spawn it here, oriented across the path
    // from the querier to the back row of the SimpleGrid.
    private void SpawnTraceWall()
    {
        const auto StationTransform = Get_StationAnchorTransform("Gym.Eqs.Trace", ECk_GymStation_Anchor::PanelCenter);
        const auto StationLocation = StationTransform.GetLocation();

        // The querier sits at the station origin and shoots LOS rays out to candidates on a
        // 5x5 grid (HalfSize=200, spacing=100). A 50uu-thick wall placed at the +X edge of the
        // grid (200uu away from the querier) blocks every candidate beyond it.
        const auto WallOffset = FVector(150.0f, 0.0f, 100.0f);
        const auto WallLocation = StationLocation + WallOffset;
        const auto WallScale = FVector(0.5, 5.0, 3.0);  // 50 x 500 x 300 cm

        auto Wall = SpawnActor(ACk_Gym_ObstacleWall, WallLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Wall == nullptr)
        {
            ck::Warning("EQS gym: failed to spawn trace wall");
            return;
        }
        Wall.SetActorScale3D(WallScale);
        FinishSpawningActor(Wall);
    }

    private void SpawnFloor()
    {
        // Reuses ACk_Gym_Floor (CkTests/Script/Common/CkGym_Floor.as) - generic floor
        // actor with collision + nav settings. The EQS NavProjection station needs the
        // baked navmesh that this floor produces; other stations just use it as a visible
        // reference surface. 4000cm x 4000cm covers the station-anchor footprint plus a
        // comfortable margin around each station's candidate spread.
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(40.0, 40.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::Warning("EQS gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
    }

    private void SpawnStation(
        FString InTag,
        FString InTitle,
        FString InDescription,
        ECkEqsGym_Scenario InScenario)
    {
        auto Params = FCkEqsGym_StationSpawnParams();
        Params.InitialTransform = Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter);
        Params.StationTitle = InTitle;
        Params.StationDescription = InDescription;
        Params.Scenario = InScenario;
        Params.RestartIntervalSeconds = 5.0f;

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle(InTag),
            UCk_EntityScript_EqsGym_Station,
            FInstancedStruct::Make(Params));
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // One row. Everything here plays once and is then over, so re-running it IS the gym - and the console
    // command's name was the only documentation that the control existed at all.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "ENTITY QUERY";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Re-run every query"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Ck_GymEqs_RestartAll(); }
    }

    UFUNCTION(Exec, DisplayName="Eqs Gym - Restart All")
    void Ck_GymEqs_RestartAll()
    {
        Request_StartGym();
    }
};
