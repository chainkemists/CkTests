class ACk_PathNetworkGym_Following_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _OwnerHandle;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private FCk_Handle_PathNetwork _MainNetwork;
    private FCk_Handle_PathNetwork _RebuildNetwork;
    private bool _RebuildLaneIsDogLeg = false;

    // Stations sit at X=k_StationX facing -X; scenarios play out in front (lower X), one lane per
    // station. Agents generally move -X, away from the station body. Floor covers ±1500.
    private const float k_StationX = 800.0;
    private const float k_SpawnX = 500.0;
    private const float k_AgentZ = 0.0;
    private const float k_HalfWidth = 90.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Add_Station(Stations, n"Gym.PathNetwork.Run", 250.0, "SIDEWALK RUN",
            "One agent walks the sidewalk end to end. Note the right-of-center offset.");
        Add_Station(Stations, n"Gym.PathNetwork.Shortcut", -250.0, "SHORTCUT VS CLING",
            "Same start/goal. Multiplier 1.2 cuts the diagonal; 8 clings to the U detour.");
        Add_Station(Stations, n"Gym.PathNetwork.Streams", -750.0, "OPPOSING STREAMS",
            "Two agents, opposite directions, same sidewalk. They pass on opposite sides.");
        Add_Station(Stations, n"Gym.PathNetwork.Corner", 750.0, "L CORNER + GAP",
            "Sidewalk ends short of the goal. Agent rounds the L, then ramps off the end.");
        Add_Station(Stations, n"Gym.PathNetwork.Junction", 1250.0, "T JUNCTION",
            "Two agents share the stem, then split to opposite branch ends.");
        Add_Station(Stations, n"Gym.PathNetwork.Rebuild", -1250.0, "LIVE REBUILD",
            "Ck_GymPathNet_Rebuild swaps the ribbon mid-walk. The corridor replans.");

        return Stations;
    }

    private void Add_Station(TArray<FCkGym_Station_SpawnParams_Payload>& InOutStations,
        FName InTag, float InLaneY, FString InTitle, FString InDesc)
    {
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(InTag);
        Station.Title = FText::FromString(InTitle);
        auto Description = TArray<FText>();
        Description.Add(FText::FromString(InDesc));
        Station.Description = Description;

        Station.AutoSize = false;
        Station.Width = 4.0;
        Station.Depth = 2.0;
        Station.Height = 2.5;

        const auto Rot180 = FRotator(0.0, 180.0, 0.0);
        Station.Transform = FTransform(Rot180, FVector(k_StationX, InLaneY, 0.0), FVector::OneVector);

        InOutStations.Add(Station);
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        ck::pathnetwork::Log("PathNetwork gym: StartGym ENTER");

        SpawnFloor();
        BuildAllScenarios();

        System::ExecuteConsoleCommand("ck.PathNetwork.DebugDraw 1");
        System::ExecuteConsoleCommand("ck.Crowd.Debug 1");
        System::ExecuteConsoleCommand("ck.Crowd.DrawPlannedPaths 1");
        System::ExecuteConsoleCommand("ck.Crowd.DrawBreadcrumbs 1");

        ck::pathnetwork::Log(f"PathNetwork gym: StartGym DONE — {_Agents.Num()} agents spawned");
    }

    private void SpawnFloor()
    {
        auto Floor = SpawnActor(ACk_Gym_Floor, FVector::ZeroVector, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::pathnetwork::Warning("PathNetwork gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FVector(30.0, 30.0, 0.5));
        FinishSpawningActor(Floor);
    }

    // ---- Scenario construction ---------------------------------------------------------------------

    private void BuildAllScenarios()
    {
        _OwnerHandle = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_OwnerHandle))
        {
            ck::pathnetwork::Warning("PathNetwork gym: PC entity invalid; cannot build scenarios");
            return;
        }

        // One shared network for the static lanes; a separate one for the rebuild lane so
        // Ck_GymPathNet_Rebuild replans ONLY that lane's corridors.
        BuildMainNetwork();
        BuildRebuildNetwork(false);

        if (ck::IsValid(_OwnerHandle))
        { utils_nav::Request_NavigationRebuild_ForTesting(_OwnerHandle); }

        // SIDEWALK RUN (Y=250): straight lane, one walker.
        SpawnFollowerAndMove(FVector(k_SpawnX, 250.0, k_AgentZ), FVector(-1200.0, 250.0, k_AgentZ),
            _MainNetwork, 3.0, FLinearColor(0.42, 0.85, 1.0, 1.0), n"PathNetAgent_Run");

        // SHORTCUT VS CLING (Y=-250): same start/goal, opposite multipliers.
        SpawnFollowerAndMove(FVector(k_SpawnX, -250.0, k_AgentZ), FVector(-900.0, -250.0, k_AgentZ),
            _MainNetwork, 1.2, FLinearColor(1.0, 0.42, 0.42, 1.0), n"PathNetAgent_Shortcutter");
        SpawnFollowerAndMove(FVector(k_SpawnX, -250.0, k_AgentZ), FVector(-900.0, -250.0, k_AgentZ),
            _MainNetwork, 8.0, FLinearColor(0.42, 1.0, 0.42, 1.0), n"PathNetAgent_Clinger");

        // OPPOSING STREAMS (Y=-750): two walkers, opposite directions.
        SpawnFollowerAndMove(FVector(k_SpawnX, -750.0, k_AgentZ), FVector(-1200.0, -750.0, k_AgentZ),
            _MainNetwork, 3.0, FLinearColor(1.0, 0.8, 0.3, 1.0), n"PathNetAgent_StreamWest");
        SpawnFollowerAndMove(FVector(-1200.0, -750.0, k_AgentZ), FVector(k_SpawnX, -750.0, k_AgentZ),
            _MainNetwork, 3.0, FLinearColor(0.3, 0.8, 1.0, 1.0), n"PathNetAgent_StreamEast");

        // L CORNER + GAP (Y=750): sidewalk ends short of the goal.
        SpawnFollowerAndMove(FVector(k_SpawnX, 750.0, k_AgentZ), FVector(-600.0, 1300.0, k_AgentZ),
            _MainNetwork, 3.0, FLinearColor(1.0, 0.5, 0.9, 1.0), n"PathNetAgent_Corner");

        // T JUNCTION (Y=1250): two agents share the stem, split at the junction.
        SpawnFollowerAndMove(FVector(k_SpawnX, 1250.0, k_AgentZ), FVector(-250.0, 1000.0, k_AgentZ),
            _MainNetwork, 3.0, FLinearColor(0.7, 0.8, 1.0, 1.0), n"PathNetAgent_BranchSouth");
        SpawnFollowerAndMove(FVector(k_SpawnX, 1250.0, k_AgentZ), FVector(-250.0, 1500.0, k_AgentZ),
            _MainNetwork, 3.0, FLinearColor(0.4, 1.0, 0.9, 1.0), n"PathNetAgent_BranchNorth");

        // LIVE REBUILD (Y=-1250): one walker on its own network.
        SpawnFollowerAndMove(FVector(k_SpawnX, -1250.0, k_AgentZ), FVector(-1200.0, -1250.0, k_AgentZ),
            _RebuildNetwork, 3.0, FLinearColor(1.0, 1.0, 1.0, 1.0), n"PathNetAgent_Rebuild");
    }

    private void BuildMainNetwork()
    {
        TArray<FCk_PathNetwork_Ribbon> Ribbons;

        // SIDEWALK RUN lane.
        Ribbons.Add(MakeRibbon2(FVector(400.0, 250.0, 0.0), FVector(-1100.0, 250.0, 0.0)));

        // SHORTCUT VS CLING lane: a U detour dipping toward Y=-450.
        {
            TArray<FCk_PathNetwork_RibbonPoint> Points;
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, -250.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(350.0, -450.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-750.0, -450.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-800.0, -250.0, 0.0), k_HalfWidth));
            Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        }

        // OPPOSING STREAMS lane.
        Ribbons.Add(MakeRibbon2(FVector(400.0, -750.0, 0.0), FVector(-1100.0, -750.0, 0.0)));

        // L CORNER lane: runs -X then turns +Y; ends at (-400, 1100) — 300cm short of the goal.
        {
            TArray<FCk_PathNetwork_RibbonPoint> Points;
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 750.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-400.0, 750.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-400.0, 1100.0, 0.0), k_HalfWidth));
            Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        }

        // T JUNCTION lane: stem endpoint lands on the branch ribbon's interior → T-split.
        Ribbons.Add(MakeRibbon2(FVector(450.0, 1250.0, 0.0), FVector(-200.0, 1250.0, 0.0)));
        Ribbons.Add(MakeRibbon2(FVector(-200.0, 1050.0, 0.0), FVector(-200.0, 1450.0, 0.0)));

        FCk_Handle TransientOwner = ck::TransientEntity();
        _MainNetwork = utils_path_network::Add(TransientOwner, FCk_Fragment_PathNetwork_ParamsData(Ribbons));
    }

    private void BuildRebuildNetwork(bool InDogLeg)
    {
        TArray<FCk_PathNetwork_Ribbon> Ribbons;

        if (InDogLeg)
        {
            // The swapped shape: detour through Y=-1050 mid-lane.
            TArray<FCk_PathNetwork_RibbonPoint> Points;
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, -1250.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-300.0, -1250.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-300.0, -1050.0, 0.0), k_HalfWidth));
            Points.Add(FCk_PathNetwork_RibbonPoint(FVector(-1100.0, -1050.0, 0.0), k_HalfWidth));
            Ribbons.Add(FCk_PathNetwork_Ribbon(Points));
        }
        else
        {
            Ribbons.Add(MakeRibbon2(FVector(400.0, -1250.0, 0.0), FVector(-1100.0, -1250.0, 0.0)));
        }

        if (ck::Is_NOT_Valid(_RebuildNetwork))
        {
            FCk_Handle TransientOwner = ck::TransientEntity();
            _RebuildNetwork = utils_path_network::Add(TransientOwner, FCk_Fragment_PathNetwork_ParamsData(Ribbons));
        }
        else
        {
            utils_path_network::Request_Rebuild(_RebuildNetwork, FCk_Request_PathNetwork_Rebuild(Ribbons));
        }

        _RebuildLaneIsDogLeg = InDogLeg;
    }

    private FCk_PathNetwork_Ribbon MakeRibbon2(FVector InStart, FVector InEnd)
    {
        TArray<FCk_PathNetwork_RibbonPoint> Points;
        Points.Add(FCk_PathNetwork_RibbonPoint(InStart, k_HalfWidth));
        Points.Add(FCk_PathNetwork_RibbonPoint(InEnd, k_HalfWidth));
        return FCk_PathNetwork_Ribbon(Points);
    }

    // ---- Agent spawning ------------------------------------------------------------------------------

    private void SpawnFollowerAndMove(FVector InSpawn, FVector InGoal, FCk_Handle_PathNetwork InNetwork,
        float InOffPathMultiplier, FLinearColor InColor, FName InDebugName)
    {
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        // Lifetime-OWNED BY the transient, not composed ONTO it. utils_crowd_agent::Add composes
        // onto the handle it is given and permits one agent per entity, so passing the transient
        // directly put every follower on the same entity — the first won and the rest were no-ops,
        // leaving one follower no matter how many this spawns.
        auto GenericAgent = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        GenericAgent.Set_DebugName(InDebugName);

        auto AgentTransform = utils_transform::Add(GenericAgent,
            FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        _Agents.Add(Agent);
        utils_velocity::Add(GenericAgent,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(GenericAgent,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(GenericAgent);
        utils_crowd_agent::Set_DebugColor(Agent, InColor);

        // THE activation switch: with the follower feature present, the agent's MoveTo routes
        // through the path network instead of straight CkNavigation.
        auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
        FollowerParams.Set_Network(InNetwork);
        FollowerParams.Set_OffPathCostMultiplier(InOffPathMultiplier);
        utils_path_network_follower::Add(GenericAgent, FollowerParams);

        utils_crowd_agent::BindTo_OnGoalReached(Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnAgentGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(InGoal));

        ck::pathnetwork::Log(f"PathNetwork gym: follower agent spawned (mult={InOffPathMultiplier}) spawn={InSpawn} goal={InGoal}");
    }

    // ---- Console ---------------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Path Network - Restart All")
    void Ck_GymPathNet_RestartAll()
    {
        if (HasAuthority() == false)
        { return; }

        ClearAll();
        BuildAllScenarios();
        ck::pathnetwork::Log("PathNetwork gym: restarted all scenarios");
    }

    UFUNCTION(Exec, DisplayName="Path Network - Rebuild Lane Swap")
    void Ck_GymPathNet_Rebuild()
    {
        if (HasAuthority() == false)
        { return; }

        if (ck::Is_NOT_Valid(_RebuildNetwork))
        {
            ck::pathnetwork::Warning("PathNetwork gym: rebuild lane network not alive — restart the gym first");
            return;
        }

        // Swap straight <-> dog-leg. Walking corridors on this network invalidate (epoch bump)
        // and replan mid-walk — the visible proof of the rebuild pipeline.
        BuildRebuildNetwork(_RebuildLaneIsDogLeg == false);
        ck::pathnetwork::Log(f"PathNetwork gym: rebuild lane swapped (dog-leg={_RebuildLaneIsDogLeg})");
    }

    UFUNCTION(Exec, DisplayName="Path Network - Clear")
    void Ck_GymPathNet_Clear()
    {
        if (HasAuthority() == false)
        { return; }

        ClearAll();
        ck::pathnetwork::Log("PathNetwork gym: cleared");
    }

    private void ClearAll()
    {
        for (auto Agent : _Agents)
        {
            if (ck::IsValid(Agent))
            { utils_entity_lifetime::Request_DestroyEntity(Agent); }
        }
        _Agents.Empty();

        if (ck::IsValid(_MainNetwork))
        {
            FCk_Handle NetworkEntity = _MainNetwork;
            utils_entity_lifetime::Request_DestroyEntity(NetworkEntity);
            _MainNetwork = FCk_Handle_PathNetwork();
        }

        if (ck::IsValid(_RebuildNetwork))
        {
            FCk_Handle NetworkEntity = _RebuildNetwork;
            utils_entity_lifetime::Request_DestroyEntity(NetworkEntity);
            _RebuildNetwork = FCk_Handle_PathNetwork();
        }
    }

    // ---- Signal handlers -------------------------------------------------------------------------

    UFUNCTION()
    void OnAgentGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        ck::pathnetwork::Log("PathNetwork gym: an agent ARRIVED");
    }

    UFUNCTION()
    void OnAgentGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        ck::pathnetwork::Warning("PathNetwork gym: an agent's route FAILED");
    }
}
