// Language=angelscript
//============================================================================
// CK CROWD - REGRESSION AUTOTEST: SPATIAL ORBIT PREVENTION
//
// The production crowd pipeline must not produce a recorder-qualified spatial loop around Centre.
//============================================================================

class UCk_AutoTest_Crowd_Separation_SpatialOrbitSearch : UCk_AutoTest_Base
{
    // Evaluation is driven by GAME time (_ElapsedSec accrues one TickIntervalSec per timer
    // fire, reaching EvaluateAtSec=14.0s) while this budget is WALL-CLOCK, so the value has to
    // cover the real:game ratio the harness actually runs at - measured 19.1s for 14.0s of game
    // time here (1.36x). The former value assumed ~1.28x and had no headroom: a small per-frame
    // cost anywhere in the engine timed this out BEFORE it ever reached its assertions, which
    // surfaces as a bare TimeLimit with no message rather than as a crowd failure. Sized at ~2.5x.
    default _TimeoutSeconds = 35.0f;

    private TArray<FCk_Handle_CrowdAgent> _OriginalAgents;
    private TArray<FCk_Handle_CrowdAgent> _TrackedAgents;
    private float _ElapsedSec = 0.0;
    private bool _OverlapWaveSpawned = false;

    private const FVector Centre = FVector(0.0, 0.0, 100.0);
    private const float SpawnRadius = 600.0;
    private const int32 AgentCount = 5;
    private const float TickIntervalSec = 0.05;
    private const float OverlapWaveAtSec = 4.5;
    private const float EvaluateAtSec = 14.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        const auto AngleStep = (2.0 * Math::PI) / float(AgentCount);
        for (int32 i = 0; i < AgentCount; ++i)
        {
            const auto Angle = AngleStep * float(i);
            const auto Spawn = Centre + FVector(
                SpawnRadius * Math::Cos(Angle),
                SpawnRadius * Math::Sin(Angle),
                0.0);
            const auto Agent = SpawnTrackedAgent(LocalHandle, Spawn, FName(f"SpatialOrbit_W0_{i}"));
            _OriginalAgents.Add(Agent);
        }

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(TickIntervalSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnScheduleTick"));
    }

    UFUNCTION()
    private void OnScheduleTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedSec += TickIntervalSec;

        if (_OverlapWaveSpawned == false && _ElapsedSec >= OverlapWaveAtSec)
        {
            SpawnOverlapWave();
            _OverlapWaveSpawned = true;
        }

        if (_ElapsedSec >= EvaluateAtSec)
        {
            EvaluateSearch();
        }
    }

    private void SpawnOverlapWave()
    {
        for (int32 i = 0; i < _OriginalAgents.Num(); ++i)
        {
            const auto Original = _OriginalAgents[i];
            if (ck::Is_NOT_Valid(Original))
            {
                FinishFailure(f"original agent {i} became invalid before the overlap wave");
                return;
            }

            const auto CurrentLocation = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(Original)));
            auto Owner = DoGet_ScriptEntity();
            SpawnTrackedAgent(Owner, CurrentLocation, FName(f"SpatialOrbit_W1_{i}"));
        }
    }

    private void EvaluateSearch()
    {
        int32 QualifiedCount = 0;
        int32 BestIndex = -1;
        float BestDominantTurnDeg = 0.0;

        for (int32 i = 0; i < _TrackedAgents.Num(); ++i)
        {
            const auto Agent = _TrackedAgents[i];
            if (ck::Is_NOT_Valid(Agent))
            {
                FinishFailure(f"tracked agent {i} became invalid before the regression scenario completed");
                return;
            }

            utils_crowd_agent_diag::EmitDigest_ForAgent(Agent, 0, "SpatialOrbitSearch", i);
            const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(Agent);
            auto DominantTurnDeg = Recorder.Get_SpatialLoopWindowActive()
                ? Recorder.Get_DominantSpatialTurnDeg()
                : 0.0;
            if (Recorder.Get_HasBestCompletedSpatialWindow())
            {
                DominantTurnDeg = Math::Max(DominantTurnDeg, Recorder.Get_BestCompletedSpatialDominantTurnDeg());
            }
            if (Recorder.Get_SpatialLoopQualified())
            {
                DominantTurnDeg = Recorder.Get_QualifiedSpatialDominantTurnDeg();
            }
            if (DominantTurnDeg > BestDominantTurnDeg)
            {
                BestDominantTurnDeg = DominantTurnDeg;
                BestIndex = i;
            }
            if (Recorder.Get_SpatialLoopQualified())
            {
                ++QualifiedCount;
            }
        }

        Assert_True(QualifiedCount == 0,
            f"REGRESSION: {QualifiedCount} recorder-qualified >=360-degree spatial loop(s) around the fixed Centre occurred across {_TrackedAgents.Num()} production-composed agents. Best tracked agent={BestIndex}, dominant spatial turn={BestDominantTurnDeg} deg.");
        FinishSuccess();
    }

    private FCk_Handle_CrowdAgent SpawnTrackedAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        const auto Rotation = (Centre - InSpawn).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(Rotation, InSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        utils_crowd_agent_diag::Track(Agent, InSpawn, Centre);
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(Centre));
        _TrackedAgents.Add(Agent);
        return Agent;
    }
}
