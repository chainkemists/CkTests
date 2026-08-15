// Language=angelscript

//============================================================================
// CK PATH NETWORK — AUTOMATION TEST: THE ROUTE-QUERY BUDGET IS PER FRAME
//============================================================================
//
// FProcessor_PathNetworkFollower_HandleRequests caps route plans at
// _MaxRouteQueriesPerFrame. That cap is only meaningful if it is a per-FRAME
// cap: the processor is pump-eligible (MarkedDirtyBy its own Requests
// fragment) and Pump() calls Tick(0) -> DoTick, so a budget re-armed in
// DoTick hands every pump pass a fresh allowance — up to budget x
// _MaxPumpIterations synchronous Recast queries in a single frame.
//
//   1. Build the L network (the RebuildReplansRoute fixture) and 3 x budget
//      followers on it, all in one frame.
//   2. Every follower issues one FindRoute to the same reachable goal in the
//      SAME frame. That frame is the seed frame.
//   3. Sample the settled count once per frame afterwards: the cumulative
//      settled count may never exceed budget x (frames elapsed since the seed
//      frame, inclusive). Anything above that is a re-armed budget.
//   4. Within the watch window ALL of them must settle (the cap throttles, it
//      must not starve).
//   5. Every settled route is Ready — the throttle must not break the route.
//
// Why the invariant is expressed cumulatively rather than as a single
// "count once, one frame later" reading: the test's callbacks ride a timer
// whose position within the frame relative to the route processor is not
// contracted, so a single sample cannot say which frames' drains it contains.
// The cumulative bound is exact under either ordering.
//============================================================================

class UCk_AutoTest_PathNetworkFollower_RouteBudgetIsPerFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_PathNetwork _Network;
    private TArray<FCk_Handle_PathNetworkFollower> _Followers;

    private int32 _Budget = 0;
    private int32 _FollowerCount = 0;

    private int64 _SeedFrame = 0;
    private int64 _LastSampledFrame = 0;
    private int32 _FramesSampled = 0;
    private int32 _FramesToWatch = 0;
    private FString _Violation = "";
    private FString _Trace = "";

    private const FVector Goal = FVector(450.0, 450.0, 0.0);
    private const FVector Start = FVector(-50.0, 25.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _Owner = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, Start, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        // Same fixture geometry as CkAutoTest_PathNetworkFollower_RebuildReplansRoute:
        // an L from the origin, already proven to resolve a route in this test world.
        TArray<FCk_PathNetwork_RibbonPoint> PointsA;
        PointsA.Add(FCk_PathNetwork_RibbonPoint(FVector(0.0, 0.0, 0.0), 100.0));
        PointsA.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 0.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_RibbonPoint> PointsB;
        PointsB.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 0.0, 0.0), 100.0));
        PointsB.Add(FCk_PathNetwork_RibbonPoint(FVector(400.0, 400.0, 0.0), 100.0));

        TArray<FCk_PathNetwork_Ribbon> Ribbons;
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsA));
        Ribbons.Add(FCk_PathNetwork_Ribbon(PointsB));

        _Network = utils_path_network::Add(LocalHandle, FCk_Fragment_PathNetwork_ParamsData(Ribbons));

        _Budget = utils_path_network_settings::Get_MaxRouteQueriesPerFrame();

        Assert_True(_Budget > 0,
            f"the route-query budget must be a positive cap for this test to mean anything (budget={_Budget})");

        _FollowerCount = 3 * _Budget;
        _FramesToWatch = ((_FollowerCount + _Budget - 1) / _Budget) + 3;

        for (int32 i = 0; i < _FollowerCount; ++i)
        {
            auto Child = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
            utils_transform::Add(Child,
                FTransform(FRotator::ZeroRotator, Start, FVector::OneVector),
                ECk_Replication::DoesNotReplicate);

            auto FollowerParams = FCk_Fragment_PathNetworkFollower_ParamsData();
            FollowerParams.Set_Network(_Network);
            FollowerParams.Set_CorridorWaypointSpacing(100.0);

            _Followers.Add(utils_path_network_follower::Add(Child, FollowerParams));
        }

        WaitUntil(n"Check_NetworkBuilt", n"OnNetworkReadyToRoute");
    }

    UFUNCTION()
    private void Check_NetworkBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_path_network::Get_IsBuilt(_Network));
    }

    UFUNCTION()
    private void OnNetworkReadyToRoute(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _SeedFrame = utils_time::Get_FrameCounter();
        _LastSampledFrame = _SeedFrame;

        for (int32 i = 0; i < _Followers.Num(); ++i)
        {
            auto Follower = _Followers[i];
            utils_path_network_follower::Request_FindRoute(Follower,
                FCk_Request_PathNetworkFollower_FindRoute(Goal));
        }

        utils_timer::Create_Tick(_Owner, FCk_Delegate_Timer(this, n"OnFrameSample"));
    }

    UFUNCTION()
    private void OnFrameSample(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        const auto Frame = utils_time::Get_FrameCounter();
        if (Frame <= _LastSampledFrame) { return; }

        _LastSampledFrame = Frame;
        _FramesSampled++;

        const auto FramesElapsed = int32(Frame - _SeedFrame) + 1;
        const auto Allowance = _Budget * FramesElapsed;
        const auto Settled = Count_Settled();

        _Trace += f" f+{FramesElapsed - 1}:{Settled}";

        if (Settled > Allowance && _Violation == "")
        {
            _Violation = f"settled={Settled}, budget={_Budget}, frames elapsed={FramesElapsed}, allowance={Allowance}";
        }

        if (_FramesSampled < _FramesToWatch) { return; }

        Do_Adjudicate();
    }

    private void Do_Adjudicate()
    {
        const auto Settled = Count_Settled();
        const auto Ready = Count_Ready();
        const auto Total = _FollowerCount;
        const auto Violation = _Violation;
        const auto Trace = _Trace;

        Assert_True(_Violation == "",
            f"route drain must respect the per-FRAME budget ({Violation}); more means the pump re-armed the budget each pass [trace:{Trace}]");

        Assert_True(Settled == Total,
            f"the per-frame budget must throttle, not starve: every route must settle within the watch window (settled={Settled}, expected={Total}) [trace:{Trace}]");

        Assert_True(Ready == Settled,
            f"every settled route must be Ready, not Failed — the same goal the fixture proves reachable (ready={Ready}, settled={Settled})");

        FinishSuccess();
    }

    private int32 Count_Settled()
    {
        int32 Count = 0;

        for (int32 i = 0; i < _Followers.Num(); ++i)
        {
            const auto Result = utils_path_network_follower::Get_RouteResult(_Followers[i]);
            if (Result.Get_Status() != ECk_PathNetwork_RouteStatus::Pending)
            { Count++; }
        }

        return Count;
    }

    private int32 Count_Ready()
    {
        int32 Count = 0;

        for (int32 i = 0; i < _Followers.Num(); ++i)
        {
            const auto Result = utils_path_network_follower::Get_RouteResult(_Followers[i]);
            if (Result.Get_Status() == ECk_PathNetwork_RouteStatus::Ready)
            { Count++; }
        }

        return Count;
    }
}
