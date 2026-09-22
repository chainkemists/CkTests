// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: A BODY THAT HAS SETTLED ON THE GOAL STILL HOLDS A LATECOMER
//============================================================================
//
// A squatter stands on the goal long enough for its stationary markup to be CONFIRMED on the
// navmesh. Only then is a latecomer sent to the same point. The latecomer must be held
// GoalOccupied by the squatter, naming it, and must never report the goal reached.
//
// Why the ORDER is the whole test: the strict planning phase excludes the markup area, and the
// goal is inside the squatter's markup. The strict answer must read as a route that ends SHORT of
// the goal, so the episode re-plans permissively, walks at the goal, and BlockDetect names the
// body standing on it. If the goal is instead moved out to the markup's edge, the route reads
// Ready, the latecomer stops a body-width short and is told it ARRIVED - no block is ever raised,
// and every consumer of OnGoalBlocked (a queue manager, a shopper rotating to another shelf)
// never hears about the occupied goal. Sending both agents together, before the markup exists,
// never exercises that path.
//
// Would each assertion hold if the goal were moved? No: the latecomer reaches the markup edge
// (a genuine arrival as far as Steering can tell), OnGoalReached fires, and the route it was
// handed ends a body-width from the goal.
//============================================================================

class UCk_AutoTest_Crowd_Goal_ConfirmedSquatterHoldsLatecomer : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    private FCk_Handle_CrowdAgent _Squatter;
    private FCk_Handle_CrowdAgent _Latecomer;

    private bool _LatecomerBlockedByTheSquatter = false;
    private bool _LatecomerReachedGoal = false;

    private const FVector Goal           = FVector(400.0, 0.0, 0.0);
    private const FVector LatecomerSpawn = FVector(-300.0, 0.0, 0.0);

    // FCk_Fragment_CrowdAgent_ParamsData's default _ArrivalRadius. The route a genuine arrival is
    // walked along ends inside it; the markup edge is a body-width (2 x 42uu) out.
    private const float ArrivalRadiusCm = 30.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();

        Add_Step(           "bake the navmesh and stand a squatter on the goal",
                            n"Step_Setup");
        Add_Step_WaitUntil( "the squatter's stationary markup is confirmed on the navmesh",
                            n"Check_SquatterMarkupConfirmed", 0, 15.0f);
        Add_Step(           "only now send a latecomer to the goal the squatter stands on",
                            n"Step_SendLatecomer");
        Add_Step_WaitUntil( "the latecomer is held by the squatter, or reports an arrival",
                            n"Check_LatecomerHeldOrArrived", 0, 15.0f);
        Add_Step(           "held GoalOccupied naming the squatter, never arrived, and routed to the goal itself",
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

        _Squatter = SpawnAgent(LocalHandle, Goal, n"ConfirmedSquatter_Squatter");
        _Latecomer = SpawnAgent(LocalHandle, LatecomerSpawn, n"ConfirmedSquatter_Latecomer");

        utils_crowd_agent::BindTo_OnGoalReached(_Latecomer,
            FCk_Delegate_CrowdAgent_OnGoalReached(this, n"OnLatecomerArrived"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::BindTo_OnGoalBlocked(_Latecomer,
            FCk_Delegate_CrowdAgent_OnGoalBlocked(this, n"OnLatecomerBlocked"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);
    }

    UFUNCTION()
    private void Check_SquatterMarkupConfirmed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_crowd_agent::Get_IsStationaryMarkupConfirmed(_Squatter));
    }

    UFUNCTION()
    private void Step_SendLatecomer(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_crowd_agent::Request_MoveTo(_Latecomer, FCk_Request_CrowdAgent_MoveTo(Goal));
    }

    UFUNCTION()
    private void Check_LatecomerHeldOrArrived(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_LatecomerBlockedByTheSquatter || _LatecomerReachedGoal);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(!_LatecomerReachedGoal,
            f"the latecomer reported the goal reached at {Get_Location(_Latecomer)}, {Get_DistanceToGoal2D(_Latecomer)}cm from a goal a settled body stands on - its route was moved off the goal");

        Assert_True(_LatecomerBlockedByTheSquatter,
            "the latecomer was never held GoalOccupied by the squatter standing on its goal");

        const auto Route = utils_nav::Get_PathResult(FCk_Handle(_Latecomer));
        Assert_True(Route.Get_Waypoints().Num() > 0,
            "the latecomer holds no route at all");
        if (Route.Get_Waypoints().Num() == 0)
        { return; }

        const auto RouteEnd = Route.Get_Waypoints().Last();
        const auto RouteEndToGoal = float((RouteEnd - Goal).Size2D());
        Assert_True(RouteEndToGoal <= ArrivalRadiusCm,
            f"the latecomer's route ends at {RouteEnd}, {RouteEndToGoal}cm from the goal - it was planned to somewhere the caller never asked for");

        FinishSuccess();
    }

    // ---- Signals ------------------------------------------------------------------------------------

    UFUNCTION()
    private void OnLatecomerArrived(FCk_Handle_CrowdAgent InAgent)
    {
        _LatecomerReachedGoal = true;
    }

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

    private float Get_DistanceToGoal2D(FCk_Handle_CrowdAgent InAgent)
    {
        return float((Get_Location(InAgent) - Goal).Size2D());
    }

    private FCk_Handle_CrowdAgent SpawnAgent(FCk_Handle& InOwner, FVector InSpawn, FName InDebugName)
    {
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        AgentEntity.Set_DebugName(InDebugName);

        auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(FRotator::ZeroRotator, InSpawn, FVector::OneVector),
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
