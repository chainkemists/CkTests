// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A DISABLED AGENT TORN DOWN WITH A REQUEST QUEUED REPORTS IT CANCELLED
//============================================================================
//
// An owner that takes a body out of the crowd may lose the entity before its next participation
// request drains - an NPC destroyed or downed while dormant, with its wake's Enable still queued.
// Destruction is stamped the moment it is requested and the request drain skips a destroying agent,
// so that Enable never runs. It must still reach its requester, as Failed_Cancelled, and tearing
// down an agent whose probe child is disabled must raise nothing.
//
// Any ensure fails the running test, so the teardown half is asserted by the test finishing at all.
// Would the completion assertion hold if the cancel path dropped the request? No: the requester
// would wait forever, and the step bound names it.
//============================================================================

class UCk_AutoTest_Crowd_Disable_DestroyedWithRequestQueuedCancels : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _AgentEntity;
    private FCk_Handle_CrowdAgent _Agent;

    private bool _EnableCompleted = false;
    private ECk_Request_OperationResult _EnableResult = ECk_Request_OperationResult::Succeeded;

    private const FVector Spawn = FVector(0.0, 0.0, 0.0);
    private const FVector Facing = FVector(1.0, 0.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(           "bake the navmesh, spawn an agent and take it out of the crowd",
                            n"Step_SetupAndDisable");
        Add_Step_WaitUntil( "the Disable has drained",
                            n"Check_AgentDisabled");
        Add_Step(           "queue an Enable, then destroy the agent before it can drain",
                            n"Step_EnableThenDestroy");
        Add_Step_WaitUntil( "the queued Enable reaches its requester",
                            n"Check_EnableCompleted", 0, 5.0f);
        Add_Step(           "it completed Failed_Cancelled",
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

        _AgentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _AgentEntity.Set_DebugName(n"DestroyedWhileDisabled_Agent");

        auto AgentTransform = utils_transform::Add(_AgentEntity,
            FTransform(Facing.Rotation(), Spawn, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);
        _Agent = utils_crowd_agent::Add(AgentTransform, FCk_CrowdAgent_Spec(42.0f, 192.0f));
        utils_velocity::Add(_AgentEntity,
            FCk_Velocity_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(_AgentEntity,
            FCk_Acceleration_Spec(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(_AgentEntity);

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
    private void Step_EnableThenDestroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_EnableDisable(_Agent,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableCompleted"));

        utils_entity_lifetime::Request_DestroyEntity(_AgentEntity);
    }

    UFUNCTION()
    private void Check_EnableCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_EnableCompleted);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_EnableResult == ECk_Request_OperationResult::Failed_Cancelled,
            f"an Enable queued on an agent destroyed before it drained completed {_EnableResult}, expected Failed_Cancelled");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnEnableCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _EnableCompleted = true;
        _EnableResult = InResult;
    }
}
