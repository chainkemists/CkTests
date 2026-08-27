// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: SEPARATION HEAD-ON PASS
//
// 2 agents 1500cm apart on a head-on course. Polls min-separation every 50ms.
// Asserts min-separation never drops below _Radius * 1.5 (= 63cm at default).
// Per Gate_03_Separation_Addendum.md Sec.8.
//
// REQUIREMENT: test map needs a NavMeshBoundsVolume covering at least
// (-1000, -1000, 0) to (1000, 1000, 0). AutoTests_CkTests_Level satisfies this.
//============================================================================

class UCk_AutoTest_Crowd_Separation_HeadOnPass : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle_CrowdAgent _AgentA;
    private FCk_Handle_CrowdAgent _AgentB;
    private float _MinSeparation = 999999.0;
    private float _ElapsedSec = 0.0;
    private int32 _SamplesWithMotion = 0;
    private const float TimeoutSec = 8.0;
    private const float SampleIntervalSec = 0.05;
    private const float MinSepRequirement = 63.0;  // _Radius(42) * 1.5
    private const int32 MinMotionSamples = 20;     // ~1s @ 50ms - must observe real motion

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the navmesh: AutoTests_CkTests_Level has the fixture but the bake is lazy.
        // Each spawned agent issues a MoveTo -> FindPath; the deferred-request queue holds
        // those until the rebuild completes (~10ms in practice).
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        const auto SpawnA = FVector(-750.0, 0.0, 100.0);
        const auto SpawnB = FVector( 750.0, 0.0, 100.0);
        _AgentA = SpawnAgent(LocalHandle, SpawnA, SpawnB);
        _AgentB = SpawnAgent(LocalHandle, SpawnB, SpawnA);

        // Recurring sample timer - fires every SampleIntervalSec until we hit timeout.
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
        if (ck::Is_NOT_Valid(_AgentA) || ck::Is_NOT_Valid(_AgentB)) { return; }

        _ElapsedSec += SampleIntervalSec;

        const auto LocA = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(_AgentA)));
        const auto LocB = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(_AgentB)));
        const auto Sep = float((LocA - LocB).Size());
        if (Sep < _MinSeparation) { _MinSeparation = Sep; }

        const auto VelA = utils_crowd_agent::Get_DesiredVelocity(_AgentA);
        if (VelA.IsNearlyZero() == false) { ++_SamplesWithMotion; }

        if (_ElapsedSec > TimeoutSec)
        {
            // Guard against the false-positive where pathing fails silently and agents never
            // move - _MinSeparation stays at its initial 999999 and the requirement check
            // would trivially "pass". Mirror the motion guard from Crowd_Separation_Vibration.
            Assert_True(_SamplesWithMotion >= MinMotionSamples,
                f"only {_SamplesWithMotion} samples saw non-zero velocity (need >= {MinMotionSamples}) - agents never moved, test would have falsely passed");
            Assert_True(_MinSeparation >= MinSepRequirement,
                f"min-separation {_MinSeparation} < required {MinSepRequirement}cm - agents clipped during head-on pass");
            FinishSuccess();
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

class ACk_AutoTest_Crowd_Separation_HeadOnPass_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Separation_HeadOnPass;
    default _TimeoutSeconds = 12.0f;
}
