//============================================================================
// PROBE GYM — GAME MODE & PLAYER CONTROLLER
//
// Generic CkFoundation Probe feature gym. Three stations:
//   1. Debug          — pure-ECS Request_BeginOverlap/EndOverlap cycle +
//                       manual force commands. Exercises signal dedup.
//   2. Physical       — multi-ball tween-driven overlap demo with
//                       AABB-vs-probe desync diagnostic (yellow = Jolt body
//                       stuck vs geometric ground truth).
//   3. NestedSceneNode— Kinematic Probe at the end of a Z45 → X30 scene-node
//                       chain; catches transform-composition bugs. Detector
//                       overlap firings are the ground truth.
//============================================================================

class ACk_ProbeGym_PlayerController : ACk_Gym_Base_PlayerController
{
    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Probe.Debug");
            Station.Title = FText::FromString("PROBE DEBUG");
            Station.Height = gym_auto::EstimateStationHeight(4, 3, 14);
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests raw Probe API: Request_Begin/EndOverlap + dedup."));
            Description.Add(FText::FromString("Console: ForceEnter / ForceExit / Reset / Auto"));
            Description.Add(FText::FromString("Auto steps: enter, dedup, exit, no-op."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Probe.Physical");
            Station.Title = FText::FromString("PROBE PHYSICAL");
            Station.Height = gym_auto::EstimateStationHeight(1, 1, 14);
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Multi-ball tween demo. Yellow ball = Jolt body desync vs AABB."));
            Description.Add(FText::FromString("Walk the pawn through too."));
            Description.Add(FText::FromString("Toggle Auto to pause/resume the balls."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        gym_auto::NormalizeStationHeights(Stations);
        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartDebugStation();
        Request_StartPhysicalStation();
    }

    void Request_StartDebugStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Probe.Debug");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.Debug"),
            UCk_EntityScript_ProbeGym_DebugStation,
            FInstancedStruct::Make(SpawnParams));
    }

    void Request_StartPhysicalStation()
    {
        auto StationTransform = Get_StationTransform("Gym.Probe.Physical");
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.Physical"),
            UCk_EntityScript_ProbeGym_PhysicalStation,
            FInstancedStruct::Make(SpawnParams));
    }

    //------------------------------------------------------------------------
    // Console Commands — Debug station manual drive
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Probe Gym - Force Enter")
    void Ck_GymProbe_ForceEnter()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGym_ForceEnter()); }
    }

    UFUNCTION(Exec, DisplayName="Probe Gym - Force Exit")
    void Ck_GymProbe_ForceExit()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGym_ForceExit()); }
    }

    UFUNCTION(Exec, DisplayName="Probe Gym - Reset")
    void Ck_GymProbe_Reset()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGym_Reset()); }
    }

    //------------------------------------------------------------------------
    // Console Commands — Auto
    //------------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Probe Gym - Auto")
    void Ck_GymProbe_Auto(int32 InEnabled = 1)
    {
        auto Enabled = InEnabled != 0;
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_Gym_AutoSet(Enabled)); }
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_PhysicalStation"))
        { utils_messaging::Broadcast(E, FCk_Message_Gym_AutoSet(Enabled)); }
    }

    UFUNCTION(Exec, DisplayName="Probe Gym - Auto Debug")
    void Ck_GymProbe_AutoDebug()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_Gym_AutoSet(true)); }
    }

    UFUNCTION(Exec, DisplayName="Probe Gym - Auto Physical")
    void Ck_GymProbe_AutoPhysical()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_PhysicalStation"))
        { utils_messaging::Broadcast(E, FCk_Message_Gym_AutoSet(true)); }
    }

}

//============================================================================
// GAME MODE
//============================================================================

class ACk_ProbeGym_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_ProbeGym_PlayerController;
    // Probe gym needs a pawn with a marker probe so walk-through physical
    // overlap fires detector signals. Default pawn has no probe.
    default DefaultPawnClass = ACk_ProbeGym_Pawn;
}
