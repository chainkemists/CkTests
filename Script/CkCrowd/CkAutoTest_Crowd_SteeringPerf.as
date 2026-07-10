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
        System::ExecuteConsoleCommand("t.MaxFPS 0");
        System::ExecuteConsoleCommand("r.VSync 0");

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the navmesh bake; MoveTos queue until it completes (same as the convergence test).
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

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
                _Agents.Add(SpawnAgent(LocalHandle, Spawn, Target));
            }
        }

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

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
        Log(f"[CkCrowd PERF][Convergence agents={AgentCount}] frames={_SampleCount} avg={AvgMs} ms  max={MaxMs} ms  fps={Fps}");
        FinishSuccess();
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FVector InTarget)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto Agent = utils_crowd_agent::Add(InOwner, Params);
        FCk_Handle Generic = Agent;
        const auto Rot = (InTarget - InSpawn).Rotation();
        utils_transform::Add(Generic, FTransform(Rot, InSpawn, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        utils_velocity::Add(Generic, FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(Generic, FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector), ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(Generic);
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(InTarget));
        return Agent;
    }
}

class ACk_AutoTest_Crowd_SteeringPerf_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_SteeringPerf;
    default _TimeoutSeconds = 45.0f;
}
