// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: MID-WALK PATH REFRESHES AROUND A FORMING CROWD
//
// The path-refresh tier (FProcessor_CrowdAgent_PathRefresh): stationary-markup
// cost discs only bend paths computed AFTER they paint. An agent already
// walking on a path computed BEFORE a crowd formed must be re-pathed — not
// left pressing into the crowd on its frozen straight polyline.
//
// Shape: a walker is issued a MoveTo across x=0 in the SAME frame a picket
// line of 5 idle agents spawns there — the pickets' discs cannot exist yet
// (stationary delay), so the walker's first path is guaranteed straight
// through the line. Once the discs paint + settle, PathRefresh must notice the
// walker's remaining path crosses fresh markup and re-path it; the walker's
// INSTALLED path (utils_nav::Get_PathResult on its own entity) then detours.
// Red-green via ECk_CrowdPathRefreshMode.
//============================================================================

class UCk_AutoTest_Crowd_PathRefresh_MidWalkDetours : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private const float WalkStartX = -500.0;
    private const float WalkEndX = 500.0;
    private const int32 PicketCount = 5;
    private const float PicketSpacingUu = 100.0;
    // Same discriminator as CkAutoTest_Crowd_StationaryLine_PathsRouteAround: straight-through
    // clearance is ~0, a detour around the line's end skirts the outermost disc (~55uu+).
    private const float MinClearanceUu = 50.0;
    private const int32 MaxAttempts = 20;
    private const float32 WalkerMaxSpeed = 120.0f;

    private TArray<FVector> _PicketLocations;
    private FCk_Handle _WalkerEntity;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _FirstPathChecked = false;
    private FString _FirstPathDump;
    private int32 _Attempts = 0;
    private float _LastWorstClearance = -1.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(WalkStartX, 0.0, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.5));
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
            // Gate on the WHOLE corridor being baked, not just the origin: the walker's FindPath
            // must resolve immediately (CkNav defers a request whose start tile isn't baked yet,
            // and a deferred first path would resolve AFTER the discs paint and detour on its
            // own — no stale path, nothing for PathRefresh to prove).
            FVector Projected;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, Projected, 300.0f) == false)
            { return; }   // bake not done yet
            _FloorZ = float(Projected.Z);
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector(WalkStartX, 0.0, _FloorZ), 100.0f, Projected, 300.0f) == false)
            { return; }
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector(WalkEndX, 0.0, _FloorZ), 100.0f, Projected, 300.0f) == false)
            { return; }

            _MeshFound = true;

            // Same frame: pickets spawn AND the walker's MoveTo is issued. The pickets' discs
            // need 1.5s of idle before they paint, so the walker's FIRST path is computed
            // against an empty mesh — straight through the line. Only PathRefresh can fix it.
            SpawnPicketLine(SelfHandle);
            SpawnWalker(SelfHandle);
            return;
        }

        if (utils_nav::Get_PathStatus(_WalkerEntity) == ECk_Nav_PathStatus::Ready)
        {
            const auto Result = utils_nav::Get_PathResult(_WalkerEntity);
            const auto WorstClearance = Compute_WorstClearance(Result.Get_Waypoints());
            _LastWorstClearance = WorstClearance;

            // Precondition, not a wait: the FIRST observed path must be the stale straight one.
            // If it already detours, the discs painted before the walker planned (the deferral
            // race above was lost) and the scenario proves nothing about PathRefresh.
            if (_FirstPathChecked == false)
            {
                _FirstPathChecked = true;
                _FirstPathDump = Dump_Polyline(Result.Get_Waypoints());
                if (WorstClearance >= MinClearanceUu)
                {
                    FinishFailure(f"INCONCLUSIVE SCENARIO: the walker's FIRST path already detours (clearance {WorstClearance}uu) — the discs painted before the walker planned, so the test never created a stale path for PathRefresh to fix. Check the corridor-bake gate. wps={_FirstPathDump}");
                    return;
                }
            }
            else if (WorstClearance >= MinClearanceUu)
            {
                FinishSuccess();
                return;
            }
        }

        _Attempts += 1;
        if (_Attempts > MaxAttempts)
        {
            FinishFailure(f"walker's installed path never detoured around the crowd that formed mid-walk after {MaxAttempts} polls — worst clearance {_LastWorstClearance}uu (need {MinClearanceUu}uu). PathRefresh is not re-pathing stale paths.");
        }
    }

    // Min distance from any picket agent to the walker's path polyline (planar). The extracted
    // waypoints strip the path start; prepend the walker's CURRENT location — after a mid-walk
    // re-path the first segment runs from wherever the walker was when it re-planned.
    private float Compute_WorstClearance(const TArray<FVector>& InWaypoints)
    {
        if (InWaypoints.Num() == 0)
        { return -1.0; }

        auto Points = TArray<FVector>();
        Points.Add(utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(_WalkerEntity)));
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

    private FString Dump_Polyline(const TArray<FVector>& InWaypoints)
    {
        auto Dump = FString("");
        for (auto Waypoint : InWaypoints)
        { Dump += f"({Math::RoundToInt(float32(Waypoint.X))},{Math::RoundToInt(float32(Waypoint.Y))}) "; }
        return Dump;
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
            auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
            // ONE ENTITY PER PICKET — utils_crowd_agent::Add composes onto the handle it is given
            // and allows one agent per entity, so sharing the owner collapsed the crowd that is
            // supposed to form mid-walk into a single agent.
            auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
            auto AgentTransform = utils_transform::Add(AgentEntity, FTransform(FRotator::ZeroRotator, Loc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
            auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
            _PicketLocations.Add(Loc);
        }
    }

    private void SpawnWalker(FCk_Handle& InOwner)
    {
        const auto Loc = FVector(WalkStartX, 0.0, _FloorZ + 100.0);
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        Params.Set_MaxSpeed(WalkerMaxSpeed);
        // FailMove is what makes the Disabled run genuinely red: with the default HoldAndRetry,
        // a walker that reaches the line and stalls is eventually block-detected, and
        // BlockedRecheck's resume FULLY RE-PATHS — producing the detour through the OTHER
        // mechanism (this happened; see [CQ-D11] in the checkout-queue campaign log). FailMove
        // ends the move instead, so the installed path can only change via PathRefresh.
        Params.Set_BlockedPolicy(ECk_CrowdAgent_BlockedPolicy::FailMove);
        // The walker needs its OWN entity too — otherwise it lands on the same entity as the
        // pickets and becomes one of them rather than a separate agent walking past them.
        _WalkerEntity = utils_entity_lifetime::Request_CreateEntity(InOwner);
        auto AgentTransform = utils_transform::Add(_WalkerEntity, FTransform(FRotator::ZeroRotator, Loc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        auto Agent = utils_crowd_agent::Add(AgentTransform, Params);
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(FVector(WalkEndX, 0.0, _FloorZ)));
    }
}

class ACk_AutoTest_Crowd_PathRefresh_MidWalkDetours_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_PathRefresh_MidWalkDetours;
    default _TimeoutSeconds = 15.0f;
}
