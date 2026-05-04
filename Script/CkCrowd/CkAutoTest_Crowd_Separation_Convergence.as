// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: SEPARATION CONVERGENCE
//
// 5 agents around a 600cm circle, all targeting the centre. After 6s asserts
// all 5 are within 200cm of target and no pair of final positions is within
// _Radius * 2 (= 84cm). Per Gate_03_Separation_Addendum.md §8.
//============================================================================

class UCk_AutoTest_Crowd_Separation_Convergence : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private TArray<FCk_Handle_CrowdAgent> _Agents;
    private const float TimeoutSec = 6.0;
    private const float ArrivalWindow = 200.0;
    private const float MinPairwiseSep = 84.0;
    private const FVector Centre = FVector(0.0, 0.0, 100.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        const auto Radius = 600.0;
        const auto Count = 5;
        const auto Step = (2.0 * Math::PI) / float(Count);
        for (int32 i = 0; i < Count; ++i)
        {
            const auto Angle = Step * float(i);
            const auto Spawn = Centre + FVector(Radius * Math::Cos(Angle), Radius * Math::Sin(Angle), 0.0);
            _Agents.Add(SpawnAgent(LocalHandle, Spawn, Centre));
        }

        // One-shot timer fires after TimeoutSec — then we evaluate.
        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(TimeoutSec));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTimeout"));
    }

    UFUNCTION()
    private void OnTimeout(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        TArray<FVector> Finals;
        for (auto Agent : _Agents)
        {
            if (ck::Is_NOT_Valid(Agent))
            {
                FinishFailure("an agent went invalid before timeout — possible early destroy / replication issue");
                return;
            }
            const auto Loc = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(Agent)));
            const auto DistToCentre = float((Loc - Centre).Size());
            Assert_True(DistToCentre <= ArrivalWindow,
                f"agent failed to reach within {ArrivalWindow}cm of centre — final {DistToCentre}cm");
            Finals.Add(Loc);
        }
        for (int32 i = 0; i < Finals.Num(); ++i)
        {
            for (int32 j = i + 1; j < Finals.Num(); ++j)
            {
                const auto PairSep = float((Finals[i] - Finals[j]).Size());
                Assert_True(PairSep >= MinPairwiseSep,
                    f"agents {i} and {j} ended within {MinPairwiseSep}cm — pile-up at goal ({PairSep}cm)");
            }
        }
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

class ACk_AutoTest_Crowd_Separation_Convergence_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Separation_Convergence;
    default _TimeoutSeconds = 10.0f;
}
