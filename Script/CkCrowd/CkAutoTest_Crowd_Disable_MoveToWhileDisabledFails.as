// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A MOVE REQUESTED OF A DISABLED AGENT FAILS, IT IS NOT DROPPED
//============================================================================
//
// A disabled agent is out of the crowd: nothing steers it, so a MoveTo could only start an episode
// that never advances. The request must complete Failed on its own completion channel - the
// caller learns the move was refused - and must leave the agent exactly as it was: Idle, still
// disabled, not moved. Enabling it afterwards makes the same move succeed, which proves the
// refusal was about the disabled state and not about the goal.
//
// Would each assertion hold if the refusal did nothing? No: an accepted MoveTo completes
// Succeeded and leaves the agent PathPending or Walking.
//============================================================================

class UCk_AutoTest_Crowd_Disable_MoveToWhileDisabledFails : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle_CrowdAgent _Agent;
    private FVector _PosWhenDisabled = FVector::ZeroVector;

    private bool _RefusedMoveCompleted = false;
    private ECk_Request_OperationResult _RefusedMoveResult = ECk_Request_OperationResult::Succeeded;
    private bool _AcceptedMoveCompleted = false;
    private ECk_Request_OperationResult _AcceptedMoveResult = ECk_Request_OperationResult::Failed;
    private bool _AgentReachedGoal = false;

    private const FVector Spawn = FVector(-300.0, 0.0, 0.0);
    private const FVector Goal  = FVector(400.0, 0.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(           "bake the navmesh, spawn an agent and take it out of the crowd",
                            n"Step_SetupAndDisable");
        Add_Step_WaitUntil( "the Disable has drained",
                            n"Check_AgentDisabled");
        Add_Step(           "ask the disabled agent to move",
                            n"Step_RequestMove");
        Add_Step_WaitUntil( "the move request completes",
                            n"Check_RefusedMoveCompleted");
        Add_Step(           "it completed Failed and left the agent Idle, disabled and in place",
                            n"Step_AssertRefusedAndEnable");
        Add_Step_WaitUntil( "the Enable has drained",
                            n"Check_AgentEnabled");
        Add_Step(           "ask again, now that it is back in the crowd",
                            n"Step_RequestMoveAgain");
        Add_Step_WaitUntil( "the enabled agent reaches the same goal",
                            n"Check_AgentReachedGoal", 0, 15.0f);
        Add_Step(           "the second request completed Succeeded",
                            n"Step_Verify");

        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_SetupAndDisable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        _Agent = SpawnAgent(LocalHandle, Spawn, n"MoveToWhileDisabled_Agent");
        utils_crowd_agent::BindTo_OnGoalReached(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnAgentArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_EnableDisable(_Agent,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Disable));
    }

    UFUNCTION()
    private void Check_AgentDisabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!utils_crowd_agent::Get_IsEnabled(_Agent));
    }

    UFUNCTION()
    private void Step_RequestMove(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PosWhenDisabled = Get_Location();
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal),
            FCk_Delegate_Request_OnCompleted(this, n"OnRefusedMoveCompleted"));
    }

    UFUNCTION()
    private void Check_RefusedMoveCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RefusedMoveCompleted);
    }

    UFUNCTION()
    private void Step_AssertRefusedAndEnable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_RefusedMoveResult == ECk_Request_OperationResult::Failed,
            f"a MoveTo on a disabled agent completed {_RefusedMoveResult}, expected Failed - the caller is told nothing refused its move");

        Assert_True(utils_crowd_agent::Get_MovementState(_Agent) == ECk_CrowdAgent_MovementState::Idle,
            f"the refused MoveTo started an episode on a disabled agent (state={utils_crowd_agent::Get_MovementState(_Agent)})");

        Assert_True(!utils_crowd_agent::Get_IsEnabled(_Agent),
            "the refused MoveTo put the agent back into the crowd");

        const auto Drift = float((Get_Location() - _PosWhenDisabled).Size());
        Assert_True(Drift <= 1.0f,
            f"the disabled agent moved {Drift}cm after a refused MoveTo");

        utils_crowd_agent::Request_EnableDisable(_Agent,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Enable));
    }

    UFUNCTION()
    private void Check_AgentEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_IsEnabled(_Agent));
    }

    UFUNCTION()
    private void Step_RequestMoveAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(Goal),
            FCk_Delegate_Request_OnCompleted(this, n"OnAcceptedMoveCompleted"));
    }

    UFUNCTION()
    private void Check_AgentReachedGoal(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_AgentReachedGoal);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_AcceptedMoveCompleted && _AcceptedMoveResult == ECk_Request_OperationResult::Succeeded,
            f"the MoveTo on the re-enabled agent did not complete Succeeded (completed={_AcceptedMoveCompleted}, result={_AcceptedMoveResult})");

        FinishSuccess();
    }

    // ---- Signals ------------------------------------------------------------------------------------

    UFUNCTION()
    private void OnRefusedMoveCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RefusedMoveCompleted = true;
        _RefusedMoveResult = InResult;
    }

    UFUNCTION()
    private void OnAcceptedMoveCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _AcceptedMoveCompleted = true;
        _AcceptedMoveResult = InResult;
    }

    UFUNCTION()
    private void OnAgentArrived(FCk_Handle_CrowdAgent InAgent)
    {
        _AgentReachedGoal = true;
    }

    // ---- Helpers ------------------------------------------------------------------------------------

    private FVector Get_Location()
    {
        return utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(FCk_Handle(_Agent)));
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
