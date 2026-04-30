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

        ck::Trace("Crowd Foundation Gym - Started. Use Ck_GymCrowd_Spawn from the console.");
    }

    UFUNCTION(Exec, DisplayName="Crowd Foundation - Spawn Agent")
    void Ck_GymCrowd_Spawn()
    {
        if (HasAuthority() == false)
        { return; }

        auto StationHandle = Get_StationHandle("Gym.Crowd.Foundation");
        if (ck::Is_NOT_Valid(StationHandle))
        {
            ck::Warning("CrowdGym: station handle invalid — has the gym finished spawning stations?");
            return;
        }

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto Agent = utils_crowd_agent::Add(StationHandle, Params);
        _Agents.Add(Agent);

        ck::Trace(f"CrowdGym: spawned agent — total now {_Agents.Num()}");
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
            ck::Warning("CrowdGym: no agents to remove");
            return;
        }

        const auto LastIdx = _Agents.Num() - 1;
        auto Last = _Agents[LastIdx];
        _Agents.RemoveAt(LastIdx);

        utils_entity_lifetime::Request_DestroyEntity(Last);

        ck::Trace(f"CrowdGym: removed last agent — {_Agents.Num()} remaining");
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

        ck::Trace(f"CrowdGym: cleared {Count} agents");
    }
}
