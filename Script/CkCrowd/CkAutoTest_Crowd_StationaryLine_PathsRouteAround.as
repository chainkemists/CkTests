// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: PATHS ROUTE AROUND A STATIONARY LINE
//
// The stationary-markup tier (FProcessor_CrowdAgent_StationaryMarkup): agents
// that hold still paint a UCk_NavArea_CrowdAgent cost disc, so a fresh path for
// an agent headed past a standing crowd routes AROUND it instead of straight
// through.
//
// Shape: a picket line of 5 idle agents across the X axis at x=0. A path is
// queried from (-500,0) to (+500,0) — agent-blind pathfinding returns the
// straight line through the picket. With markup enabled, once the discs paint
// (stationary delay + async tile rebuild — hence the poll), the path detours
// around the line's end. Red-green via ECk_CrowdStationaryMarkupMode.
//============================================================================

class UCk_AutoTest_Crowd_StationaryLine_PathsRouteAround : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private const float PathStartX = -500.0;
    private const float PathEndX = 500.0;
    private const int32 PicketCount = 5;
    private const float PicketSpacingUu = 100.0;
    // Detour = every picket agent is at least this far from the path polyline. Straight-through
    // passes over the centre picket (clearance ~0); a detour around the line's end skirts the
    // outermost disc edge (half-extent 63uu at the default 1.5x multiplier), so ~55uu+ from the
    // outermost agent even when the funnel cuts the corner. 50 splits the two cases robustly.
    private const float MinClearanceUu = 50.0;
    private const int32 MaxAttempts = 16;

    private TArray<FVector> _PicketLocations;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private int32 _Attempts = 0;
    private float _LastWorstClearance = -1.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(PathStartX, 0.0, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Timer_Spec(FCk_Time(0.5));
        TimerParams.Set_StartingState(ECk_Timer_State::Running)
                   .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(LocalHandle, TimerParams);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnPoll"));
    }

    UFUNCTION()
    private void OnPoll(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SelfHandle = DoGet_ScriptEntity();

        if (_MeshFound == false)
        {
            FVector OriginOnMesh;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, OriginOnMesh, 300.0f) == false)
            { return; }   // bake not done yet

            _MeshFound = true;
            _FloorZ = float(OriginOnMesh.Z);
            SpawnPicketLine(SelfHandle);
            return;   // give the stationary delay + tile rebuild a beat before the first query
        }

        // Evaluate the previous round's result, then query again.
        if (utils_nav::Get_PathStatus(SelfHandle) == ECk_Nav_PathStatus::Ready)
        {
            const auto Result = utils_nav::Get_PathResult(SelfHandle);
            const auto WorstClearance = Compute_WorstClearance(Result.Get_Waypoints());
            _LastWorstClearance = WorstClearance;

            if (WorstClearance >= MinClearanceUu)
            {
                FinishSuccess();
                return;
            }
        }

        _Attempts += 1;
        if (_Attempts > MaxAttempts)
        {
            FinishFailure(f"path never detoured around the stationary line after {MaxAttempts} attempts — worst clearance {_LastWorstClearance}uu (need {MinClearanceUu}uu). Stationary markup is not steering paths.");
            return;
        }

        utils_nav::Request_FindPath(SelfHandle,
            FCk_Request_Nav_FindPath(FVector(PathEndX, 0.0, _FloorZ)));
    }

    // Min distance from any picket agent to the path polyline (planar). The extracted waypoints
    // strip the path start, so the first segment runs from the query start to waypoint 0.
    private float Compute_WorstClearance(const TArray<FVector>& InWaypoints)
    {
        if (InWaypoints.Num() == 0)
        { return -1.0; }

        auto Points = TArray<FVector>();
        Points.Add(FVector(PathStartX, 0.0, _FloorZ));
        for (auto Waypoint : InWaypoints)
        { Points.Add(Waypoint); }

        auto WorstClearance = -1.0;
        for (auto PicketLoc : _PicketLocations)
        {
            auto Closest = -1.0;
            for (auto i = 1; i < Points.Num(); ++i)
            {
                const auto Dist = Dist2D_PointToSegment(PicketLoc, Points[i - 1], Points[i]);
                if (Closest < 0.0 || Dist < Closest) { Closest = Dist; }
            }
            if (WorstClearance < 0.0 || Closest < WorstClearance) { WorstClearance = Closest; }
        }
        return float(WorstClearance);
    }

    private float Dist2D_PointToSegment(FVector InPoint, FVector InA, FVector InB)
    {
        auto P = InPoint; P.Z = 0.0;
        auto A = InA;     A.Z = 0.0;
        auto B = InB;     B.Z = 0.0;

        const auto AB = B - A;
        const auto LenSq = AB.SizeSquared();
        if (LenSq < 0.0001)
        { return float((P - A).Size()); }

        auto T = (P - A).DotProduct(AB) / LenSq;
        T = Math::Clamp(T, 0.0, 1.0);
        const auto ClosestPoint = A + AB * T;
        return float((P - ClosestPoint).Size());
    }

    private void SpawnPicketLine(FCk_Handle& InOwner)
    {
        const auto HalfSpan = float(PicketCount - 1) * PicketSpacingUu * 0.5;
        for (auto i = 0; i < PicketCount; ++i)
        {
            const auto Loc = FVector(0.0, float(i) * PicketSpacingUu - HalfSpan, _FloorZ + 100.0);
            auto Params = FCk_CrowdAgent_Spec(42.0f, 192.0f);
            auto PicketEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
            auto AgentTransform = utils_transform::Add(PicketEntity, FTransform(FRotator::ZeroRotator, Loc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
            auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
            _PicketLocations.Add(Loc);
        }
    }
}

class ACk_AutoTest_Crowd_StationaryLine_PathsRouteAround_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_StationaryLine_PathsRouteAround;
    default _TimeoutSeconds = 15.0f;
}
