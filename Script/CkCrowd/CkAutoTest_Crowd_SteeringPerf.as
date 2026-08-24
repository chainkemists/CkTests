// Language=angelscript

//============================================================================
// CK CROWD — PERF READOUT AUTOTEST (steering pipeline under convergence)
//============================================================================
//
// Measured (not estimated) frame-time readout for the per-frame steering
// loop: 240 agents in concentric rings, each targeting its ANTIPODE through
// the shared centre — every path crosses (0,0) so the sample window covers a
// sustained maximum-density crossing (probe overlap storm, NeighborSync
// mapping, separation, and — with the project defaults of threshold=1 /
// stride=1 — dtCrowd-style avoidance sampling on every neighbored agent
// every frame).
//
// Iskm-pattern harness: 3s warmup, 6s sampling, avg/max frame ms + FPS
// logged; no pass/fail timing threshold (machine-dependent) — compare logs
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

        const auto ProbeStart = Centre + FVector(InnerRadius, 0.0, 0.0);
        const auto ProbeTarget = FVector(-ProbeStart.X, -ProbeStart.Y, ProbeStart.Z);
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, ProbeStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathReady(LocalHandle,
            FCk_Delegate_Nav_OnPathReady(this, n"OnNavProbeReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_nav::BindTo_OnPathFailed(LocalHandle,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnNavProbeFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Kick the bake, then send one real path request through the same
        // explicit-default-nav-data path used by every benchmark agent. A
        // projection-only probe can select different nav data and false-positive.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);
        utils_nav::Request_FindPath(LocalHandle, FCk_Request_Nav_FindPath(ProbeTarget));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_MoveRequestsIssued == false)
        {
            if (_NavProbeReady == false)
            { return; }

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

    UFUNCTION()
    private void OnNavProbeReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        if (InResult.Get_Status() != ECk_Nav_PathStatus::Ready)
        {
            FinishFailure(f"navigation readiness probe returned status {InResult.Get_Status()} instead of Ready");
            return;
        }

        if (InResult.Get_Waypoints().Num() < 1)
        {
            FinishFailure("navigation readiness probe returned no waypoints");
            return;
        }

        _NavProbeReady = true;
    }

    UFUNCTION()
    private void OnNavProbeFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_nav::Get_PathResult(InHandle);
        FinishFailure(f"navigation readiness probe failed: reason={Result.Get_Diagnostics().Get_LastFailReason()}");
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
                // Antipode through the centre — every agent's path crosses (0,0).
                const auto Target = FVector(-Spawn.X, -Spawn.Y, Spawn.Z);
                _Agents.Add(SpawnAgent(InOwner, Spawn, Target));
            }
        }
    }

    private bool TryStartBenchmark()
    {
        for (auto Agent : _Agents)
        {
            FCk_Handle AgentEntity = Agent;
            const auto Status = utils_nav::Get_PathStatus(AgentEntity);
            if (Status == ECk_Nav_PathStatus::Failed || Status == ECk_Nav_PathStatus::Partial)
            {
                const auto Result = utils_nav::Get_PathResult(AgentEntity);
                StopAllAgents();
                FinishFailure(f"benchmark agent path failed before steering started: status={Status}, reason={Result.Get_Diagnostics().Get_LastFailReason()}");
                return false;
            }

            if (Status != ECk_Nav_PathStatus::Ready)
            { return false; }
        }

        // Begin the benchmark clock only after all 240 paths are ready. The
        // three-second warmup still absorbs their one-frame resolution skew.
        _Elapsed = 0.0f;
        _SampleSum = 0.0f;
        _SampleMax = 0.0f;
        _SampleCount = 0;
        _BenchmarkStarted = true;
        return true;
    }

    private bool ValidateAllAgentsOnNavmesh(FString InPhase)
    {
        auto SelfHandle = DoGet_ScriptEntity();
        for (int32 AgentIndex = 0; AgentIndex < _Agents.Num(); ++AgentIndex)
        {
            FCk_Handle AgentEntity = _Agents[AgentIndex];
            const auto AgentLoc = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(AgentEntity));

            FVector OnMesh;
            const auto Projects = utils_nav::Try_ProjectOntoNavmesh(
                SelfHandle, AgentLoc, 42.0f, OnMesh, 192.0f);
            if (Projects == false)
            {
                FinishFailure(f"benchmark agent {AgentIndex} left the navmesh {InPhase}: location={AgentLoc}");
                return false;
            }

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
