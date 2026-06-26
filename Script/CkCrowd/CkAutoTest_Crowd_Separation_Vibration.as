// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: SEPARATION VIBRATION
//
// 2 agents head-on. Samples agent A's _DesiredVelocity direction every 50ms
// for 3s. Asserts max angular delta between consecutive samples < 30°.
// Catches re-introduction of the Phase 1 vibration bug (force/path-follow
// fighting at full strength).
//============================================================================

class UCk_AutoTest_Crowd_Separation_Vibration : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_CrowdAgent _AgentA;
    private FCk_Handle_CrowdAgent _AgentB;
    private FVector _LastDir = FVector::ZeroVector;
    private float _MaxDeltaDeg = 0.0;
    private float _ElapsedSec = 0.0;
    private int32 _SamplesWithMotion = 0;
    private const float SampleIntervalSec = 0.05;
    private const float TestDurationSec = 3.0;
    private const float MaxAllowedDeltaDeg = 30.0;
    private const int32 MinMotionSamples = 20;  // ~1s @ 50ms — must observe real motion

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the navmesh: AutoTests_CkTests_Level has the fixture but the bake is lazy.
        // Each spawned agent issues a MoveTo → FindPath; the deferred-request queue holds
        // those until the rebuild completes (~10ms in practice).
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        const auto SpawnA = FVector(-750.0, 0.0, 100.0);
        const auto SpawnB = FVector( 750.0, 0.0, 100.0);
        _AgentA = SpawnAgent(LocalHandle, SpawnA, SpawnB);
        _AgentB = SpawnAgent(LocalHandle, SpawnB, SpawnA);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(SampleIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnSample"));
    }

    UFUNCTION()
    private void OnSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (ck::Is_NOT_Valid(_AgentA)) { return; }

        _ElapsedSec += SampleIntervalSec;

        const auto Vel = utils_crowd_agent::Get_DesiredVelocity(_AgentA);
        if (Vel.IsNearlyZero() == false)
        {
            ++_SamplesWithMotion;
            const auto Dir = Vel.GetSafeNormal();
            if (_LastDir.IsNearlyZero() == false)
            {
                const auto Dot = _LastDir.X * Dir.X + _LastDir.Y * Dir.Y + _LastDir.Z * Dir.Z;
                const auto AngleRad = Math::Acos(Math::Clamp(Dot, -1.0, 1.0));
                const auto AngleDeg = float(AngleRad * (180.0 / Math::PI));
                if (AngleDeg > _MaxDeltaDeg) { _MaxDeltaDeg = AngleDeg; }
            }
            _LastDir = Dir;
        }

        if (_ElapsedSec > TestDurationSec)
        {
            // Guard against the false-positive where pathing fails silently and no
            // velocity is ever sampled — _MaxDeltaDeg stays 0 and would "pass".
            Assert_True(_SamplesWithMotion >= MinMotionSamples,
                f"only {_SamplesWithMotion} samples saw non-zero velocity (need ≥ {MinMotionSamples}) — agents never moved, test would have falsely passed");
            Assert_True(_MaxDeltaDeg <= MaxAllowedDeltaDeg,
                f"max angular delta {_MaxDeltaDeg}° exceeds {MaxAllowedDeltaDeg}° — vibration regression");
            FinishSuccess();
        }
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

class ACk_AutoTest_Crowd_Separation_Vibration_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Separation_Vibration;
    default _TimeoutSeconds = 6.0f;
}
