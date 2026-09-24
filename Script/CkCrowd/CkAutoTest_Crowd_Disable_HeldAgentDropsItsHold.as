// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A HELD AGENT TAKEN OUT OF THE CROWD DROPS ITS HOLD FOR GOOD
//============================================================================
//
// A latecomer is held GoalOccupied behind a squatter standing on their shared goal. The LATECOMER
// is then disabled. Disable ends its movement episode as a Stop does, so the hold goes with it:
//
//   1. it no longer reports itself goal-blocked, and has no active goal;
//   2. BlockedRecheck does not resume it while it is out (it is excluded, and the hold is gone);
//   3. Enable does not resurrect the old episode either - it comes back Idle, and the next move is
//      the owner's to issue.
//
// The sibling case - a dependent held ON a disabled body resuming - is
// CkAutoTest_Crowd_Disable_FreesOccupiedGoal.
//
// Would each assertion hold if Disable did nothing? No: the latecomer would stay goal-blocked with
// its goal retained, and the recheck would resume it the moment the goal cleared.
//============================================================================

class UCk_AutoTest_Crowd_Disable_HeldAgentDropsItsHold : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 45.0f;

    private FCk_Handle_CrowdAgent _Squatter;
    private FCk_Handle_CrowdAgent _Latecomer;

    private bool _LatecomerBlockedByTheSquatter = false;
    private FVector _LatecomerPosWhenDisabled = FVector::ZeroVector;

    private const FVector Goal           = FVector(400.0, 0.0, 0.0);
    private const FVector SquatterSpawn  = FVector(200.0, 0.0, 0.0);
    private const FVector LatecomerSpawn = FVector(-300.0, 0.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        // Both are sent together, as in Crowd_Goal_OccupiedGoal, so the latecomer's path ends on the
        // squatter and the hold is GoalOccupied.
        Add_Step(           "bake the navmesh, spawn both agents and send both to the same goal",
                            n"Step_Setup");
        Add_Step_WaitUntil( "the latecomer is held GoalOccupied, naming the squatter",
                            n"Check_LatecomerHeldByTheSquatter", 0, 15.0f);
        Add_Step(           "take the HELD agent out of the crowd",
                            n"Step_DisableLatecomer");
        Add_Step_WaitUntil( "the Disable has drained",
                            n"Check_LatecomerDisabled");
        Add_Step(           "its hold and its goal went with the episode",
                            n"Step_AssertHoldDropped");
        Add_Step_WaitSeconds("several BlockedRecheck cadences pass while it is out",
                            1.5f);
        Add_Step(           "nothing resumed or moved it, then put it back",
                            n"Step_AssertStillOutAndEnable");
        Add_Step_WaitUntil( "the Enable has drained",
                            n"Check_LatecomerEnabled");
        Add_Step_WaitSeconds("give a resurrected episode time to show itself",
                            1.0f);
        Add_Step(           "it came back Idle, with no goal and no hold",
                            n"Step_AssertBackIdle");

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

        _Squatter = SpawnAgent(LocalHandle, SquatterSpawn, n"HeldDrops_Squatter");
        _Latecomer = SpawnAgent(LocalHandle, LatecomerSpawn, n"HeldDrops_Latecomer");

        utils_crowd_agent::BindTo_OnGoalBlocked(_Latecomer,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnLatecomerBlocked"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Squatter, FCk_Request_CrowdAgent_MoveTo(Goal));
        utils_crowd_agent::Request_MoveTo(_Latecomer, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_LatecomerHeldByTheSquatter(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_LatecomerBlockedByTheSquatter && utils_crowd_agent::Get_IsGoalBlocked(_Latecomer));
    }

    UFUNCTION()
    private void Step_DisableLatecomer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_EnableDisable(_Latecomer,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Disable));
    }

    UFUNCTION()
    private void Check_LatecomerDisabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(!utils_crowd_agent::Get_IsEnabled(_Latecomer));
    }

    UFUNCTION()
    private void Step_AssertHoldDropped(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _LatecomerPosWhenDisabled = Get_Location(_Latecomer);
        Assert_NoHoldAndIdle("right after the Disable drained");
    }

    UFUNCTION()
    private void Step_AssertStillOutAndEnable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_NoHoldAndIdle("while it was out of the crowd");

        const auto Drift = float((Get_Location(_Latecomer) - _LatecomerPosWhenDisabled).Size());
        Assert_True(Drift <= 1.0f,
            f"the disabled latecomer moved {Drift}cm while it was out of the crowd");

        utils_crowd_agent::Request_EnableDisable(_Latecomer,
            FCk_Request_CrowdAgent_EnableDisable(ECk_EnableDisable::Enable));
    }

    UFUNCTION()
    private void Check_LatecomerEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_IsEnabled(_Latecomer));
    }

    UFUNCTION()
    private void Step_AssertBackIdle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_NoHoldAndIdle("after it was enabled again");
        FinishSuccess();
    }

    private void Assert_NoHoldAndIdle(const FString& InWhen)
    {
        Assert_True(!utils_crowd_agent::Get_IsGoalBlocked(_Latecomer),
            f"{InWhen}, the latecomer still reports itself goal-blocked - the hold outlived the episode Disable ended");

        Assert_True(utils_crowd_agent::Get_MovementState(_Latecomer) == ECk_CrowdAgent_MovementState::Idle,
            f"{InWhen}, the latecomer has a movement episode (state={utils_crowd_agent::Get_MovementState(_Latecomer)})");

        Assert_True(utils_crowd_agent::Get_ActiveGoal(_Latecomer).IsNearlyZero(),
            f"{InWhen}, the latecomer still holds goal {utils_crowd_agent::Get_ActiveGoal(_Latecomer)} - a recheck could resume it");
    }

    // ---- Signals ------------------------------------------------------------------------------------

    UFUNCTION()
    private void OnLatecomerBlocked(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalBlockedInfo InInfo)
    {
        if (InInfo.Get_Reason() == ECk_CrowdAgent_BlockedReason::GoalOccupied
            && InInfo.Get_BlockedBy() == FCk_Handle(_Squatter))
        { _LatecomerBlockedByTheSquatter = true; }
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
