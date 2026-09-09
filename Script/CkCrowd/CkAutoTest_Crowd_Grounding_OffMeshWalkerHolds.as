// Language=angelscript
//============================================================================
// CK CROWD - AUTOMATION TEST: AN OFF-MESH WALKER HOLDS INSTEAD OF GLIDING
//============================================================================
//
// This regression test keeps a real walking agent in the production
// Euler/ConstrainToNavmesh path while it is displaced beyond recovery.
//
//----------------------------------------------------------------------------
// THE CONSTRAINT
//----------------------------------------------------------------------------
//
// ConstrainToNavmesh is the SINGLE transform writer for a crowd agent: every
// other stage (steering, push-apart, separation, the euler integrator) only
// STAGES a displacement into FFragment_CrowdAgent_PendingDisplacement, and this
// processor decides what part of it the agent is actually allowed to travel.
//
// It has three outcomes for a displacing agent:
//
//   * start projects onto the mesh  -> FindMoveAlongSurface walks the planar
//     part of the displacement across the surface and the agent gets the
//     surface delta. This is the constraint doing its job.
//   * start does NOT project, but the 4x-radius / +/-Height recovery search
//     finds mesh -> the agent is snapped back. This is the self-heal.
//   * NEITHER projects -> the agent is flagged Get_IsOffNavmesh. In Hold mode,
//     its pending displacement is consumed without queuing a transform offset.
//
// A crowd agent has no gravity or floor collision, so accepting a pending
// displacement from that third branch would carry it through open air at
// constant Z. The fixture pins that no transform movement is admitted once
// the agent is beyond recovery.
//
// The grounding lease (FFragment_CrowdAgent_Grounding, Get_IsOffNavmesh,
// Get_SecondsOffNavmesh) reports the state and supplies the dwell time quoted
// by failure text. Recovery and reporting are deliberately different jobs (see
// Crowd_Grounding_StationaryAgentReGrounds phase D, which pins the recovery
// extent from the other side). The Hold branch defines what the agent is
// allowed to do while it is reported: no pending displacement is applied.
//
//----------------------------------------------------------------------------
// WHAT THIS TEST STAGES, AND WHY IN THIS ORDER
//----------------------------------------------------------------------------
//
// The field shape is "a walking agent leaves the mesh and keeps going". The
// smallest honest manufacture of that is a walking agent that is MOVED off the
// mesh mid-stride, because what matters is not HOW the agent got out there -
// it is that a nonzero production displacement reaches the both-fail branch.
//
//   1. Find the navmesh's +X edge by probing, the way
//      Crowd_PushApart_AgentStaysOnNavmesh does, rather than hardcoding a
//      coordinate. The fixture then survives a change to the test level, and a
//      level that no longer has the shape this test needs says so by name.
//   2. Walk one agent along +X on a real path until it is genuinely cruising
//      (Ready path, Walking state, above a speed floor, clear of its spawn).
//   3. Displace it to EdgeX + 2500uu at the SAME Y and the SAME Z. Horizontal
//      only, so the constant-Z glide the field showed is the thing measured;
//      2500uu is ~15x the 4x-radius recovery extent, so both projections fail
//      on distance and the agent is genuinely beyond recovery - that is the
//      positive control that this run reached the branch under test at all.
//   4. From the FIRST frame Get_IsOffNavmesh reports true, accumulate the
//      agent's PATH LENGTH in XY (not its endpoint distance - an out-and-back
//      glide is still a glide) until it comes to rest or the window closes.
//
// THE CONTRACT: an agent that is off the navmesh beyond recovery must not
// travel. A held agent moves EXACTLY zero, because ConstrainToNavmesh is the
// only thing that would have written its transform. A gliding one moves its
// commanded speed for as long as the pipeline keeps commanding it.
//
// WHY THE LIMIT IS 50uu AND NOT 700uu. The field glide ran for hundreds of uu
// because the agent stayed ON its own XY corridor and nothing noticed. Here the
// displacement is lateral, so BlockDetect's off-path tier (300cm, XY, evaluated
// on the 0.5s block-detection cadence) DOES notice and re-paths; that re-path
// fails from 2500uu off-mesh, steering zeroes the desired velocity, and
// AccelClamp ramps the agent down over ~0.5s at the default 480cm/s^2. So the
// glide this fixture can produce is BOUNDED - roughly one block-detect cadence
// plus one deceleration at the default 240cm/s, on the order of 100-200uu, not
// 700uu. 50uu sits an order of magnitude above the held agent's exact zero and
// still well under the shortest glide the bound allows. It is deliberately not
// set close to the expected glide: this is a floor on "moved at all", not a
// measurement of how far.
//
//----------------------------------------------------------------------------
// THE POSITIVE CONTROL, AND THE ONE WAY A CORRECT FIX COULD TRIP IT
//----------------------------------------------------------------------------
//
// A zero travel proves nothing if no movement reached the constraint. The
// tracked CrowdDiag record therefore latches a high-speed sample inside the
// already-confirmed empty projection box and requires two later samples to
// remain at that observed location. The requested transform is not
// the anchor: a previously staged offset can commit with it. This uses public
// post-Constrain position/speed observations; it does not expose private
// pipeline staging data just for the test.
//
// Z is measured across the same window and folded into the failure text rather
// than asserted separately: a constant Z is the SIGNATURE of this defect (no
// gravity, no floor), not an independent requirement, and asserting it on its
// own would turn a fix that grounds the agent into a second red.
//============================================================================

class UCk_AutoTest_Crowd_Grounding_OffMeshWalkerHolds : UCk_AutoTest_Base
{
    // The walk-up, the nav bake poll and a multi-second hold window do not fit
    // in the base 5s, and a full-suite run spreads these tests over concurrent
    // editors so every settle buys fewer frames per second than it does alone.
    default _TimeoutSeconds = 30.0f;

    // ---- Fixture geometry (all derived, none of it hardcoded to the level) ----

    private const float32 ProbeExtentUu = 5.0f;
    private const float32 ProbeVerticalExtentUu = 300.0f;
    private const float CoarseStepUu = 250.0;
    private const float RefineStepUu = 5.0;
    private const float MaxProbeUu = 20000.0;

    // How far past the discovered +X edge the agent is displaced to. The
    // recovery search is 4x radius horizontally (168uu at these params), so this
    // is ~15x beyond it: both projections fail on horizontal distance alone, and
    // no plausible retune of the recovery extent turns this run vacuous.
    private const float OffMeshMarginUu = 2500.0;

    // The probe that CONFIRMS the displacement target is genuinely off-mesh.
    // Deliberately far larger than the constraint's own extents: if the mesh
    // reaches this point at all, the fixture cannot host the phenomenon.
    private const float32 OffMeshConfirmExtentUu = 500.0f;

    private const float SpawnXFromEdgeUu = -1600.0;
    private const float GoalXFromEdgeUu = -200.0;

    private const float AgentRadius = 42.0f;
    private const float AgentHeight = 192.0f;

    // ---- Thresholds ----

    // THE CONTRACT. A held agent travels exactly 0 - ConstrainToNavmesh is the
    // only writer of its transform. See the header for why this is 50 and not
    // the ~700uu of the field report.
    private const float MaxOffMeshTravelCm = 50.0;

    // Cruise floor. Default _MaxSpeed is 240cm/s; 150 is comfortably clear of
    // the AccelClamp ramp-up without being so close to 240 that a slow frame
    // stalls the precondition.
    private const float MinCruiseSpeedCm = 150.0;

    private const float MinWalkBeforeDisplaceUu = 150.0;
    private const float RecorderAnchorToleranceUu = 0.001;
    private const int32 RequiredPostAnchorStationarySamples = 2;
    private const int32 PostTrackSampleCensusLimit = 8;

    // Matches Crowd_Grounding_StationaryAgentReGrounds' settled threshold.
    private const float SettledSpeedCm = 5.0;

    // Consecutive at-rest polls before the agent is called held. One poll of
    // near-zero speed happens naturally as velocity crosses zero on a reversal.
    private const int32 RestConfirmPolls = 30;

    // The measurement window, in polls rather than seconds: how many processor
    // passes a displacement needs is a property of ordering, and under
    // concurrent lanes a fixed number of seconds buys far fewer of them. Longer
    // than intended only ever gives a glide MORE room to show itself.
    private const int32 HoldWindowPolls = 240;

    private const int32 SettleBudgetPolls = 1200;
    private const int32 OffMeshWaitBudgetPolls = 600;

    // ---- State ----

    private FCk_Handle_CrowdAgent _Agent;
    private FCk_Handle_Transform _AgentTransform;

    private bool _NavProbeReady = false;
    private float _VerifyIntervalSec = 0.0;

    private float _FloorZ = 0.0;
    private float _EdgeX = 0.0;
    private float _OffMeshX = 0.0;

    private FVector _SpawnLocation = FVector::ZeroVector;
    private FVector _GoalLocation = FVector::ZeroVector;

    private float _SpeedAtDisplacement = 0.0;
    private FVector _DisplacedTo = FVector::ZeroVector;
    private int32 _OffMeshWaitPolls = 0;
    private int32 _LastProcessedRecorderSampleIndex = 0;
    private bool _SawPostTeleportMotionAnchor = false;
    private int32 _PostAnchorStationarySamples = 0;
    private float _MotionAnchorTimeSec = -1.0;
    private FVector _MotionAnchorPos = FVector::ZeroVector;
    private int32 _PostTrackSampleCensusCount = 0;
    private FString _PostTrackSampleCensus;
    private float _HighestOffMeshBoxSampleSpeedCm = -1.0;
    private float _HighestOffMeshBoxSampleTimeSec = -1.0;
    private FVector _HighestOffMeshBoxSamplePos = FVector::ZeroVector;

    private FVector _OffMeshEnterPos = FVector::ZeroVector;
    private FVector _LastSampledPos = FVector::ZeroVector;
    private float _OffMeshTravelCm = 0.0;
    private float _OffMeshMinZ = 0.0;
    private float _OffMeshMaxZ = 0.0;
    private float _OffMeshMaxSpeedCm = 0.0;
    private int32 _RestPolls = 0;
    private int32 _HoldPolls = 0;
    private bool _CameToRest = false;

    private bool _GoalFailed = false;
    private FString _GoalFailReason;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        Set_CVarForTest(n"ck.Crowd.SampleHz", "1000");
        Set_CVarForTest(n"ck.Crowd.MaxRecordedSamples", "65536");

        Add_Step(           "confirm the navmesh constraint and the grounding lease are live",
                            n"Step_AssertConstraintLive");
        Add_Step(           "kick the navmesh bake and probe a real path query",
                            n"Step_ProbeNavmesh");
        Add_Step_WaitUntil( "the navmesh answers a real path query",
                            n"Check_NavReady", SettleBudgetPolls);
        Add_Step(           "find the mesh's +X edge and confirm the off-mesh target is off-mesh",
                            n"Step_FindMeshEdgeAndOffMeshTarget");
        Add_Step(           "spawn one agent inland and send it toward the edge",
                            n"Step_SpawnWalker");
        Add_Step_WaitUntil( "the agent is genuinely cruising on a Ready path",
                            n"Check_WalkerCruising", SettleBudgetPolls);
        Add_Step(           "displace the CRUISING agent far past the edge, same Y, same Z",
                            n"Step_DisplaceOffMesh");
        Add_Step_WaitUntil( "the agent reports itself off-navmesh beyond recovery",
                            n"Check_ReportedOffNavmesh", OffMeshWaitBudgetPolls);
        Add_Step(           "latch the position, height and speed the hold is measured from",
                            n"Step_LatchOffMeshBaseline");
        Add_Step_WaitUntil( "the off-mesh agent HOLDS instead of travelling through open air",
                            n"Check_OffMeshWalkerHeld", HoldWindowPolls + 120);
        Add_Step(           "and the run had commanded motion to hold in the first place",
                            n"Step_ReportHold");

        Run_Steps(InHandle);
    }

    // ---- Preconditions ------------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertConstraintLive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // With the constraint off, EnqueueOffset(Displacement) is the FIRST branch
        // rather than the last one, so every agent in the world glides and this
        // test would be reporting a project setting rather than a defect.
        if (utils_crowd_settings::Get_NavmeshConstraintMode() == ECk_CrowdNavmeshConstraintMode::Disabled)
        {
            FinishFailure("the navmesh constraint is DISABLED for this run (_NavmeshConstraintMode = Disabled). Every displacement is passed straight through in that mode, so an off-mesh walker gliding says nothing about the both-projections-fail branch this test exists for - failing here instead, naming the setting.");
            return;
        }

        _VerifyIntervalSec = utils_crowd_settings::Get_GroundingVerifyIntervalSeconds();
        if (_VerifyIntervalSec <= 0.0f)
        {
            FinishFailure(f"the grounding lease is DISABLED for this run (_GroundingVerifyIntervalSeconds = {_VerifyIntervalSec}). Get_IsOffNavmesh is how this test knows it reached the branch under test, and Get_SecondsOffNavmesh is the dwell time its failure text quotes - with the lease off both are dead and a green here would be vacuous.");
            return;
        }

        ck::crowd::Log(f"[OFFMESH-HOLD] constraint enabled, lease at {_VerifyIntervalSec}s");
    }

    UFUNCTION()
    private void Step_ProbeNavmesh(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        // The probe's start/end pair is Crowd_Grounding_StationaryAgentReGrounds'
        // proven one, reversed: a projection-only probe can select different nav
        // data and false-positive, so this travels a real route on the same
        // fixture the rest of the corpus already relies on.
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 100.0), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // AutoTests_CkTests_Level carries the fixture but the bake is lazy, and
        // the edge probe below is a SYNCHRONOUS projection - it needs a live mesh
        // or it reports the origin itself as the edge.
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    // Retried each poll until the surface answers Success: the rebuild kicked in
    // Step_ProbeNavmesh is async, so the first few polls can legitimately read Unbuilt while the
    // bake finishes.
    UFUNCTION()
    private void Check_NavReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        if (IsFinished()) { return; }

        auto Res = OutResult;

        if (_NavProbeReady)
        {
            Res.Set(true);
            return;
        }

        auto ProbeQuery = FCk_NavSurface_PathQuery(FVector(0.0, 0.0, 100.0), FVector(500.0, 0.0, 100.0));
        const auto Result = utils_nav_surface::Try_FindPathSync(ProbeQuery);

        if (Result.Get_Status() == ECk_NavSurface_QueryStatus::Unbuilt) { return; }

        if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"navigation readiness probe returned status {Result.Get_Status()} instead of Success");
            return;
        }

        _NavProbeReady = true;
        Res.Set(true);
    }

    // ---- Fixture: where the mesh actually ends --------------------------------------------------------

    UFUNCTION()
    private void Step_FindMeshEdgeAndOffMeshTarget(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        const auto OriginProjection = Do_ProjectOntoSurface(FVector::ZeroVector, FVector(100.0, 100.0, ProbeVerticalExtentUu));
        if (OriginProjection.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure("the navmesh answered a path query but the origin does not project - the test level's mesh is not where this fixture expects it");
            return;
        }
        _FloorZ = float(OriginProjection.Get_Location().Z);

        if (DoFind_MeshEdgeX(LocalHandle) == false)
        {
            FinishFailure(f"navmesh +X edge not found within {MaxProbeUu}uu of the origin - test level changed?");
            return;
        }

        _OffMeshX = _EdgeX + OffMeshMarginUu;

        // POSITIVE CONTROL on the fixture itself. Everything below measures what
        // an agent does while BOTH projections fail; if the mesh reaches the
        // displacement target, the recovery branch runs instead and a green would
        // mean nothing.
        if (Do_ProjectOntoSurface(FVector(_OffMeshX, 0.0, _FloorZ),
                FVector(OffMeshConfirmExtentUu, OffMeshConfirmExtentUu, OffMeshConfirmExtentUu)).Get_Status() == ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"INCONCLUSIVE FIXTURE: the displacement target X={_OffMeshX} still projects onto the navmesh within {OffMeshConfirmExtentUu}uu, even though the +X edge probed as X={_EdgeX}. An agent put there would take the RECOVERY branch, not the both-projections-fail branch this test is about.");
            return;
        }

        _SpawnLocation = FVector(_EdgeX + SpawnXFromEdgeUu, 0.0, _FloorZ + 100.0);
        _GoalLocation = FVector(_EdgeX + GoalXFromEdgeUu, 0.0, _FloorZ);

        if (Do_ProjectOntoSurface(_SpawnLocation, FVector(100.0, 100.0, ProbeVerticalExtentUu)).Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"INCONCLUSIVE FIXTURE: the walker's spawn {_SpawnLocation} is not on the navmesh (edge X={_EdgeX}) - the run would be measuring an agent that never walked.");
            return;
        }

        if (Do_ProjectOntoSurface(_GoalLocation, FVector(100.0, 100.0, ProbeVerticalExtentUu)).Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"INCONCLUSIVE FIXTURE: the walker's goal {_GoalLocation} is not on the navmesh (edge X={_EdgeX}) - no path, so no cruise, so nothing to displace.");
            return;
        }

        ck::crowd::Log(f"[OFFMESH-HOLD] floorZ={_FloorZ} edgeX={_EdgeX} offMeshX={_OffMeshX} spawn={_SpawnLocation} goal={_GoalLocation}");
    }

    private FCk_NavSurface_ProjectionResult Do_ProjectOntoSurface(FVector InPoint, FVector InSearchHalfExtents) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(InSearchHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query);
    }

    // Coarse sweep then a fine refine, the same shape
    // Crowd_PushApart_AgentStaysOnNavmesh uses - a hardcoded edge silently stops
    // being the edge the first time the test level is re-authored.
    private bool DoFind_MeshEdgeX(FCk_Handle& InSelf)
    {
        const auto ProbeExtents = FVector(ProbeExtentUu, ProbeExtentUu, ProbeVerticalExtentUu);

        float LastGoodX = 0.0f;
        float CoarseFailX = -1.0f;
        for (float X = CoarseStepUu; X <= MaxProbeUu; X += CoarseStepUu)
        {
            if (Do_ProjectOntoSurface(FVector(X, 0.0, _FloorZ), ProbeExtents).Get_Status() != ECk_NavSurface_QueryStatus::Success)
            {
                CoarseFailX = X;
                break;
            }
            LastGoodX = X;
        }

        if (CoarseFailX < 0.0f)
        { return false; }

        for (float X = LastGoodX + RefineStepUu; X < CoarseFailX; X += RefineStepUu)
        {
            if (Do_ProjectOntoSurface(FVector(X, 0.0, _FloorZ), ProbeExtents).Get_Status() != ECk_NavSurface_QueryStatus::Success)
            { break; }
            LastGoodX = X;
        }

        _EdgeX = LastGoodX;
        return true;
    }

    // ---- The walker -----------------------------------------------------------------------------------

    UFUNCTION()
    private void Step_SpawnWalker(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        auto Params = FCk_Fragment_CrowdAgent_ParamsData(AgentRadius, AgentHeight);

        auto AgentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        AgentEntity.Set_DebugName(n"OffMeshWalkerHolds_Walker");

        const auto Rot = (_GoalLocation - _SpawnLocation).Rotation();
        auto AgentTransform = utils_transform::Add(AgentEntity,
            FTransform(Rot, _SpawnLocation, FVector::OneVector), ECk_Replication::DoesNotReplicate);
        _AgentTransform = AgentTransform;
        _Agent = utils_crowd_agent::Add(AgentTransform, Params);

        utils_velocity::Add(AgentEntity,
            FCk_Fragment_Velocity_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_acceleration::Add(AgentEntity,
            FCk_Fragment_Acceleration_ParamsData(ECk_LocalWorld::World, FVector::ZeroVector),
            ECk_Replication::DoesNotReplicate);
        utils_euler_integrator::Request_Start(AgentEntity);

        // Bound for DIAGNOSTICS only. A goal failure after the displacement is
        // the EXPECTED outcome (the re-path cannot plan from 2500uu off-mesh)
        // what this test judges is what the agent did while that was resolving,
        // so the reason is recorded and folded into whatever verdict follows.
        utils_crowd_agent::BindTo_OnGoalFailed(_Agent,
            FCk_Delegate_CrowdAgent_OnGoalFailed(this, n"OnGoalFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_crowd_agent::Request_MoveTo(_Agent, FCk_Request_CrowdAgent_MoveTo(_GoalLocation));
    }

    UFUNCTION()
    private void OnGoalFailed(FCk_Handle_CrowdAgent InAgent, FCk_CrowdAgent_GoalFailedInfo InInfo)
    {
        if (IsFinished()) { return; }
        _GoalFailed = true;
        _GoalFailReason = f"{InInfo.Get_Reason()} / nav={InInfo.Get_NavFailReason()}";
    }

    UFUNCTION()
    private void Check_WalkerCruising(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (DoValidate_Agent() == false) { return; }

        // The displacement is only meaningful against an agent that is actually
        // being driven: an idle agent stages zero displacement, the both-fail
        // branch has nothing to pass through, and a zero travel would prove
        // nothing at all.
        if (utils_nav::Get_PathStatus(_Agent) != ECk_Nav_PathStatus::Ready) { return; }
        if (utils_crowd_agent::Get_MovementState(_Agent) != ECk_CrowdAgent_MovementState::Walking) { return; }

        const auto Pos = DoGet_Position();
        if (DoGet_Dist2D(Pos, _SpawnLocation) < MinWalkBeforeDisplaceUu) { return; }

        Res.Set(DoGet_Speed() >= MinCruiseSpeedCm);
    }

    // ---- The displacement -----------------------------------------------------------------------------

    UFUNCTION()
    private void Step_DisplaceOffMesh(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _SpeedAtDisplacement = DoGet_Speed();

        const auto Current = utils_transform::Get_EntityCurrentTransform(_AgentTransform);
        const auto From = Current.GetLocation();

        // Y and Z are PRESERVED. A purely horizontal move is what makes the
        // constant-Z glide legible: any vertical component here would be
        // indistinguishable from the constraint failing to correct height.
        _DisplacedTo = FVector(float64(_OffMeshX), From.Y, From.Z);

        // Start a new, high-rate diagnostic episode immediately before the
        // teleport. Its public post-Constrain samples supply the positive
        // control without exposing private pending-displacement state.
        _LastProcessedRecorderSampleIndex = 0;
        _SawPostTeleportMotionAnchor = false;
        _PostAnchorStationarySamples = 0;
        _MotionAnchorTimeSec = -1.0;
        _MotionAnchorPos = FVector::ZeroVector;
        _PostTrackSampleCensusCount = 0;
        _PostTrackSampleCensus = "";
        _HighestOffMeshBoxSampleSpeedCm = -1.0;
        _HighestOffMeshBoxSampleTimeSec = -1.0;
        _HighestOffMeshBoxSamplePos = FVector::ZeroVector;
        utils_crowd_agent_diag::Track(_Agent, From, _GoalLocation);

        // Deliberately NOT preceded by Request_Stop: the move must remain live
        // long enough for its production Euler displacement to reach the
        // constraint on the first off-mesh frame.
        utils_transform::Request_SetTransform(_AgentTransform,
            FCk_Request_Transform_SetTransform(
                FTransform(Current.GetRotation(), _DisplacedTo, Current.GetScale3D())));

        ck::crowd::Log(f"[OFFMESH-HOLD] displaced cruising agent from {From} to {_DisplacedTo} at {_SpeedAtDisplacement}cm/s (edgeX={_EdgeX})");
    }

    UFUNCTION()
    private void Check_ReportedOffNavmesh(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (DoValidate_Agent() == false) { return; }

        if (utils_crowd_agent::Get_IsOffNavmesh(_Agent))
        {
            Res.Set(true);
            return;
        }

        // A DISPLACING agent runs the constraint every frame, so this normally
        // flips within a frame or two; the lease interval only bounds the IDLE
        // path. The budget is stated against the interval anyway so the failure
        // text can say what it was waiting on rather than "condition false".
        _OffMeshWaitPolls += 1;
        if (_OffMeshWaitPolls >= OffMeshWaitBudgetPolls)
        {
            const auto Pos = DoGet_Position();
            FinishFailure(f"INCONCLUSIVE: {OffMeshWaitBudgetPolls} polls (many multiples of the {_VerifyIntervalSec}s grounding lease) after being displaced to {_DisplacedTo}, the agent at {Pos} still does not report Get_IsOffNavmesh. Either the mesh reaches further than the edge probe found (edgeX={_EdgeX}) or the reporting half of the lease is dead - either way this run never reached the both-projections-fail branch, so it can neither confirm nor refute the glide.");
        }
    }

    UFUNCTION()
    private void Step_LatchOffMeshBaseline(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Pos = DoGet_Position();

        _OffMeshEnterPos = Pos;
        _LastSampledPos = Pos;
        _OffMeshTravelCm = 0.0;
        _OffMeshMinZ = float(Pos.Z);
        _OffMeshMaxZ = float(Pos.Z);
        _OffMeshMaxSpeedCm = DoGet_Speed();
        _RestPolls = 0;
        _HoldPolls = 0;
        _CameToRest = false;
    }

    // ---- THE CONTRACT ---------------------------------------------------------------------------------

    UFUNCTION()
    private void Check_OffMeshWalkerHeld(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (DoValidate_Agent() == false) { return; }

        if (DoObserve_PostTeleportHold() == false) { return; }

        const auto Pos = DoGet_Position();
        const auto Speed = DoGet_Speed();

        // PATH LENGTH, not endpoint distance: the desired velocity after the
        // displacement points back at a corridor the agent no longer stands on,
        // so a glide out and part-way back would net out to a small endpoint
        // delta while having travelled the whole way.
        _OffMeshTravelCm += DoGet_Dist2D(Pos, _LastSampledPos);
        _LastSampledPos = Pos;

        _OffMeshMinZ = Math::Min(_OffMeshMinZ, float(Pos.Z));
        _OffMeshMaxZ = Math::Max(_OffMeshMaxZ, float(Pos.Z));
        _OffMeshMaxSpeedCm = Math::Max(_OffMeshMaxSpeedCm, Speed);

        if (_OffMeshTravelCm > MaxOffMeshTravelCm)
        {
            DoFail_Glide(Pos, "while still reporting itself off the navmesh");
            return;
        }

        if (utils_crowd_agent::Get_IsOffNavmesh(_Agent) == false)
        {
            // Getting back onto the mesh from here means covering the whole
            // OffMeshMarginUu, so this cannot happen without travel - but if it
            // somehow does, say so rather than accepting it as a hold.
            DoFail_Glide(Pos, f"and then re-grounded, which from {OffMeshMarginUu}uu past the edge is only reachable by travelling");
            return;
        }

        if (Speed <= SettledSpeedCm) { _RestPolls += 1; }
        else { _RestPolls = 0; }

        if (_RestPolls >= RestConfirmPolls)
        {
            _CameToRest = true;
            Res.Set(true);
            return;
        }

        // The window closing with the travel still under the limit still has to
        // clear the recorder-backed positive control in Step_ReportHold.
        _HoldPolls += 1;
        if (_HoldPolls >= HoldWindowPolls)
        { Res.Set(true); }
    }

    private void DoFail_Glide(FVector InEndPos, const FString& InWhat)
    {
        const auto ZSpreadCm = _OffMeshMaxZ - _OffMeshMinZ;
        const auto DwellSec = utils_crowd_agent::Get_SecondsOffNavmesh(_Agent);
        const auto EndpointCm = DoGet_Dist2D(InEndPos, _OffMeshEnterPos);

        FinishFailure(f"GLIDE: off-mesh agent travelled {_OffMeshTravelCm}uu at constant Z ({_OffMeshMinZ}) - the constraint passed displacement through instead of holding. It went off-mesh at {_OffMeshEnterPos} and reached {InEndPos} {InWhat} (limit {MaxOffMeshTravelCm}uu, endpoint delta {EndpointCm}uu, Z spread over the whole window {ZSpreadCm}uu, mesh edge X={_EdgeX}, off-navmesh for {DwellSec}s, peak speed while off-mesh {_OffMeshMaxSpeedCm}cm/s, speed when displaced {_SpeedAtDisplacement}cm/s, goalFailed={_GoalFailed} [{_GoalFailReason}]). A crowd agent has no gravity and no floor collision, so a displacement that survives the both-projections-fail branch of FProcessor_CrowdAgent_ConstrainToNavmesh carries the body through open air at whatever height it left the mesh at - that flat Z IS the signature. The agent that is beyond the recovery extent must be HELD, not merely reported.");
    }

    private bool DoObserve_PostTeleportHold()
    {
        const auto Recorder = utils_crowd_agent_diag::Get_RecorderData(_Agent);
        const auto Samples = Recorder.Get_Samples();

        for (int32 Index = _LastProcessedRecorderSampleIndex; Index < Samples.Num(); ++Index)
        {
            const auto Sample = Samples[Index];
            const auto SamplePos = Sample.Get_Pos();
            const auto SampleSpeed = Sample.Get_Speed();
            const auto IsInsideConfirmedOffMeshBox = DoIs_InsideConfirmedOffMeshBox(SamplePos);

            if (_PostTrackSampleCensusCount < PostTrackSampleCensusLimit)
            {
                _PostTrackSampleCensus += f" [t={Sample.Get_T()} pos={SamplePos} speed={SampleSpeed}]";
                _PostTrackSampleCensusCount += 1;
            }

            if (IsInsideConfirmedOffMeshBox && SampleSpeed > _HighestOffMeshBoxSampleSpeedCm)
            {
                _HighestOffMeshBoxSampleSpeedCm = SampleSpeed;
                _HighestOffMeshBoxSampleTimeSec = Sample.Get_T();
                _HighestOffMeshBoxSamplePos = SamplePos;
            }

            if (_SawPostTeleportMotionAnchor == false)
            {
                if (IsInsideConfirmedOffMeshBox == false) { continue; }
                if (SampleSpeed < MinCruiseSpeedCm) { continue; }

                _SawPostTeleportMotionAnchor = true;
                _MotionAnchorTimeSec = Sample.Get_T();
                _MotionAnchorPos = SamplePos;
                continue;
            }

            const auto DriftFromAnchor = DoGet_Dist2D(SamplePos, _MotionAnchorPos);
            if (DriftFromAnchor > RecorderAnchorToleranceUu)
            {
                FinishFailure(f"GLIDE: the post-teleport motion anchor at t={_MotionAnchorTimeSec}s, pos={_MotionAnchorPos} was followed by a position {SamplePos} at t={Sample.Get_T()}s (speed {SampleSpeed}cm/s, XY drift {DriftFromAnchor}uu, tolerance {RecorderAnchorToleranceUu}uu). The constraint accepted a staged off-mesh displacement instead of holding it.");
                _LastProcessedRecorderSampleIndex = Samples.Num();
                return false;
            }

            _PostAnchorStationarySamples += 1;
        }

        _LastProcessedRecorderSampleIndex = Samples.Num();
        return true;
    }

    UFUNCTION()
    private void Step_ReportHold(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto ZSpreadCm = _OffMeshMaxZ - _OffMeshMinZ;
        const auto DwellSec = utils_crowd_agent::Get_SecondsOffNavmesh(_Agent);

        Assert_True(_SawPostTeleportMotionAnchor,
            f"INCONCLUSIVE: no post-teleport CrowdDiag sample inside the confirmed empty box centered at X={_OffMeshX}, Y=0, Z={_FloorZ} with half-extents {OffMeshConfirmExtentUu}uu had speed >= {MinCruiseSpeedCm}cm/s. With no observed production motion at the displaced location, a travel of {_OffMeshTravelCm}uu cannot prove the hold. First {_PostTrackSampleCensusCount} post-Track samples:{_PostTrackSampleCensus}; highest in-box sample: t={_HighestOffMeshBoxSampleTimeSec}s pos={_HighestOffMeshBoxSamplePos} speed={_HighestOffMeshBoxSampleSpeedCm}cm/s.");

        Assert_True(_PostAnchorStationarySamples >= RequiredPostAnchorStationarySamples,
            f"INCONCLUSIVE: the post-teleport motion anchor at t={_MotionAnchorTimeSec}s had only {_PostAnchorStationarySamples} later high-rate recorder observations held at {_MotionAnchorPos} (need {RequiredPostAnchorStationarySamples}, tolerance {RecorderAnchorToleranceUu}uu). The run did not retain enough ordered post-anchor evidence to prove the hold.");

        Assert_True(_OffMeshTravelCm <= MaxOffMeshTravelCm,
            f"the off-mesh agent travelled {_OffMeshTravelCm}uu (limit {MaxOffMeshTravelCm}uu)");

        ck::crowd::Log(f"[OFFMESH-HOLD] held: travel={_OffMeshTravelCm}uu zSpread={ZSpreadCm}uu peakSpeed={_OffMeshMaxSpeedCm}cm/s cameToRest={_CameToRest} dwell={DwellSec}s");
    }

    // ---- Helpers --------------------------------------------------------------------------------------

    private bool DoIs_InsideConfirmedOffMeshBox(FVector InPos) const
    {
        return Math::Abs(float(InPos.X - _OffMeshX)) <= OffMeshConfirmExtentUu &&
            Math::Abs(float(InPos.Y)) <= OffMeshConfirmExtentUu &&
            Math::Abs(float(InPos.Z - _FloorZ)) <= OffMeshConfirmExtentUu;
    }

    private bool DoValidate_Agent()
    {
        if (ck::Is_NOT_Valid(_Agent))
        {
            FinishFailure("the walker went invalid mid-run - possible early destroy / lifetime issue");
            return false;
        }
        return true;
    }

    private float DoGet_Speed()
    {
        FCk_Handle Generic = _Agent;
        return float(utils_velocity::Get_CurrentVelocity(
            utils_velocity::DoCastChecked(Generic)).Size());
    }

    private FVector DoGet_Position()
    {
        return utils_transform::Get_EntityCurrentLocation(_AgentTransform);
    }

    // Planar on purpose: this test's whole claim is about travel through open
    // air at a FIXED height, so folding Z into the distance would let a
    // (hypothetical) vertical correction read as horizontal travel.
    private float DoGet_Dist2D(FVector InA, FVector InB)
    {
        return float(FVector(InA.X - InB.X, InA.Y - InB.Y, 0.0).Size());
    }
}

class ACk_AutoTest_Crowd_Grounding_OffMeshWalkerHolds_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Grounding_OffMeshWalkerHolds;
    default _TimeoutSeconds = 30.0f;

    // The displacement puts the agent 2500uu off the mesh ON PURPOSE, so the
    // re-path BlockDetect fires afterwards cannot project its start and CkNav
    // warns about it. The automation framework escalates any Warning to a test
    // failure, so the test's own deliberate output would fail it before its own
    // assertions ever ran. Registered as plain substrings (AddExpectedErrorPlain
    // - Contains, suppress-all); a pattern that never fires is not reported as
    // missing, so the hedges below cost nothing even at their current
    // verbosity.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // CkNav_Algorithm.cpp - "FindPathSync: [Start] projection FAILED. ..."
        // (and the [End] form, if the goal is ever the one that misses).
        Out.Add("projection FAILED");
        // FProcessor_CrowdAgent_OnPathResolved, Failed branch:
        //   "CrowdAgent [..] PathPending -> Idle (path failed: ..)"
        Out.Add("path failed");
        // The bounded no-progress ladder, currently Log-level. A zero-cost hedge
        // against the day it goes back to Warning.
        Out.Add("made no progress toward");
        return Out;
    }
}
