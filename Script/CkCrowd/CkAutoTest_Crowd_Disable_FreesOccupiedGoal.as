// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A DISABLED AGENT FREES THE GOAL IT STANDS ON
//============================================================================
//
// A squatter arrives, comes to rest ON the goal, and paints a confirmed stationary disc - the
// hardest body the crowd has. A latecomer sent to the same point is held GoalOccupied by it.
//
// The squatter is then taken out of the crowd with Request_EnableDisable(Disable) and NOT moved.
// A disabled agent is ABSENT, so:
//
//   1. the held latecomer RESUMES and takes the goal - walking to the very spot the squatter
//      still stands on, because nothing perceives it any more;
//   2. the squatter is not shoved while that happens (nothing pushes a body that is not there);
//   3. its stationary markup is gone.
//
// Would each assertion hold if Disable did nothing? No: the latecomer would stay held forever
// behind a confirmed hard body, which is exactly the tunnel pile-up this API exists for.
//============================================================================

class UCk_AutoTest_Crowd_Disable_FreesOccupiedGoal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;

    private FCk_Handle_CrowdAgent _Squatter;
    private FCk_Handle_CrowdAgent _Latecomer;

    private bool _SquatterArrived = false;
    private bool _LatecomerBlockedByTheSquatter = false;
    private bool _LatecomerReachedGoal = false;
    private bool _DisableCompleted = false;
    private ECk_Request_OperationResult _DisableResult = ECk_Request_OperationResult::Failed;
    private FVector _SquatterRestPos = FVector::ZeroVector;

    private const FVector Goal           = FVector(400.0, 0.0, 0.0);
    private const FVector SquatterSpawn  = FVector(200.0, 0.0, 0.0);
    private const FVector LatecomerSpawn = FVector(-300.0, 0.0, 0.0);

    private const float SettledSpeedCm = 5.0;

    // A body out of the crowd is neither steered nor pushed; allow float noise only.
    private const float MaxSquatterDriftCm = 1.0;

    private const float MaxArrivedDistToGoalCm = 45.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Sent together: a latecomer sent after the squatter's disc confirms plans strictly to the disc's
        // edge, never ends on the squatter, and so is never held GoalOccupied.
        Add_Step(           "bake the navmesh, spawn both agents and send both to the same goal",
                            n"Step_Setup");
        Add_Step_WaitUntil( "the latecomer is held GoalOccupied, naming the squatter",
                            n"Check_LatecomerHeldByTheSquatter", 0, 15.0f);
        Add_Step_WaitUntil( "the squatter rests on the goal with its stationary markup confirmed",
                            n"Check_SquatterIsAHardBodyOnTheGoal", 0, 15.0f);
        Add_Step(           "take the squatter out of the crowd without moving it",
                            n"Step_DisableSquatter");
        Add_Step_WaitUntil( "the latecomer resumes and takes the goal",
                            n"Check_LatecomerReachedGoal", 0, 15.0f);
        Add_Step(           "the latecomer stands on the goal; the squatter stayed put, disabled and unpainted",
                            n"Step_Verify");

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

        _Squatter = SpawnAgent(LocalHandle, SquatterSpawn, n"Disable_Squatter");
        _Latecomer = SpawnAgent(LocalHandle, LatecomerSpawn, n"Disable_Latecomer");

        utils_crowd_agent::BindTo_OnGoalReached(_Squatter,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnSquatterArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalReached(_Latecomer,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnLatecomerArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalBlocked(_Latecomer,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnLatecomerBlocked"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Squatter, FCk_Request_CrowdAgent_MoveTo(Goal));
        utils_crowd_agent::Request_MoveTo(_Latecomer, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_SquatterIsAHardBodyOnTheGoal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_SquatterArrived
            && Get_Speed(_Squatter) <= SettledSpeedCm
            && utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Squatter));
    }

    UFUNCTION()
    private void Check_LatecomerHeldByTheSquatter(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_LatecomerBlockedByTheSquatter && utils_crowd_agent::Get_IsGoalBlocked(_Latecomer));
    }

    UFUNCTION()
    private void Step_DisableSquatter(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(!_LatecomerReachedGoal,
            "the latecomer reached the goal while the squatter still stood on it - the precondition this test needs (a held latecomer) was never established");

        _SquatterRestPos = Get_Location(_Squatter);
        utils_crowd_agent::Request_EnableDisable(_Squatter,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnSquatterDisableCompleted"));
    }

    UFUNCTION()
    private void Check_LatecomerReachedGoal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_LatecomerReachedGoal);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_DisableCompleted && _DisableResult == ECk_Request_OperationResult::Succeeded,
            f"the Disable request did not complete Succeeded (completed={_DisableCompleted}, result={_DisableResult})");

        Assert_True(!utils_crowd_agent::Get_IsEnabled(_Squatter),
            "Get_IsEnabled still reports the squatter enabled after its Disable drained");

        const auto Drift = float((Get_Location(_Squatter) - _SquatterRestPos).Size());
        Assert_True(Drift <= MaxSquatterDriftCm,
            f"the disabled squatter moved {Drift}cm while the latecomer took its spot (limit {MaxSquatterDriftCm}cm) - something still pushes or steers a body that is out of the crowd");

        Assert_True(!utils_crowd_agent::Get_IsStationaryMarkupPainted(_Squatter),
            "the disabled squatter still paints its stationary disc - every planner keeps routing around a body that is not there");

        // Well inside the disc's 84uu half-extent, so stopping at the edge of a stale disc fails this.
        const auto LatecomerDistToGoal = float((Get_Location(_Latecomer) - Goal).Size2D());
        Assert_True(LatecomerDistToGoal <= MaxArrivedDistToGoalCm,
            f"the latecomer 'arrived' {LatecomerDistToGoal}cm from the goal (limit {MaxArrivedDistToGoalCm}cm) - it stopped short of ground the disabled squatter no longer occupies");

        FinishSuccess();
    }

    // ---- Signals ------------------------------------------------------------------------------------

    UFUNCTION()
    private void OnSquatterArrived(FCk_Handle_CrowdAgent InAgent)
    {
        _SquatterArrived = true;
    }

    UFUNCTION()
    private void OnLatecomerArrived(FCk_Handle_CrowdAgent InAgent)
    {
        _LatecomerReachedGoal = true;
    }

    UFUNCTION()
    private void OnLatecomerBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        ck::crowd::Log(f"[DISABLE-FREES-GOAL] latecomer BLOCKED: reason={InInfo.Get_Reason()} blockedBy={InInfo.Get_BlockedBy().ToString()} squatter={FCk_Handle(_Squatter).ToString()} distToGoal={InInfo.Get_DistanceToGoal()}");
        if (InInfo.Get_Reason() == ECk_CrowdAgent_BlockedReason::GoalOccupied
            && InInfo.Get_BlockedBy() == FCk_Handle(_Squatter))
        { _LatecomerBlockedByTheSquatter = true; }
    }

    UFUNCTION()
    private void OnSquatterDisableCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _DisableCompleted = true;
        _DisableResult = InResult;
    }

    // ---- Helpers ------------------------------------------------------------------------------------

    private FVector Get_Location(FCk_Handle_CrowdAgent InAgent)
    {
        return utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(InAgent)));
    }

    private float Get_Speed(FCk_Handle_CrowdAgent InAgent)
    {
        return float(utils_velocity::Get_CurrentVelocity(
            utils_velocity::DoCastChecked(FCk_Handle(InAgent))).Size());
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_CrowdAgent_Spec(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        const auto Rot = (Goal - InSpawn).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(Rot, InSpawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_velocity::Add(AgentEntity,
            FCk_Velocity_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Acceleration_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        return Agent;
    }
}
