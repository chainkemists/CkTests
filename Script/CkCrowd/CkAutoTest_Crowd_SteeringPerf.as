// Language=angelscript

//============================================================================
// CK CROWD - PERF READOUT AUTOTEST (steering pipeline under convergence)
//============================================================================
//
// Measured (not estimated) frame-time readout for the per-frame steering
// loop: 240 agents in concentric rings, each targeting its ANTIPODE through
// the shared centre - every path crosses (0,0) so the sample window covers a
// sustained maximum-density crossing (probe overlap storm, NeighborSync
// mapping, separation, and - with the project defaults of threshold=1 /
// stride=1 - dtCrowd-style avoidance sampling on every neighbored agent
// every frame).
//
// Iskm-pattern harness: 3s warmup, 6s sampling, avg/max frame ms + FPS
// logged; no pass/fail timing threshold (machine-dependent) - compare logs
// from the same machine across implementation changes.
//============================================================================

class UCk_AutoTest_Crowd_SteeringPerf : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;

    private TArray<FCk_Handle_CrowdAgent> _Agents;

    private float _Elapsed = 0.0f;
    private float _SampleSum = 0.0f;
    private float _SampleMax = 0.0f;
    private int32 _SampleCount = 0;
    private FVector _ProbeStart = FVector::ZeroVector;
    private FVector _ProbeTarget = FVector::ZeroVector;
    private bool _NavProbeReady = false;
    private bool _MoveRequestsIssued = false;
    private bool _BenchmarkStarted = false;

    const int32 Rings = 6;
    const int32 AgentsPerRing = 40;
    const float InnerRadius = 350.0f;
    const float OuterRadius = 700.0f;
    const float WarmupSeconds = 3.0f;
    const float SampleSeconds = 6.0f;
    const FVector Centre = FVector(0.0, 0.0, 100.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        // Uncap so deltas measure work, not vsync.
        Set_CVarForTest(n"t.MaxFPS", "0");
        Set_CVarForTest(n"r.VSync", "0");

        _ProbeStart = Centre + FVector(InnerRadius, 0.0, 0.0);
        _ProbeTarget = FVector(-_ProbeStart.X, -_ProbeStart.Y, _ProbeStart.Z);
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, _ProbeStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the bake, then send one real path request through the same
        // explicit-default-nav-data path used by every benchmark agent. A
        // projection-only probe can select different nav data and false-positive.
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_MoveRequestsIssued == false)
        {
            if (_NavProbeReady == false)
            {
                DoTryNavProbe();
                return;
            }

            auto SelfHandle = DoGet_ScriptEntity();
            SpawnWorkload(SelfHandle);
            _MoveRequestsIssued = true;
            return;
        }

        if (_BenchmarkStarted == false)
        {
            if (TryStartBenchmark() == false)
            { return; }

            return;
        }

        const float Dt = float(InDeltaT.Get_Seconds());
        _Elapsed += Dt;

        if (_Elapsed <= WarmupSeconds)
        { return; }

        if (_Elapsed <= WarmupSeconds + SampleSeconds)
        {
            _SampleSum += Dt;
            if (Dt > _SampleMax) { _SampleMax = Dt; }
            ++_SampleCount;
            return;
        }

        if (_SampleCount == 0)
        {
            FinishFailure("no frames sampled");
            return;
        }

        const float AvgMs = (_SampleSum / float(_SampleCount)) * 1000.0f;
        const float MaxMs = _SampleMax * 1000.0f;
        const float Fps = float(_SampleCount) / _SampleSum;
        const int32 AgentCount = Rings * AgentsPerRing;
        if (ValidateAllAgentsOnNavmesh("after the benchmark") == false)
        {
            StopAllAgents();
            return;
        }
        Log(f"[CkCrowd PERF][Convergence agents={AgentCount}] frames={_SampleCount} avg={AvgMs} ms  max={MaxMs} ms  fps={Fps}");
        StopAllAgents();
        FinishSuccess();
    }

    // Retried each tick until the surface answers Success: the rebuild kicked in DoBeginPlay is
    // async, so the first few ticks can legitimately read Unbuilt while the bake finishes.
    private void DoTryNavProbe()
    {
        auto ProbeQuery = FCk_NavSurface_PathQuery(_ProbeStart, _ProbeTarget);
        const auto Result = utils_nav_surface::Try_FindPathSync(ProbeQuery);

        if (Result.Get_Status() == ECk_NavSurface_QueryStatus::Unbuilt) { return; }

        if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"navigation readiness probe returned status {Result.Get_Status()} instead of Success");
            return;
        }

        if (Result.Get_Waypoints().Num() < 1)
        {
            FinishFailure("navigation readiness probe returned no waypoints");
            return;
        }

        _NavProbeReady = true;
    }

    private void SpawnWorkload(FCk_Handle& InOwner)
    {
        const auto RingStep = (OuterRadius - InnerRadius) / float(Rings - 1);
        const auto AngleStep = (2.0 * Math::PI) / float(AgentsPerRing);

        for (int32 Ring = 0; Ring < Rings; ++Ring)
        {
            const auto Radius = InnerRadius + RingStep * float(Ring);
            // Stagger alternating rings by half a step so spokes don't line up.
            const auto AngleOffset = (Ring % 2 == 0) ? 0.0 : 0.5 * AngleStep;

            for (int32 i = 0; i < AgentsPerRing; ++i)
            {
                const auto Angle = AngleOffset + AngleStep * float(i);
                const auto Spawn = Centre + FVector(Radius * Math::Cos(Angle), Radius * Math::Sin(Angle), 0.0);
                // Antipode through the centre - every agent's path crosses (0,0).
                const auto Target = FVector(-Spawn.X, -Spawn.Y, Spawn.Z);
                _Agents.Add(SpawnAgent(InOwner, Spawn, Target));
            }
        }
    }

    // The nav slot is the wrong read here: under the crowd's two-phase GroundNav plan a strict
    // pass can answer Unreachable and get retried PERMISSIVELY one tick later
    // (FProcessor_CrowdAgent_OnGroundNavPathResolved runs RunAfter OnPathResolved), so
    // utils_nav::Get_PathStatus can read a transient Failed for one frame with no episode
    // actually failed. Read the crowd episode contract instead: abort only on the sticky
    // GoalFailedHold, and "ready" means the agent is Walking or has already reached its goal.
    private bool TryStartBenchmark()
    {
        for (auto Agent : _Agents)
        {
            if (utils_crowd_agent::Get_IsGoalFailedHold(Agent))
            {
                StopAllAgents();
                FinishFailure(f"benchmark agent path failed before steering started: goal-failed hold set");
                return false;
            }

            const bool IsWalking = utils_crowd_agent::Get_MovementState(Agent) == ECk_CrowdAgent_MovementState::Walking;
            if (IsWalking == false && utils_crowd_agent::Get_HasReachedActiveGoal(Agent) == false)
            { return false; }
        }

        // Begin the benchmark clock only after all 240 paths are ready. An agent that
        // already reached its goal counts as ready too - routes resolve over roughly a
        // second while antipode trips take roughly five, so early arrivals can go Idle
        // before the last agents start Walking, and the all-Walking condition alone
        // would never be met for a crowd that resolves in waves. The three-second
        // warmup still absorbs their one-frame resolution skew.
        _Elapsed = 0.0f;
        _SampleSum = 0.0f;
        _SampleMax = 0.0f;
        _SampleCount = 0;
        _BenchmarkStarted = true;
        return true;
    }

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    private bool ValidateAllAgentsOnNavmesh(FString InPhase)
    {
        for (int32 AgentIndex = 0; AgentIndex < _Agents.Num(); ++AgentIndex)
        {
            FCk_Handle AgentEntity = _Agents[AgentIndex];
            const auto AgentLoc = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(AgentEntity));

            const auto Projection = Do_ProjectOntoSurface(AgentLoc, FVector(42.0, 42.0, 192.0));
            if (Projection.Get_Status() != ECk_NavSurface_QueryStatus::Success)
            {
                FinishFailure(f"benchmark agent {AgentIndex} left the navmesh {InPhase}: location={AgentLoc}");
                return false;
            }

            const auto OnMesh = Projection.Get_Location();
            const auto VerticalDrift = Math::Abs(float(AgentLoc.Z - OnMesh.Z));
            if (VerticalDrift > 2.0f)
            {
                FinishFailure(f"benchmark agent {AgentIndex}'s feet drifted {VerticalDrift}uu from the navmesh surface {InPhase}: location={AgentLoc}, surface={OnMesh}");
                return false;
            }
        }

        return true;
    }

    private void StopAllAgents()
    {
        for (auto Agent : _Agents)
        {
            utils_crowd_agent::Request_Stop(Agent);
        }
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FVector InTarget)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        const auto Rot = (InTarget - InSpawn).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(InTarget));
        return Agent;
    }
}

class ACk_AutoTest_Crowd_SteeringPerf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_SteeringPerf;
    default _TimeoutSeconds = 45.0f;
}
