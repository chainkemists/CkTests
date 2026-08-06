// Language=angelscript
//============================================================================
// CK CROWD — REGRESSION AUTOTEST: COINCIDENT-PAIR SPATIAL ORBIT PREVENTION
//
// This fixed equilateral geometry must not produce a recorder-qualified spatial loop around Centre.
//============================================================================

class UCk_AutoTest_Crowd_Separation_CoincidentPairOrbitSearch : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 28.0f;

    private TArray<FCk_Handle_CrowdAgent> _FirstWaveAgents;
    private TArray<FCk_Handle_CrowdAgent> _TrackedAgents;
    private float _ElapsedSec = 0.0;
    private bool _SecondWaveSpawned = false;

    private const FVector Centre = FVector(0.0, 0.0, 100.0);
    private const float SpawnRadius = 600.0;
    private const int32 FirstWaveCount = 3;
    private const float TickIntervalSec = 0.05;
    private const float SecondWaveAtSec = 4.5;
    private const float EvaluateAtSec = 22.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        const auto AngleStep = (2.0 * Math::PI) / float(FirstWaveCount);
        for (int32 i = 0; i < FirstWaveCount; ++i)
        {
            const auto Angle = AngleStep * float(i);
            const auto Spawn = Centre + FVector(
                SpawnRadius * Math::Cos(Angle),
                SpawnRadius * Math::Sin(Angle),
                0.0);
            const auto Agent = SpawnTrackedAgent(LocalHandle, Spawn, FName(f"CoincidentPair_W0_{i}"));
            _FirstWaveAgents.Add(Agent);
        }

        auto TimerParams = FCk_Timer_Spec(FCk_Time(TickIntervalSec));
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
        if (_SecondWaveSpawned == false && _ElapsedSec >= SecondWaveAtSec)
        {
            SpawnCoincidentSecondWave();
            _SecondWaveSpawned = true;
        }

        if (_ElapsedSec >= EvaluateAtSec)
        {
            EvaluateSearch();
        }
    }

    private void SpawnCoincidentSecondWave()
    {
        auto Owner = DoGet_ScriptEntity();
        TArray<FVector> ConflictLocations;
        for (int32 i = 0; i < _FirstWaveAgents.Num(); ++i)
        {
            const auto FirstWaveAgent = _FirstWaveAgents[i];
            if (ck::Is_NOT_Valid(FirstWaveAgent))
            {
                FinishFailure(f"first-wave agent {i} became invalid before its coincident pair spawned");
                return;
            }

            const auto CurrentLocation = utils_transform::Get_EntityCurrentLocation(
                utils_transform::DoCastChecked(FCk_Handle(FirstWaveAgent)));
            ConflictLocations.Add(CurrentLocation);
        }

        for (int32 i = 0; i < _FirstWaveAgents.Num(); ++i)
        {
            const auto FirstWaveAgent = _FirstWaveAgents[i];
            const auto CurrentLocation = ConflictLocations[i];
            // Re-anchor the original's diagnostic window at the deterministic conflict onset. This
            // does not alter its production motion; it keeps any later spatial-loop evidence from
            // being mixed with its unobstructed approach to Centre.
            utils_crowd_agent_diag::Track(FirstWaveAgent, CurrentLocation, Centre);
            SpawnTrackedAgent(Owner, CurrentLocation, FName(f"CoincidentPair_W1_{i}"));
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

            utils_crowd_agent_diag::EmitDigest_ForAgent(Agent, 0, "CoincidentPairOrbitSearch", i);
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
                ++QualifiedCount;
            }
            if (DominantTurnDeg > BestDominantTurnDeg)
            {
                BestDominantTurnDeg = DominantTurnDeg;
                BestIndex = i;
            }
        }

        Assert_True(QualifiedCount == 0,
            f"REGRESSION: {QualifiedCount} recorder-qualified >=360-degree spatial loop(s) around the fixed Centre occurred across {_TrackedAgents.Num()} production-composed agents after coincident pairs were introduced. Each original agent's qualified window begins at the deterministic conflict onset. Best tracked agent={BestIndex}, dominant spatial turn={BestDominantTurnDeg} deg.");
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
