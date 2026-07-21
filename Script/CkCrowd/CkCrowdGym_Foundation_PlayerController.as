// --------------------------------------------------------------------------------------------------------------------
// Crowd Foundation Gym — PlayerController
//
// Gate 0 commands (run from the console — Tab to open the gym menu HUD if it's not already up):
//   Ck_GymCrowd_Spawn         spawn one agent
//   Ck_GymCrowd_Spawn10       spawn 10 agents
//   Ck_GymCrowd_RemoveLast    remove the most recently spawned agent
//   Ck_GymCrowd_Clear         destroy all spawned agents
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
            Description.Add(FText::FromString("Console: Ck_GymCrowd_Spawn / Ck_GymCrowd_Spawn10 / Ck_GymCrowd_RemoveLast / Ck_GymCrowd_Clear"));
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

        ck::crowd::Log("Crowd Foundation Gym - Started. Use Ck_GymCrowd_Spawn from the console.");
    }

    UFUNCTION(Exec, DisplayName="Crowd Foundation - Spawn Agent")
    void Ck_GymCrowd_Spawn()
    {
        if (HasAuthority() == false)
        { return; }

        auto StationHandle = Get_StationHandle("Gym.Crowd.Foundation");
        if (ck::Is_NOT_Valid(StationHandle))
        {
            ck::crowd::Warning("CrowdGym: station handle invalid — has the gym finished spawning stations?");
            return;
        }

        // Agents are standalone top-level entities (lifetime-owned by the registry transient),
        // not sub-entities of the station — Clear/RemoveLast destroy them explicitly.
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        // Gate 3+: Setup processor requires FFragment_Transform to spawn the probe child entity.
        // Foundation gym doesn't pathfind or move, but a Transform at the station origin (jittered
        // so successive spawns don't pile on one point) lets the probe + neighbor cache exercise
        // without needing a navmesh.
        FCk_Handle GenericAgent = TransientOwner;
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

        ck::crowd::Log(f"CrowdGym: spawned agent at {SpawnXform.GetLocation()} — total now {_Agents.Num()}");
    }

    UFUNCTION(Exec, DisplayName="Crowd Foundation - Spawn 10 Agents")
    void Ck_GymCrowd_Spawn10()
    {
        for (int32 i = 0; i < 10; ++i)
        { Ck_GymCrowd_Spawn(); }
    }

    UFUNCTION(Exec, DisplayName="Crowd Foundation - Remove Last Agent")
    void Ck_GymCrowd_RemoveLast()
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

        ck::crowd::Log(f"CrowdGym: removed last agent — {_Agents.Num()} remaining");
    }

    UFUNCTION(Exec, DisplayName="Crowd Foundation - Clear All Agents")
    void Ck_GymCrowd_Clear()
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
