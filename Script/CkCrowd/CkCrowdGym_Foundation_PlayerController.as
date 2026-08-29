// --------------------------------------------------------------------------------------------------------------------
// Crowd Foundation Gym - PlayerController
//
// Gate 0 controls (the on-screen control panel; Tab opens the gym menu HUD):
//   G   spawn one agent
//   T   spawn 10 agents
//   X   remove the most recently spawned agent
//   Z   destroy all spawned agents
//
// Verify with the CkCrowdDebugger window:
//   ck.CrowdDebugger 1
//
// Each agent appears in the Agent List panel with an id like "#NNNNN  Crowd.Agent".
// Agent Detail (when one is clicked) shows handle / tags / radius / height.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Foundation_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FCk_Handle_CrowdAgent> _Agents;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.Foundation");
            Station.Title = FText::FromString("CROWD FOUNDATION");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Panel: G spawn one / T spawn ten / X remove last / Z clear"));
            Description.Add(FText::FromString("Open the debugger:  ck.CrowdDebugger 1"));
            Description.Add(FText::FromString("Spawned agents appear in the Agent List panel."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        ck::crowd::Log("Crowd Foundation Gym - Started. Press G on the control panel to spawn an agent.");
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // A crowd gym with no agents in it is an empty floor, and every way to put agents in it was
    // console-only.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "CROWD: FOUNDATION";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "Spawn one agent"));
        Rows.Add(CkGym_Control::Action(EKeys::T, "T", "Spawn ten agents"));
        Rows.Add(CkGym_Control::Action(EKeys::X, "X", "Remove the last agent"));
        Rows.Add(CkGym_Control::Action(EKeys::Z, "Z", "Clear every agent"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Request_SpawnAgent(); }
        else if (InRowIndex == 1) { Request_SpawnTenAgents(); }
        else if (InRowIndex == 2) { Request_RemoveLastAgent(); }
        else if (InRowIndex == 3) { Request_ClearAgents(); }
    }

    private void Request_SpawnAgent()
    {
        if (HasAuthority() == false)
        { return; }

        auto StationHandle = Get_StationHandle("Gym.Crowd.Foundation");
        if (ck::Is_NOT_Valid(StationHandle))
        {
            ck::crowd::Warning("CrowdGym: station handle invalid - has the gym finished spawning stations?");
            return;
        }

        // Agents are standalone top-level entities (lifetime-owned by the registry transient),
        // not sub-entities of the station - Clear/RemoveLast destroy them explicitly.
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        // Gate 3+: Setup processor requires FFragment_Transform to spawn the probe child entity.
        // Foundation gym doesn't pathfind or move, but a Transform at the station origin (jittered
        // so successive spawns don't pile on one point) lets the probe + neighbor cache exercise
        // without needing a navmesh.
        // Lifetime-OWNED BY the transient, not composed ONTO it. utils_crowd_agent::Add composes
        // onto the handle it is given and permits one agent per entity, so passing the transient
        // directly put every agent on the same entity - the jitter below could not separate them
        // because there was only ever one agent, and the probe/neighbor cache had nothing to see.
        auto GenericAgent = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        GenericAgent.Set_DebugName(FName(f"FoundationAgent_{_Agents.Num()}"));
        const auto StationXform = Get_StationAnchorTransform("Gym.Crowd.Foundation", ECk_GymStation_Anchor::FootprintCenter);
        const auto Jitter = FVector(
            Math::RandRange(-50.0, 50.0),
            Math::RandRange(-50.0, 50.0),
            100.0);
        const auto SpawnXform = FTransform(
            FRotator::ZeroRotator,
            StationXform.GetLocation() + Jitter,
            FVector::OneVector);
        auto AgentTransform = utils_transform::Add(GenericAgent, SpawnXform, ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);

        _Agents.Add(Agent);

        ck::crowd::Log(f"CrowdGym: spawned agent at {SpawnXform.GetLocation()} - total now {_Agents.Num()}");
    }

    private void Request_SpawnTenAgents()
    {
        for (int32 i = 0; i < 10; ++i)
        { Request_SpawnAgent(); }
    }

    private void Request_RemoveLastAgent()
    {
        if (HasAuthority() == false)
        { return; }

        if (_Agents.Num() == 0)
        {
            ck::crowd::Warning("CrowdGym: no agents to remove");
            return;
        }

        const auto LastIdx = _Agents.Num() - 1;
        auto Last = _Agents[LastIdx];
        _Agents.RemoveAt(LastIdx);

        utils_entity_lifetime::Request_DestroyEntity(Last);

        ck::crowd::Log(f"CrowdGym: removed last agent - {_Agents.Num()} remaining");
    }

    private void Request_ClearAgents()
    {
        if (HasAuthority() == false)
        { return; }

        const auto Count = _Agents.Num();
        for (auto Agent : _Agents)
        {
            utils_entity_lifetime::Request_DestroyEntity(Agent);
        }
        _Agents.Empty();

        ck::crowd::Log(f"CrowdGym: cleared {Count} agents");
    }
}
