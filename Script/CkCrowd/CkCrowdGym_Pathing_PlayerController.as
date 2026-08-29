class ACk_CrowdGym_Pathing_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _OwnerHandle;
    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private TArray<AActor> _Obstacles;

    private TArray<FVector> _PendingSpawns;
    private TArray<FVector> _PendingGoals;
    private TArray<FLinearColor> _PendingColors;
    private TArray<FName> _PendingNames;

    // Re-target station: an agent is ping-ponged between two close points while still moving, so it
    // is perpetually re-targeted at speed (mirroring the live NPC's mid-walk MoveTo re-issue). This
    // is the most direct way to inject the high-speed lateral velocity the AccelClamp orbit needs.
    private bool _TickCreated = false;
    private FCk_Handle_CrowdAgent _RetargetAgent;
    private bool _RetargetValid = false;
    private FVector _RetargetT1 = FVector::ZeroVector;
    private FVector _RetargetT2 = FVector::ZeroVector;
    private bool _RetargetToB = false;
    private const float k_RetargetSwitchDist = 90.0;

    // A close, behind-and-lateral replacement goal applied while this agent is already moving.
    // K rebuilds the scenario with the generic Crowd close-goal strafe parameter toggled.
    private FCk_Handle_CrowdAgent _CloseGoalStrafeAgent;
    private bool _CloseGoalStrafeRetargetPending = false;
    private bool _CloseGoalStrafeEnabled = true;
    private FVector _CloseGoalStrafeGoal = FVector::ZeroVector;

    // Arrival ring (params default _ArrivalRadius) and the predicted single-point orbit radius
    // (MaxSpeed 240 / MaxTurnRate 4.0 = 60cm). An agent that settles on the red ring and never
    // enters the green ring is exhibiting the AccelClamp turn-radius orbit.
    private const float k_ArrivalRadius = 30.0;
    private const float k_OrbitRadius = 60.0;
    private const float k_AgentZ = 100.0;
    private const float k_BoxZ = 100.0;
    private const float k_DrawSeconds = 600.0;

    // Stations sit at X=k_StationX facing -X (open front toward -X). Scenarios are laid out in the
    // clear space IN FRONT of the stations (lower X) and agents move in the -X direction, away from
    // the station body. All positions are KNOWN - we never use the deferred station-tag lookup.
    // Lanes are within the Separation-gym-proven navmesh envelope (Y within +/-600).
    private const float k_StationX = 800.0;
    private const float k_SpawnX = 450.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        Add_Station(Stations, n"Gym.Crowd.Pathing.Retarget", -250.0, "RE-ISSUE CHURN",
            "MoveTo same point re-fired every frame. Should settle, not orbit.");
        Add_Station(Stations, n"Gym.Crowd.Pathing.Open", 250.0, "OPEN",
            "Straight goal. Stops in the green ring.");
        Add_Station(Stations, n"Gym.Crowd.Pathing.RoundEnd", -750.0, "ROUND END",
            "Round a wall end into a side goal.");
        Add_Station(Stations, n"Gym.Crowd.Pathing.Hairpin", 750.0, "HAIRPIN",
            "180 around a wall to a goal behind it.");
        Add_Station(Stations, n"Gym.Crowd.Pathing.Niche", -1250.0, "NICHE",
            "Stop deep inside a 3-sided pocket.");
        Add_Station(Stations, n"Gym.Crowd.Pathing.FlushBox", 1250.0, "FLUSH BOX",
            "Goal flush vs box. Orbit on red ring?");
        Add_Station(Stations, n"Gym.Crowd.Pathing.CloseGoalStrafe", -1750.0, "CLOSE-GOAL STRAFE",
            "K toggles the close-goal angular bypass, then retargets a moving agent to a nearby behind/lateral goal.");

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

        // Fixed, narrow dimensions so three panels fit at 450cm spacing without overlapping
        // (AutoSize would grow them ~600cm wide and they would collide).
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

        ck::crowd::Log("Pathing gym: StartGym ENTER");

        SpawnFloor();
        BuildAllScenarios();

        // Show the framework's own crowd debug draws: separation circle, the DASHED planned path
        // ("where it intends to go"), and the SOLID breadcrumb ("where it actually went"). The
        // gym no longer draws its own path lines - the framework's dashed-vs-solid distinction is
        // the single source of truth. (Toggles persist in the editor ini, so force them on entry.)
        System::ExecuteConsoleCommand("ck.Crowd.Debug 1");
        System::ExecuteConsoleCommand("ck.Crowd.DrawPlannedPaths 1");
        System::ExecuteConsoleCommand("ck.Crowd.DrawBreadcrumbs 1");
        ck::crowd::Log(f"Pathing gym: StartGym DONE - {_Agents.Num()} agents spawned");
    }

    private void SpawnFloor()
    {
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale = FVector(30.0, 30.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("Pathing gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);
        ck::crowd::Log("Pathing gym: floor spawned");
    }

    // ---- Scenario construction (positions are KNOWN; agents move -X, in front of the stations) -----

    private void BuildAllScenarios()
    {
        _OwnerHandle = ck::ToEntity(this);
        if (ck::Is_NOT_Valid(_OwnerHandle))
        {
            ck::crowd::Warning("Pathing gym: PC entity invalid; cannot build scenarios");
            return;
        }

        Build_Open(250.0);
        Build_RoundEnd(-750.0);
        Build_Hairpin(750.0);
        Build_Niche(-1250.0);
        Build_FlushBox(1250.0);

        RebuildNav();
        IssueAllMoves();

        // The re-target agent needs no obstacles; spawn it after the nav rebuild and start its
        // ping-pong. A single per-frame tick on the PC entity drives the re-targeting.
        SpawnRetargetAgent(-250.0);
        SpawnCloseGoalStrafeAgent(-1750.0);
        if (_TickCreated == false)
        {
            utils_timer::Create_Tick(_OwnerHandle, FCk_Delegate_Timer(this, n"OnGymTick"));
            _TickCreated = true;
        }
    }

    private void Build_Open(float InLaneY)
    {
        Queue_Agent(FVector(k_SpawnX, InLaneY, k_AgentZ), FVector(-50.0, InLaneY, k_AgentZ),
            FLinearColor(0.42, 0.85, 1.0, 1.0), n"PathingAgent_Open");
    }

    private void Build_FlushBox(float InLaneY)
    {
        // Small box (100x100x150) in front of the station; goal sits just past its far (-X) face so
        // the agent must round it and arrives laterally - the orbit seed.
        SpawnBox(FVector(180.0, InLaneY, k_BoxZ), FVector(1.0, 1.0, 1.5));
        Queue_Agent(FVector(k_SpawnX, InLaneY, k_AgentZ), FVector(100.0, InLaneY, k_AgentZ),
            FLinearColor(1.0, 0.42, 0.42, 1.0), n"PathingAgent_FlushBox");
    }

    private void Build_RoundEnd(float InLaneY)
    {
        // Wall blocks the lower part of the lane with a gap above. The agent must detour up, round
        // the wall's top end, then drop back DOWN to a goal on the far side - arriving with -Y
        // (lateral) velocity. Strong orbit candidate.
        SpawnBox(FVector(150.0, InLaneY - 60.0, k_BoxZ), FVector(0.5, 2.2, 1.5));
        Queue_Agent(FVector(k_SpawnX, InLaneY - 60.0, k_AgentZ), FVector(100.0, InLaneY - 40.0, k_AgentZ),
            FLinearColor(0.4, 1.0, 0.9, 1.0), n"PathingAgent_RoundEnd");
    }

    private void Build_Hairpin(float InLaneY)
    {
        // A long divider wall. The agent starts above it and the goal is below it, so it must run
        // out to the wall's open (-X) end, hairpin around, and come back to a goal just past the
        // turn - arriving mid-turn.
        SpawnBox(FVector(240.0, InLaneY, k_BoxZ), FVector(3.0, 0.4, 1.5));
        Queue_Agent(FVector(k_SpawnX, InLaneY + 70.0, k_AgentZ), FVector(130.0, InLaneY - 70.0, k_AgentZ),
            FLinearColor(1.0, 0.5, 0.9, 1.0), n"PathingAgent_Hairpin");
    }

    private void Build_Niche(float InLaneY)
    {
        // Three-sided pocket opening toward the agent. It enters at speed and must stop deep inside
        // a confined space - overshoot into the back wall is where it can orbit/jitter. The side
        // walls start at X=110 so they abut (not overlap) the X[70,110] back wall.
        SpawnBox(FVector(90.0, InLaneY, k_BoxZ), FVector(0.4, 1.6, 1.5));
        SpawnBox(FVector(205.0, InLaneY + 80.0, k_BoxZ), FVector(1.9, 0.4, 1.5));
        SpawnBox(FVector(205.0, InLaneY - 80.0, k_BoxZ), FVector(1.9, 0.4, 1.5));
        Queue_Agent(FVector(k_SpawnX, InLaneY, k_AgentZ), FVector(160.0, InLaneY, k_AgentZ),
            FLinearColor(0.7, 0.8, 1.0, 1.0), n"PathingAgent_Niche");
    }

    // ---- Queued-agent plumbing (boxes first, then one nav rebuild, then moves) --------------------

    private void Queue_Agent(FVector InSpawn, FVector InGoal, FLinearColor InColor, FName InDebugName)
    {
        _PendingSpawns.Add(InSpawn);
        _PendingGoals.Add(InGoal);
        _PendingColors.Add(InColor);
        _PendingNames.Add(InDebugName);
    }

    private void IssueAllMoves()
    {
        for (int32 i = 0; i < _PendingSpawns.Num(); ++i)
        {
            SpawnAgentAndMove(_PendingSpawns[i], _PendingGoals[i], _PendingColors[i], _PendingNames[i]);
        }
        _PendingSpawns.Empty();
        _PendingGoals.Empty();
        _PendingColors.Empty();
        _PendingNames.Empty();
    }

    private void RebuildNav()
    {
        if (ck::IsValid(_OwnerHandle))
        {
            utils_nav::Request_NavigationRebuild_ForTesting(_OwnerHandle);
        }
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // The run is over in seconds, so re-running it is the gym.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "CROWD: PATHING";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Restart every agent"));
        Rows.Add(CkGym_Control::Action(EKeys::Z, "Z", "Clear"));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K",
            _CloseGoalStrafeEnabled ? "Close-goal strafe: Enabled (60 uu)" : "Close-goal strafe: Disabled"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Request_RestartAllScenarios(); }
        else if (InRowIndex == 1) { Request_ClearScenarios(); }
        else if (InRowIndex == 2) { Request_ToggleCloseGoalStrafe(); }
    }

    private void Request_RestartAllScenarios()
    {
        if (HasAuthority() == false)
        { return; }

        ClearAll();
        BuildAllScenarios();
        ck::crowd::Log("Pathing gym: restarted all scenarios");
    }

    private void Request_ClearScenarios()
    {
        if (HasAuthority() == false)
        { return; }

        ClearAll();
        ck::crowd::Log("Pathing gym: cleared");
    }

    private void Request_ToggleCloseGoalStrafe()
    {
        if (HasAuthority() == false)
        { return; }

        _CloseGoalStrafeEnabled = !_CloseGoalStrafeEnabled;
        Request_RestartAllScenarios();
        ck::crowd::Log(f"Pathing gym: close-goal strafe {GetCloseGoalStrafeModeLabel()}; oracle is the close behind/lateral retarget lane");
    }

    private void ClearAll()
    {
        _RetargetValid = false;
        _CloseGoalStrafeRetargetPending = false;
        _CloseGoalStrafeAgent = FCk_Handle_CrowdAgent();

        for (auto Agent : _Agents)
        {
            if (ck::IsValid(Agent))
            {
                utils_entity_lifetime::Request_DestroyEntity(Agent);
            }
        }
        _Agents.Empty();

        for (auto Obstacle : _Obstacles)
        {
            if (Obstacle != nullptr)
            {
                Obstacle.DestroyActor();
            }
        }
        _Obstacles.Empty();

        RebuildNav();
    }

    // ---- Spawning helpers ------------------------------------------------------------------------

    private void SpawnBox(FVector InCenter, FVector InScale)
    {
        // Nav-only box: carves the navmesh (agent routes around it) but ignores the player Pawn.
        auto Box = SpawnActor(ACk_CrowdPathingGym_NavBox, InCenter, FRotator::ZeroRotator, NAME_None, true);
        if (Box == nullptr)
        {
            ck::crowd::Warning("Pathing gym: failed to spawn obstacle box");
            return;
        }
        Box.SetActorScale3D(InScale);
        FinishSpawningActor(Box);
        _Obstacles.Add(Box);
    }

    private FCk_Handle_CrowdAgent SpawnAgentAndMove(FVector InSpawn, FVector InGoal, FLinearColor InColor, FName InDebugName,
        bool InUseCloseGoalStrafe = false)
    {
        // Agents are standalone top-level entities (lifetime-owned by the registry transient),
        // NOT sub-entities of the PlayerController - they represent free-standing NPCs.
        // ClearAll destroys them explicitly, so no owner-cascade is needed.
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        if (InUseCloseGoalStrafe)
        {
            Params.Set_CloseGoalStrafe(_CloseGoalStrafeEnabled ? ECk_EnableDisable::Enable : ECk_EnableDisable::Disable);
            Params.Set_CloseGoalStrafeDistanceUu(60.0f);
        }

        // Lifetime-OWNED BY the transient, not composed ONTO it. utils_crowd_agent::Add composes
        // onto the handle it is given and permits one agent per entity, so passing the transient
        // directly put every agent on the same entity - the first won and the rest were no-ops.
        // It would also make ClearAll's destroy target the world transient.
        auto GenericAgent = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        GenericAgent.Set_DebugName(InDebugName);

        const auto SpawnXform = FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector);
        auto AgentTransform = utils_transform::Add(GenericAgent, SpawnXform, ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        _Agents.Add(Agent);

        auto VelocityParams = FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector);
        utils_velocity::Add(GenericAgent, VelocityParams, ECk_Replication::DoesNotReplicate);

        auto AccelParams = FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector);
        utils_acceleration::Add(GenericAgent, AccelParams, ECk_Replication::DoesNotReplicate);

        utils_euler_integrator::Request_Start(GenericAgent);
        utils_crowd_agent::Set_DebugColor(Agent, InColor);

        utils_crowd_agent::BindTo_OnGoalReached(Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnAgentGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        DrawRingsAt(InGoal);

        const auto Request = FCk_Request_CrowdAgent_MoveTo(InGoal);
        utils_crowd_agent::Request_MoveTo(Agent, Request);

        ck::crowd::Log(f"Pathing gym: agent added (valid={ck::IsValid(Agent)}) spawn={InSpawn} goal={InGoal}");
        return Agent;
    }

    private void SpawnRetargetAgent(float InLaneY)
    {
        // Single fixed goal; the per-frame tick re-issues MoveTo to it forever (the churn).
        _RetargetT1 = FVector(120.0, InLaneY, k_AgentZ);
        _RetargetT2 = _RetargetT1;
        _RetargetToB = false;

        DrawRingsAt(_RetargetT1);

        _RetargetAgent = SpawnAgentAndMove(FVector(k_SpawnX, InLaneY, k_AgentZ), _RetargetT1,
            FLinearColor(1.0, 0.25, 0.25, 1.0), n"PathingAgent_Retarget");
        _RetargetValid = true;
    }

    private void SpawnCloseGoalStrafeAgent(float InLaneY)
    {
        // Run rightward from the open lane, then replace the final goal at X~300 with a target
        // behind and laterally offset but still inside the 60uu strafe band. With strafe enabled it
        // may immediately redirect; disabled mode remains subject to the normal turn-rate cap.
        const auto InitialGoal = FVector(500.0, InLaneY, k_AgentZ);
        _CloseGoalStrafeGoal = FVector(265.0, InLaneY + 35.0, k_AgentZ);
        DrawRingsAt(_CloseGoalStrafeGoal);
        _CloseGoalStrafeAgent = SpawnAgentAndMove(FVector(-1200.0, InLaneY, k_AgentZ), InitialGoal,
            _CloseGoalStrafeEnabled ? FLinearColor(0.95, 0.7, 0.15, 1.0) : FLinearColor(0.55, 0.55, 0.55, 1.0),
            n"PathingAgent_CloseGoalStrafe", true);
        _CloseGoalStrafeRetargetPending = ck::IsValid(_CloseGoalStrafeAgent);
        ck::crowd::Log(f"Pathing gym: close-goal strafe oracle armed ({GetCloseGoalStrafeModeLabel()}, radius=60uu)");
    }

    UFUNCTION()
    void OnGymTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_RetargetValid && ck::IsValid(_RetargetAgent))
        {
            // Re-issue MoveTo to the SAME point every frame - reproduces the live NPC's re-issue churn
            // (a noisy state machine re-firing MoveTo many times a second). Without the fix this resets
            // the waypoint cursor every frame and the agent orbits the point; with the same-goal no-op
            // (B) + the turn-radius arrival cap (A) it should ignore the churn and settle cleanly.
            const auto Request = FCk_Request_CrowdAgent_MoveTo(_RetargetT1);
            utils_crowd_agent::Request_MoveTo(_RetargetAgent, Request);
        }

        if (_CloseGoalStrafeRetargetPending == false || ck::Is_NOT_Valid(_CloseGoalStrafeAgent))
        { return; }

        const auto Location = utils_transform::Get_EntityCurrentLocation(_CloseGoalStrafeAgent.As_Transform());
        if (Location.X < 300.0)
        { return; }

        auto Request = FCk_Request_CrowdAgent_MoveTo(_CloseGoalStrafeGoal);
        Request.Set_CorrelationId(73);
        Request.Set_ForceRepath(true);
        utils_crowd_agent::Request_MoveTo(_CloseGoalStrafeAgent, Request);
        _CloseGoalStrafeRetargetPending = false;
        ck::crowd::Log(f"Pathing gym: close-goal strafe oracle retargeted to {_CloseGoalStrafeGoal}; expected mode={GetCloseGoalStrafeOracleLabel()}");
    }

    private FString GetCloseGoalStrafeModeLabel() const
    {
        return _CloseGoalStrafeEnabled ? "ENABLED" : "DISABLED";
    }

    private FString GetCloseGoalStrafeOracleLabel() const
    {
        return _CloseGoalStrafeEnabled ? "immediate direction" : "turn limited";
    }

    private void DrawRingsAt(FVector InGoal)
    {
        const auto Green = FLinearColor(0.2, 1.0, 0.2, 1.0);
        const auto Red = FLinearColor(1.0, 0.2, 0.2, 1.0);
        const auto White = FLinearColor(1.0, 1.0, 1.0, 1.0);

        UCk_Utils_DebugDraw_UE::DrawDebugSphere(InGoal, k_ArrivalRadius, 24, Green, k_DrawSeconds, 2.0f);
        UCk_Utils_DebugDraw_UE::DrawDebugSphere(InGoal, k_OrbitRadius, 24, Red, k_DrawSeconds, 2.0f);
        UCk_Utils_DebugDraw_UE::DrawDebugSphere(InGoal, 8.0f, 12, White, k_DrawSeconds, 2.0f);
    }

    // ---- Signal handlers -------------------------------------------------------------------------

    UFUNCTION()
    void OnAgentGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        ck::crowd::Log("Pathing gym: an agent ARRIVED (clean stop)");
    }

    UFUNCTION()
    void OnAgentGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        ck::crowd::Warning("Pathing gym: an agent path FAILED (off-navmesh?)");
    }
}
