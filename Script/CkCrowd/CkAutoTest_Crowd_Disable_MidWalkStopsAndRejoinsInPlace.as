// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: DISABLING A WALKING AGENT STOPS IT DEAD, AND IT REJOINS IN PLACE
//============================================================================
//
// Disable ends the movement episode as a Stop does, and also zeroes the velocity the bridge will
// no longer write - a body left carrying its cruise velocity would read as still moving to every
// velocity-keyed consumer. While out, nothing may move it. On Enable it must rejoin exactly where
// it stood (no accumulated integrator offset landing on the first frame back) and walk normally.
//============================================================================

class UCk_AutoTest_Crowd_Disable_MidWalkStopsAndRejoinsInPlace : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle_CrowdAgent _Walker;
    private bool _WalkerReachedGoal = false;
    private FVector _PosAtDisableRequest = FVector::ZeroVector;
    private FVector _PosWhenDisabled = FVector::ZeroVector;

    private const FVector Spawn = FVector(-400.0, 0.0, 0.0);
    private const FVector Goal  = FVector(600.0, 0.0, 0.0);

    private const float CruisingSpeedCm = 100.0;

    // The Disable drains on the processor pass after it is requested; one or two frames of travel at
    // cruise speed may land in between.
    private const float MaxStopDistanceCm = 40.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(           "bake the navmesh and send a walker across it",
                            n"Step_Setup");
        Add_Step_WaitUntil( "the walker is cruising",
                            n"Check_WalkerCruising", 0, 10.0f);
        Add_Step(           "take the walker out of the crowd mid-stride",
                            n"Step_Disable");
        Add_Step_WaitUntil( "the Disable has drained",
                            n"Check_WalkerDisabled");
        Add_Step(           "it stopped within a frame or two, with zero velocity",
                            n"Step_AssertStopped");
        Add_Step_WaitSeconds("nothing moves the disabled walker for a second",
                            1.0f);
        Add_Step(           "it is exactly where it stopped, then put it back",
                            n"Step_AssertHeldAndEnable");
        Add_Step_WaitUntil( "the Enable has drained",
                            n"Check_WalkerEnabled");
        Add_Step(           "it rejoined where it stood, and walks on",
                            n"Step_AssertRejoinedInPlaceAndResume");
        Add_Step_WaitUntil( "the re-enabled walker reaches its goal",
                            n"Check_WalkerReachedGoal", 0, 15.0f);
        Add_Step(           "done",
                            n"Step_Finish");

        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Setup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        _Walker = SpawnAgent(LocalHandle, Spawn, n"MidWalk_Walker");
        utils_crowd_agent::BindTo_OnGoalReached(_Walker,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnWalkerArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_WalkerCruising(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Get_Speed() >= CruisingSpeedCm);
    }

    UFUNCTION()
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PosAtDisableRequest = Get_Location();
        utils_crowd_agent::Request_EnableDisable(_Walker,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Disable));
    }

    UFUNCTION()
    private void Check_WalkerDisabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!utils_crowd_agent::Get_IsEnabled(_Walker));
    }

    UFUNCTION()
    private void Step_AssertStopped(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PosWhenDisabled = Get_Location();

        const auto StopDistance = float((_PosWhenDisabled - _PosAtDisableRequest).Size());
        Assert_True(StopDistance <= MaxStopDistanceCm,
            f"the walker travelled {StopDistance}cm between the Disable request and its drain (limit {MaxStopDistanceCm}cm)");

        Assert_True(Get_Speed() <= 0.01f,
            f"the disabled walker still carries {Get_Speed()}cm/s - a stale velocity reads as a moving body");

        Assert_True(utils_crowd_agent::Get_MovementState(_Walker) == ECk_CrowdAgent_MovementState::Idle,
            f"Disable did not end the movement episode (state={utils_crowd_agent::Get_MovementState(_Walker)})");
    }

    UFUNCTION()
    private void Step_AssertHeldAndEnable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Drift = float((Get_Location() - _PosWhenDisabled).Size());
        Assert_True(Drift <= 1.0f,
            f"the disabled walker moved {Drift}cm in the second it was out of the crowd");

        utils_crowd_agent::Request_EnableDisable(_Walker,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Enable));
    }

    UFUNCTION()
    private void Check_WalkerEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_IsEnabled(_Walker));
    }

    UFUNCTION()
    private void Step_AssertRejoinedInPlaceAndResume(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Jump = float((Get_Location() - _PosWhenDisabled).Size());
        Assert_True(Jump <= 1.0f,
            f"the walker rejoined {Jump}cm away from where it stood - something accumulated while it was out");

        utils_crowd_agent::Request_MoveTo(_Walker, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_WalkerReachedGoal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_WalkerReachedGoal);
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FinishSuccess();
    }

    UFUNCTION()
    private void OnWalkerArrived(FCk_Handle_CrowdAgent InAgent)
    {
        _WalkerReachedGoal = true;
    }

    // ---- Helpers ------------------------------------------------------------------------------------

    private FVector Get_Location()
    {
        return utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(_Walker)));
    }

    private float Get_Speed()
    {
        return float(utils_velocity::Get_CurrentVelocity(
            utils_velocity::DoCastChecked(FCk_Handle(_Walker))).Size());
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        const auto Rot = (Goal - InSpawn).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, InSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        return Agent;
    }
}
