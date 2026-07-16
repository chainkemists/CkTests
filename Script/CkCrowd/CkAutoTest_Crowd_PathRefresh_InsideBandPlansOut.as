// Language=angelscript
//============================================================================
// CK CROWD — AUTOMATION TEST: AGENT INSIDE THE COST BAND PLANS OUT AND AROUND
//
// The inside-band escape (FProcessor_CrowdAgent_PathRefresh::Get_EscapedQueryStart):
// the stationary-markup toll is paid per distance crossed, so for an agent
// ALREADY INSIDE the band, finishing the crossing is cheaper than backing out
// plus detouring — a plain plan from its feet picks "through". Every re-path
// site therefore plans from just outside the band when the agent is inside it
// and its goal is not.
//
// Shape: a picket line paints its discs; we wait until a PROBE path from the
// test entity detours (proving the discs are confirmed on the rebuilt mesh —
// no timing guess), then spawn a walker AT THE SEAM between two pickets
// (inside both discs) and MoveTo across. With the tier enabled, the walker's
// installed path must exit the band and clear every picket; with it disabled
// (red), the fresh plan goes straight through. Deterministic: fresh MoveTo
// against pre-confirmed discs — no refresh timing involved.
//============================================================================

class UCk_AutoTest_Crowd_PathRefresh_InsideBandPlansOut : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private const float ProbeStartX = -500.0;
    private const float GoalX = 500.0;
    private const int32 PicketCount = 5;
    private const float PicketSpacingUu = 100.0;
    // The walker spawns at the seam between pickets 0 and 1 (y = -150): inside both discs at
    // the 2x extent multiplier (radius 84 > 50uu seam distance).
    private const float WalkerSpawnY = -150.0;
    private const float MinClearanceUu = 50.0;
    // Stage-2 discriminator, measured over the WHOLE plan polyline including its start point:
    // with the escape, the plan starts at the pushed-out point (>=112uu from every picket
    // centre — 84uu disc + 42uu agent radius + margin, and detour segments stay ~112+); without
    // it (red), the plan starts at the walker's seam position ~50uu from the nearest picket.
    // 90 splits the two with margin on both sides.
    private const float InsideBandMinClearanceUu = 90.0;
    private const int32 MaxAttempts = 20;

    private TArray<FVector> _PicketLocations;
    private FCk_Handle _WalkerEntity;
    private float _FloorZ = 0.0;
    private bool _MeshFound = false;
    private bool _ProbeDetoured = false;
    private int32 _Attempts = 0;
    private float _LastWorstClearance = -1.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(ProbeStartX, 0.0, 100.0), FVector::OneVector),
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
            FVector OriginOnMesh;
            if (utils_nav::Try_ProjectOntoNavmesh(SelfHandle, FVector::ZeroVector, 100.0f, OriginOnMesh, 300.0f) == false)
            { return; }   // bake not done yet

            _MeshFound = true;
            _FloorZ = float(OriginOnMesh.Z);
            SpawnPicketLine(SelfHandle);
            return;
        }

        _Attempts += 1;
        if (_Attempts > MaxAttempts)
        {
            const auto Stage = _ProbeDetoured ? "walker's fresh plan never exited the band" : "probe path never detoured (discs never confirmed?)";
            FinishFailure(f"{Stage} after {MaxAttempts} polls — worst clearance {_LastWorstClearance}uu (need {MinClearanceUu}uu). Inside-band escape is not planning out.");
            return;
        }

        // Stage 1: prove the discs are live on the rebuilt mesh — a probe path from the test
        // entity (well outside the band) must detour. Only then does the walker scenario start,
        // so the walker's fresh plan is guaranteed to run against confirmed discs.
        if (_ProbeDetoured == false)
        {
            if (utils_nav::Get_PathStatus(SelfHandle) == ECk_Nav_PathStatus::Ready)
            {
                const auto Result = utils_nav::Get_PathResult(SelfHandle);
                const auto Clearance = Compute_WorstClearance(Result.Get_Waypoints(), FVector(ProbeStartX, 0.0, _FloorZ));
                if (Clearance >= MinClearanceUu)
                {
                    _ProbeDetoured = true;
                    SpawnWalkerInsideBand(SelfHandle);
                    return;
                }
            }
            utils_nav::Request_FindPath(SelfHandle,
                FCk_Request_Nav_FindPath(FVector(GoalX, 0.0, _FloorZ)));
            return;
        }

        // Stage 2: the walker planned from INSIDE the band — the PLAN itself (its whole
        // polyline, start point included) must sit outside the band. The walker's body stays at
        // the seam; only the plan is judged, so it is deliberately NOT prepended.
        if (utils_nav::Get_PathStatus(_WalkerEntity) == ECk_Nav_PathStatus::Ready)
        {
            const auto Result = utils_nav::Get_PathResult(_WalkerEntity);
            const auto Waypoints = Result.Get_Waypoints();
            if (Waypoints.Num() >= 1)
            {
                const auto WorstClearance = Compute_WorstClearance(Waypoints, Waypoints[0]);
                _LastWorstClearance = WorstClearance;

                if (WorstClearance >= InsideBandMinClearanceUu)
                {
                    FinishSuccess();
                }
            }
        }
    }

    private float Compute_WorstClearance(const TArray<FVector>& InWaypoints, FVector InStart)
    {
        if (InWaypoints.Num() == 0)
        { return -1.0; }

        auto Points = TArray<FVector>();
        Points.Add(InStart);
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
            auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
            auto Agent = utils_crowd_agent::Add(InOwner, Params);
            FCk_Handle Generic = Agent;
            utils_transform::Add(Generic, FTransform(FRotator::ZeroRotator, Loc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
            _PicketLocations.Add(Loc);
        }
    }

    private void SpawnWalkerInsideBand(FCk_Handle& InOwner)
    {
        const auto Loc = FVector(0.0, WalkerSpawnY, _FloorZ + 100.0);
        auto Params = FCk_Fragment_CrowdAgent_ParamsData(42.0f, 192.0f);
        auto Agent = utils_crowd_agent::Add(InOwner, Params);
        _WalkerEntity = Agent;
        utils_transform::Add(_WalkerEntity, FTransform(FRotator::ZeroRotator, Loc, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        utils_crowd_agent::Request_MoveTo(Agent, FCk_Request_CrowdAgent_MoveTo(FVector(GoalX, 0.0, _FloorZ)));
    }
}

class ACk_AutoTest_Crowd_PathRefresh_InsideBandPlansOut_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_PathRefresh_InsideBandPlansOut;
    default _TimeoutSeconds = 15.0f;
}
