// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A RE-ENABLED AGENT IS A BODY AGAIN
//============================================================================
//
// The other half of Request_EnableDisable. An agent standing on a goal is taken out of the crowd,
// refuses movement while it is out, and is then put back. Once back it must be a full body again:
// a newcomer sent to the goal is held GoalOccupied by it, naming it.
//
// That last assertion is what makes the round trip meaningful. If Enable failed to restore the
// probe or the neighbour-side visibility, the newcomer would walk straight onto the goal.
//============================================================================

class UCk_AutoTest_Crowd_Disable_ReenableRestoresBody : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle_CrowdAgent _Squatter;
    private FCk_Handle_CrowdAgent _Newcomer;

    private bool _MoveWhileDisabledCompleted = false;
    private ECk_Request_OperationResult _MoveWhileDisabledResult = ECk_Request_OperationResult::Succeeded;
    private bool _EnableCompleted = false;
    private ECk_Request_OperationResult _EnableResult = ECk_Request_OperationResult::Failed;

    private bool _NewcomerBlockedByTheSquatter = false;
    private bool _NewcomerReachedGoal = false;
    private FVector _SquatterPosWhenDisabled = FVector::ZeroVector;

    private const FVector Goal          = FVector(400.0, 0.0, 0.0);
    private const FVector NewcomerSpawn = FVector(-300.0, 0.0, 0.0);
    private const FVector RefusedTarget = FVector(400.0, 400.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(           "bake the navmesh and stand a squatter on the goal",
                            n"Step_Setup");
        Add_Step(           "take the squatter out of the crowd",
                            n"Step_Disable");
        Add_Step_WaitUntil( "the Disable has drained",
                            n"Check_SquatterDisabled");
        Add_Step(           "ask the disabled squatter to move",
                            n"Step_MoveWhileDisabled");
        Add_Step_WaitUntil( "the refused MoveTo reports its outcome",
                            n"Check_MoveWhileDisabledCompleted");
        Add_Step(           "the move was refused and the squatter never left the goal",
                            n"Step_AssertRefused");
        Add_Step(           "put the squatter back into the crowd",
                            n"Step_Enable");
        Add_Step_WaitUntil( "the Enable has drained",
                            n"Check_SquatterEnabled");
        Add_Step(           "send a newcomer to the goal the squatter stands on",
                            n"Step_SendNewcomer");
        Add_Step_WaitUntil( "the newcomer is held GoalOccupied by the re-enabled squatter",
                            n"Check_NewcomerHeldByTheSquatter", 0, 15.0f);
        Add_Step(           "the newcomer never reached the occupied goal",
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

        _Squatter = SpawnAgent(LocalHandle, Goal, n"Reenable_Squatter");
        _Newcomer = SpawnAgent(LocalHandle, NewcomerSpawn, n"Reenable_Newcomer");

        utils_crowd_agent::BindTo_OnGoalReached(_Newcomer,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnNewcomerArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalBlocked(_Newcomer,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnNewcomerBlocked"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
    }

    UFUNCTION()
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_EnableDisable(_Squatter,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Disable));
    }

    UFUNCTION()
    private void Check_SquatterDisabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!utils_crowd_agent::Get_IsEnabled(_Squatter));
    }

    UFUNCTION()
    private void Step_MoveWhileDisabled(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _SquatterPosWhenDisabled = Get_Location(_Squatter);
        utils_crowd_agent::Request_MoveTo(_Squatter,
            FCk_Request_CrowdAgent_MoveTo(RefusedTarget),
            FCk_Delegate_Request_OnCompleted(this, n"OnMoveWhileDisabledCompleted"));
    }

    UFUNCTION()
    private void Check_MoveWhileDisabledCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_MoveWhileDisabledCompleted);
    }

    UFUNCTION()
    private void Step_AssertRefused(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_MoveWhileDisabledResult == ECk_Request_OperationResult::Failed,
            f"a MoveTo on a disabled agent completed {_MoveWhileDisabledResult} - it must be refused (Failed), never silently accepted or dropped");

        Assert_True(utils_crowd_agent::Get_MovementState(_Squatter) == ECk_CrowdAgent_MovementState::Idle,
            f"the refused MoveTo started a movement episode anyway (state={utils_crowd_agent::Get_MovementState(_Squatter)})");

        const auto Drift = float((Get_Location(_Squatter) - _SquatterPosWhenDisabled).Size());
        Assert_True(Drift <= 1.0f,
            f"the disabled squatter moved {Drift}cm after a refused MoveTo");
    }

    UFUNCTION()
    private void Step_Enable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_EnableDisable(_Squatter,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableCompleted"));
    }

    UFUNCTION()
    private void Check_SquatterEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_EnableCompleted && utils_crowd_agent::Get_IsEnabled(_Squatter));
    }

    UFUNCTION()
    private void Step_SendNewcomer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_EnableResult == ECk_Request_OperationResult::Succeeded,
            f"the Enable request completed {_EnableResult}, not Succeeded");

        utils_crowd_agent::Request_MoveTo(_Newcomer, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_NewcomerHeldByTheSquatter(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_NewcomerBlockedByTheSquatter || _NewcomerReachedGoal);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(!_NewcomerReachedGoal,
            "the newcomer reached the goal the re-enabled squatter stands on - Enable did not put the body back into the crowd");

        Assert_True(_NewcomerBlockedByTheSquatter,
            "the newcomer was never held GoalOccupied by the re-enabled squatter");

        FinishSuccess();
    }

    // ---- Signals ------------------------------------------------------------------------------------

    UFUNCTION()
    private void OnNewcomerArrived(FCk_Handle_CrowdAgent InAgent)
    {
        _NewcomerReachedGoal = true;
    }

    UFUNCTION()
    private void OnNewcomerBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (InInfo.Get_Reason() == ECk_CrowdAgent_BlockedReason::GoalOccupied
            && InInfo.Get_BlockedBy() == FCk_Handle(_Squatter))
        { _NewcomerBlockedByTheSquatter = true; }
    }

    UFUNCTION()
    private void OnMoveWhileDisabledCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _MoveWhileDisabledCompleted = true;
        _MoveWhileDisabledResult = InResult;
    }

    UFUNCTION()
    private void OnEnableCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _EnableCompleted = true;
        _EnableResult = InResult;
    }

    // ---- Helpers ------------------------------------------------------------------------------------

    private FVector Get_Location(FCk_Handle_CrowdAgent InAgent)
    {
        return utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(InAgent)));
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_CrowdAgent_Spec(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector),
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
