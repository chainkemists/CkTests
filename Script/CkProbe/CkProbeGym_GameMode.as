//============================================================================
// PROBE GYM - GAME MODE & PLAYER CONTROLLER
//
// Generic CkFoundation Probe feature gym. Three stations:
//   1. Debug          - pure-ECS Request_BeginOverlap/EndOverlap cycle +
//                       manual force commands. Exercises signal dedup.
//   2. Physical       - multi-ball tween-driven overlap demo with
//                       AABB-vs-probe desync diagnostic (yellow = Jolt body
//                       stuck vs geometric ground truth).
//   3. NestedSceneNode- Kinematic Probe at the end of a Z45 -> X30 scene-node
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
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Tests raw Probe API: Request_Begin/EndOverlap + dedup."));
            Description.Add(FText::FromString("Panel: [J] enter, [K] exit, [R] reset."));
            Description.Add(FText::FromString("Auto steps: enter, dedup, exit, no-op."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Probe.Physical.Single");
            Station.Title = FText::FromString("PROBE PHYSICAL (SINGLE)");
            Station.AutoSize = true;
            auto SingleDescription = TArray<FText>();
            SingleDescription.Add(FText::FromString("Single ball tweens through the detector."));
            SingleDescription.Add(FText::FromString("Simplest case; yellow = Jolt body desync."));
            SingleDescription.Add(FText::FromString("Walk pawn through too."));
            Station.Description = SingleDescription;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Probe.Physical");
            Station.Title = FText::FromString("PROBE PHYSICAL (MULTI)");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Multi-ball tween demo. Yellow ball = Jolt body desync vs AABB."));
            Description.Add(FText::FromString("Walk the pawn through too."));
            Description.Add(FText::FromString("Panel [G]/[B] resume/pause the balls."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Probe.StationaryHierarchy");
            Station.Title = FText::FromString("PROBE STATIC HIERARCHY");
            Station.AutoSize = true;
            auto StaticDescription = TArray<FText>();
            StaticDescription.Add(FText::FromString("Same Z45->X30 chain but stationary."));
            StaticDescription.Add(FText::FromString("Detector at expected probe world pos."));
            StaticDescription.Add(FText::FromString("Fires at setup if composition works."));
            Station.Description = StaticDescription;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Probe.Trace");
            Station.Title = FText::FromString("PROBE TRACE WORLD HITS");
            Station.AutoSize = true;
            auto TraceDescription = TArray<FText>();
            TraceDescription.Add(FText::FromString("Shape trace across a baked cube and a target probe."));
            TraceDescription.Add(FText::FromString("Panel [T] cycles the world-hit policy."));
            TraceDescription.Add(FText::FromString("Ignore = wallhack, Blocking = cube truncates, Reported = both."));
            Station.Description = TraceDescription;
            Stations.Add(Station);
        }

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Probe.NestedSceneNode");
            Station.Title = FText::FromString("PROBE NESTED SCENE NODES");
            Station.AutoSize = true;
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Kinematic probe at end of Z45->X30 scene-node chain."));
            Description.Add(FText::FromString("Static detector fires when chained probe crosses it."));
            Description.Add(FText::FromString("Detector hits should match expected count."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        Request_StartDebugStation();
        Request_StartSinglePhysicalStation();
        Request_StartPhysicalStation();
        Request_StartStationaryHierarchyStation();
        Request_StartTraceStation();
        Request_StartNestedSceneNodeStation();
    }

    void Request_StartTraceStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Probe.Trace", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.Trace"),
            UCk_EntityScript_ProbeGym_TraceStation,
            FInstancedStruct::Make(SpawnParams));
    }

    void Request_StartStationaryHierarchyStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Probe.StationaryHierarchy", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.StationaryHierarchy"),
            UCk_EntityScript_ProbeGym_StationaryHierarchyStation,
            FInstancedStruct::Make(SpawnParams));
    }

    void Request_StartSinglePhysicalStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Probe.Physical.Single", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.Physical.Single"),
            UCk_EntityScript_ProbeGym_PhysicalStation_Single,
            FInstancedStruct::Make(SpawnParams));
    }

    void Request_StartDebugStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Probe.Debug", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.Debug"),
            UCk_EntityScript_ProbeGym_DebugStation,
            FInstancedStruct::Make(SpawnParams));
    }

    void Request_StartPhysicalStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Probe.Physical", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.Physical"),
            UCk_EntityScript_ProbeGym_PhysicalStation,
            FInstancedStruct::Make(SpawnParams));
    }

    void Request_StartNestedSceneNodeStation()
    {
        auto StationTransform = Get_StationAnchorTransform("Gym.Probe.NestedSceneNode", ECk_GymStation_Anchor::PanelCenter);
        auto SpawnParams = FCk_Gym_TransformSpawnParams(StationTransform);

        utils_entity_script::Request_SpawnEntity(
            Get_StationHandle("Gym.Probe.NestedSceneNode"),
            UCk_EntityScript_ProbeGym_NestedSceneNodeStation,
            FInstancedStruct::Make(SpawnParams));
    }

    //------------------------------------------------------------------------
    // Station drive - Debug + Nested manual steps
    //------------------------------------------------------------------------

    private void DoForceEnter()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGym_ForceEnter()); }
    }

    private void DoForceExit()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGym_ForceExit()); }
    }

    private void DoResetDebug()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_DebugStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGym_Reset()); }
    }

    private void DoResetNested()
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_NestedSceneNodeStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGym_NestedReset()); }
    }

    //------------------------------------------------------------------------
    // Trace station world-hit policy
    //------------------------------------------------------------------------

    // The policy lives on the trace station entity (its CurrentPolicy is private, with no readback),
    // so the panel mirrors it here. This controller's broadcast is the only writer.
    private ECk_ProbeTrace_WorldHitPolicy _TracePolicy = ECk_ProbeTrace_WorldHitPolicy::Ignore;

    private void DoCycleTraceWorldHitPolicy()
    {
        if (_TracePolicy == ECk_ProbeTrace_WorldHitPolicy::Ignore)
        { _TracePolicy = ECk_ProbeTrace_WorldHitPolicy::Blocking; }
        else if (_TracePolicy == ECk_ProbeTrace_WorldHitPolicy::Blocking)
        { _TracePolicy = ECk_ProbeTrace_WorldHitPolicy::Reported; }
        else
        { _TracePolicy = ECk_ProbeTrace_WorldHitPolicy::Ignore; }

        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), n"TAG_ProbeGym_TraceStation"))
        { utils_messaging::Broadcast(E, FCk_Message_ProbeGymTrace_SetWorldHitPolicy(_TracePolicy)); }
    }

    private FString Get_TracePolicyLabel()
    {
        if (_TracePolicy == ECk_ProbeTrace_WorldHitPolicy::Blocking) { return "Blocking"; }
        if (_TracePolicy == ECk_ProbeTrace_WorldHitPolicy::Reported) { return "Reported"; }
        return "Ignore";
    }

    //------------------------------------------------------------------------
    // Auto stepping
    //------------------------------------------------------------------------

    private void DoSetAutoAll(bool InEnabled)
    {
        DoSetAutoForTag(n"TAG_ProbeGym_DebugStation", InEnabled);
        DoSetAutoForTag(n"TAG_ProbeGym_PhysicalStation", InEnabled);
        DoSetAutoForTag(n"TAG_ProbeGym_NestedSceneNodeStation", InEnabled);
        DoSetAutoForTag(n"TAG_ProbeGym_TraceStation", InEnabled);
    }

    private void DoSetAutoForTag(FName InStationTag, bool InEnabled)
    {
        for (auto E : utils_entity_tag::ForEach_Entity(ck::ToEntity(this), InStationTag))
        { utils_messaging::Broadcast(E, FCk_Message_Gym_AutoSet(InEnabled)); }
    }

    //------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // Auto is two Actions rather than one Toggle on purpose: the debug station stops its OWN auto
    // whenever a manual step arrives (gym_auto::StopAuto), so a single mirrored flag here would
    // report a state no station is necessarily in.
    //------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "PROBE";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();

        Rows.Add(CkGym_Control::Header("DEBUG STATION"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Force enter"));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Force exit"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset the overlap state"));

        Rows.Add(CkGym_Control::Header("TRACE STATION"));
        Rows.Add(CkGym_Control::Cycle(EKeys::T, "T", "World-hit policy", Get_TracePolicyLabel()));

        Rows.Add(CkGym_Control::Header("NESTED SCENE NODES"));
        Rows.Add(CkGym_Control::Action(EKeys::N, "N", "Reset the chain"));

        Rows.Add(CkGym_Control::Header("AUTO STEPPING"));
        Rows.Add(CkGym_Control::Action(EKeys::G, "G", "All stations: auto on"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "All stations: auto off"));
        Rows.Add(CkGym_Control::Action(EKeys::U, "U", "Debug station only"));
        Rows.Add(CkGym_Control::Action(EKeys::I, "I", "Physical station only"));
        Rows.Add(CkGym_Control::Action(EKeys::O, "O", "Nested station only"));
        Rows.Add(CkGym_Control::Action(EKeys::P, "P", "Trace station only"));

        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        // Rows 0, 4, 6 and 8 are headers, which hold no key and never arrive here.
        if (InRowIndex == 1) { DoForceEnter(); }
        else if (InRowIndex == 2) { DoForceExit(); }
        else if (InRowIndex == 3) { DoResetDebug(); }
        else if (InRowIndex == 5) { DoCycleTraceWorldHitPolicy(); }
        else if (InRowIndex == 7) { DoResetNested(); }
        else if (InRowIndex == 9) { DoSetAutoAll(true); }
        else if (InRowIndex == 10) { DoSetAutoAll(false); }
        else if (InRowIndex == 11) { DoSetAutoForTag(n"TAG_ProbeGym_DebugStation", true); }
        else if (InRowIndex == 12) { DoSetAutoForTag(n"TAG_ProbeGym_PhysicalStation", true); }
        else if (InRowIndex == 13) { DoSetAutoForTag(n"TAG_ProbeGym_NestedSceneNodeStation", true); }
        else if (InRowIndex == 14) { DoSetAutoForTag(n"TAG_ProbeGym_TraceStation", true); }
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
