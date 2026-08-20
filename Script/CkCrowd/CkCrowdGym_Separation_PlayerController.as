// --------------------------------------------------------------------------------------------------------------------
// Crowd Separation Gym — PlayerController (Gate 3)
//
// Spawns CrowdAgents at four cardinal offsets from the station origin and sends each toward a
// target. The full Gate 3 stack drives them: probe → neighbor cache → separation force →
// steering combination → motion. Visuals come up with `ck.Crowd.Debug 1`.
// --------------------------------------------------------------------------------------------------------------------

class ACk_CrowdGym_Separation_PlayerController : ACk_Gym_Base_PlayerController
{
    private FCk_Handle _StationHandle;
    private TArray<FCk_Handle_CrowdAgent> _Agents;

    // Cardinal spawn offsets relative to the station origin. 600cm puts agents well outside each
    // others' 100cm separation radius at spawn time; the head-on collision happens near centre
    // (Y=0 for N↔S, X=0 for E↔W) where separation should kick in.
    private const float SpawnDistance = 600.0;
    private const float SpawnZ = 100.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        if (HasAuthority() == false)
        { return TArray<FCkGym_Station_SpawnParams_Payload>(); }

        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        {
            auto Station = FCkGym_Station_SpawnParams_Payload();
            Station.Tags.Add(n"Gym.Crowd.Separation");
            Station.Title = FText::FromString("CROWD SEPARATION (Gate 3)");
            auto Description = TArray<FText>();
            Description.Add(FText::FromString("Console: Ck_GymCrowd_Sep_HeadOnNS / HeadOnEW / All4 / Cluster5 / Clear"));
            Description.Add(FText::FromString("In-world visuals:  ck.Crowd.Debug 1"));
            Description.Add(FText::FromString("Data panel:        ck.CrowdDebugger 1"));
            Description.Add(FText::FromString("Head-on pairs should pass without clipping; converging cluster should not pile."));
            Station.Description = Description;
            Stations.Add(Station);
        }

        return Stations;
    }

    void Request_StartGym() override
    {
        if (HasAuthority() == false)
        { return; }

        SpawnFloor();

        _StationHandle = Get_StationHandle("Gym.Crowd.Separation");
        if (ck::Is_NOT_Valid(_StationHandle))
        {
            ck::crowd::Warning("Separation gym: station handle invalid at StartGym");
            return;
        }

        ck::crowd::Log("Separation gym started. Try Ck_GymCrowd_Sep_HeadOnNS or Ck_GymCrowd_Sep_Cluster5.");
    }

    private void SpawnFloor()
    {
        // 2000cm × 2000cm flat cube — same shape used by Locomotion / Pathfinding gyms. Top at
        // Z=+25 with 0.5 height scale; spawn points sit at Z=100 (75cm above the floor) so the
        // navmesh's 500cm projection comfortably finds the floor below.
        const auto FloorLocation = FVector::ZeroVector;
        const auto FloorScale    = FVector(20.0, 20.0, 0.5);

        auto Floor = SpawnActor(ACk_Gym_Floor, FloorLocation, FRotator::ZeroRotator, NAME_None, true);
        if (Floor == nullptr)
        {
            ck::crowd::Warning("Separation gym: failed to spawn floor actor");
            return;
        }
        Floor.SetActorScale3D(FloorScale);
        FinishSpawningActor(Floor);

        ck::crowd::Log(f"Separation gym: floor spawned at {FloorLocation} scale={FloorScale}");
    }

    // ---- Cardinal helper -----------------------------------------------------------------------

    private FVector Get_StationOrigin()
    {
        const auto StationXform = Get_StationAnchorTransform("Gym.Crowd.Separation", ECk_GymStation_Anchor::FootprintCenter);
        return StationXform.GetLocation() + FVector(0.0, 0.0, SpawnZ);
    }

    private FVector Get_North() { return Get_StationOrigin() + FVector(0.0,  SpawnDistance, 0.0); }
    private FVector Get_South() { return Get_StationOrigin() + FVector(0.0, -SpawnDistance, 0.0); }
    private FVector Get_East()  { return Get_StationOrigin() + FVector( SpawnDistance, 0.0, 0.0); }
    private FVector Get_West()  { return Get_StationOrigin() + FVector(-SpawnDistance, 0.0, 0.0); }

    // ---- Console commands ----------------------------------------------------------------------

    UFUNCTION(Exec, DisplayName="Crowd Separation - Head-On N↔S")
    void Ck_GymCrowd_Sep_HeadOnNS()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        SpawnAgentAt(Get_North(), Get_South(), FLinearColor(0.42, 0.85, 1.0, 0.6));
        SpawnAgentAt(Get_South(), Get_North(), FLinearColor(1.0, 0.42, 0.85, 0.6));
        ck::crowd::Log("Separation gym: dispatched 2 agents on head-on N↔S course");
    }

    UFUNCTION(Exec, DisplayName="Crowd Separation - Head-On E↔W")
    void Ck_GymCrowd_Sep_HeadOnEW()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        SpawnAgentAt(Get_East(), Get_West(), FLinearColor(0.85, 1.0, 0.42, 0.6));
        SpawnAgentAt(Get_West(), Get_East(), FLinearColor(1.0, 0.85, 0.42, 0.6));
        ck::crowd::Log("Separation gym: dispatched 2 agents on head-on E↔W course");
    }

    UFUNCTION(Exec, DisplayName="Crowd Separation - All 4 Cardinals")
    void Ck_GymCrowd_Sep_All4()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        SpawnAgentAt(Get_North(), Get_South(), FLinearColor(0.42, 0.85, 1.0, 0.6));
        SpawnAgentAt(Get_South(), Get_North(), FLinearColor(1.0, 0.42, 0.85, 0.6));
        SpawnAgentAt(Get_East(),  Get_West(),  FLinearColor(0.85, 1.0, 0.42, 0.6));
        SpawnAgentAt(Get_West(),  Get_East(),  FLinearColor(1.0, 0.85, 0.42, 0.6));
        ck::crowd::Log("Separation gym: dispatched 4 agents (all four cardinals heading to opposite)");
    }

    UFUNCTION(Exec, DisplayName="Crowd Separation - Cluster of 5 to Centre")
    void Ck_GymCrowd_Sep_Cluster5()
    {
        if (HasAuthority() == false || ck::Is_NOT_Valid(_StationHandle))
        { return; }

        // 5 agents evenly spaced on a circle, all targeting the centre. Cluster radius is the same
        // as the spawn distance for the cardinal commands so behaviour is comparable.
        const auto Centre = Get_StationOrigin();
        const auto Count = 5;
        const auto AngleStep = (2.0 * Math::PI) / float(Count);
        for (int32 i = 0; i < Count; ++i)
        {
            const auto Angle = AngleStep * float(i);
            const auto Offset = FVector(SpawnDistance * Math::Cos(Angle), SpawnDistance * Math::Sin(Angle), 0.0);
            const auto SpawnLoc = Centre + Offset;
            // Hue varies around the wheel to make individuals legible in the cluster.
            const auto Hue = (360.0 / float(Count)) * float(i);
            const auto Color = FLinearColor::MakeFromHSV8(uint8(Hue * 255.0 / 360.0), 200, 220);
            SpawnAgentAt(SpawnLoc, Centre, Color);
        }
        ck::crowd::Log("Separation gym: dispatched 5 agents converging on the centre point");
    }

    UFUNCTION(Exec, DisplayName="Crowd Separation - Clear All Agents")
    void Ck_GymCrowd_Sep_Clear()
    {
        if (HasAuthority() == false)
        { return; }

        const auto Count = _Agents.Num();
        for (auto Agent : _Agents)
        {
            if (ck::IsValid(Agent))
            {
                utils_entity_lifetime::Request_DestroyEntity(Agent);
            }
        }
        _Agents.Empty();
        ck::crowd::Log(f"Separation gym: cleared {Count} agents");
    }

    // ---- Agent factory -------------------------------------------------------------------------

    private void SpawnAgentAt(FVector SpawnLoc, FVector TargetLoc, FLinearColor InColor)
    {
        // Mirror the Locomotion gym's spawn flow: agent + Transform + Velocity + Acceleration +
        // EulerIntegrator started, plus a cyan capsule + orange forward cone for visuals.
        // Agents are standalone top-level entities (lifetime-owned by the registry transient),
        // not sub-entities of the station — Clear destroys each agent explicitly.
        FCk_Handle TransientOwner = ck::TransientEntity();
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        // Lifetime-OWNED BY the transient, not composed ONTO it. utils_crowd_agent::Add composes
        // onto the handle it is given and permits one agent per entity, so passing the transient
        // directly put every agent on the same entity — the first won and the rest were no-ops,
        // leaving a "crowd" of exactly one. It would also make ClearAll's destroy target the
        // world transient.
        auto GenericAgent = utils_entity_lifetime::Request_CreateEntity(TransientOwner);
        GenericAgent.Set_DebugName(FName(f"SeparationAgent_{_Agents.Num()}"));

        // Yaw the spawn rotation toward the target so the forward cone starts already pointing
        // the right way (vs the default zero rotator which has the cone facing world +X).
        const auto ToTarget = (TargetLoc - SpawnLoc).GetSafeNormal();
        const auto SpawnRot = ToTarget.Rotation();
        const auto SpawnXform = FTransform(SpawnRot, SpawnLoc, FVector::OneVector);
        auto AgentTransform = utils_transform::Add(GenericAgent, SpawnXform, ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        _Agents.Add(Agent);

        auto VelocityParams = FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector);
        utils_velocity::Add(GenericAgent, VelocityParams, ECk_Replication::DoesNotReplicate);

        auto AccelParams = FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector);
        utils_acceleration::Add(GenericAgent, AccelParams, ECk_Replication::DoesNotReplicate);

        utils_euler_integrator::Request_Start(GenericAgent);

        // Body capsule + forward cone come from FProcessor_CrowdAgent_DrawBody (CkCrowd
        // framework). Pin the per-agent override color so the multi-agent test's "blue vs pink
        // vs green vs orange" identity is preserved — without this, Get_DebugColor falls back
        // to a hash-derived color and the directions become indistinguishable.
        utils_crowd_agent::Set_DebugColor(Agent, InColor);

        // Bind goal signals so we can log arrivals — useful when the cluster test is busy and we
        // need to see "agent X reached goal" without staring at the viewport.
        utils_crowd_agent::BindTo_OnGoalReached(Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentGoalReached"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
        utils_crowd_agent::BindTo_OnGoalFailed(Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnAgentGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Issue the move request immediately. The full Gate 3 stack handles the rest: pathing
        // resolves, NeighborSync populates the cache, Separation computes the force, Steering
        // combines and writes desired velocity.
        const auto MoveRequest = FCk_Request_CrowdAgent_MoveTo(TargetLoc);
        utils_crowd_agent::Request_MoveTo(Agent, MoveRequest);

        ck::crowd::Log(f"Separation gym: spawned agent at {SpawnLoc} → target {TargetLoc}");
    }

    UFUNCTION()
    void OnAgentGoalReached(FCk_Handle_CrowdAgent InAgent)
    {
        // Format via the generic FCk_Handle — typesafe handles aren't directly stringifiable in AS.
        FCk_Handle Generic = InAgent;
        ck::crowd::Log(f"Separation gym: agent {Generic} reached goal");
    }

    UFUNCTION()
    void OnAgentGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        FCk_Handle Generic = InAgent;
        ck::crowd::Warning(f"Separation gym: agent {Generic} failed to reach goal");
    }
}
