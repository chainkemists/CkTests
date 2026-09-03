// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: HOW LONG A PAINTED AREA TAKES TO REACH THE TILES
//============================================================================
//
// A measurement, not a contract. Runtime navmesh generation is Dynamic for this project, so a
// nav-area paint does not wait for a full build - registering the markup dirties the tiles it
// covers and Recast repairs them over the following frames. What that repair COSTS, in frames and
// in seconds, is what every fixture that paints a carve and then settles on it is budgeting for.
// No rebuild is kicked after a paint on purpose: kicking one would measure
// UNavigationSystemV1::Build(), not the dirty-area repair.
//
// TWO AREAS, BECAUSE THE LIVE FLAG AND THE CONSEQUENCE CANNOT BE READ OFF THE SAME PAINT.
// Get_IsMarkupLive resolves through Get_IsAreaLiveAt, which finds the nearest polygon to the
// markup's centre and compares its area id against the painted area's. The well-known impassable
// area removes the polygons under it outright - they STOP EXISTING - so an
// impassable box has no polygon left to carry its id and its live flag can never read true. The
// two numbers are therefore taken off two paints per round:
//
//   Nav.Area.Restricted - sampleable, so Get_IsMarkupLive IS the named condition, and the frames
//     between the request and the flag are the markup-live latency.
//   Nav.Area.Impassable - not sampleable, so the named condition is the CONSEQUENCE: a projection
//     probe at the box centre, with search half-extents deliberately tighter than the hole, stops
//     succeeding. The live flag is read at that moment too and reported alongside.
//
// WHY THE CONSEQUENCE IS NOT Get_IsReachable: the facade projects a reachability query's endpoints
// with the project-wide extent (500uu half-extent), which is wider than the hole a 300uu box
// leaves, so the end point snaps to a polygon just outside the carve and the verdict stays
// Reachable. Both verdicts are logged to record that; the timed condition is the tight probe.
//
// The assertions are sanity bounds only: at least one round of each kind must have been observed
// and the surface revision must have moved. Every markup is registered for cleanup as it is
// painted, so it is unpainted on every exit path including the harness's own timeout, and each
// round waits for the navmesh to come back before the next one starts.
//
//============================================================================

class UCk_AutoTest_NavSurface_RecastBudgets_MarkupLiveLatency : UCk_AutoTest_Base
{
    // Five rounds of three timed repairs over runtime paints. Deliberately slack - a measurement
    // that times out measures nothing.
    default _TimeoutSeconds = 240.0f;

    private const int32 RoundCount = 5;

    // 300 x 300 x 200uu, quoted as half-extents. Comfortably larger than a Recast tile cell, so the
    // polygon under the centre is fully inside the box rather than straddling its edge.
    private const FVector BoxHalfExtents = FVector(150.0, 150.0, 100.0);

    // Round 0 lands at (400, 0, floorTop); the rest are spread around the same ring so no two
    // rounds repair the same tiles back to back.
    private const float RingRadiusUu = 400.0;

    // Tighter than the hole a 300uu box leaves after agent-radius erosion, so a probe inside the
    // carve cannot snap to a polygon outside it. The vertical half-extent stays well under the box
    // height, so the walkable surface Recast may bake on TOP of nothing here is never picked up.
    private const FVector ProbeHalfExtents = FVector(60.0, 60.0, 80.0);

    // Per-stage ceiling. A dirty-area repair is a handful of frames; this is that with room over,
    // and it is what turns a wedged repair into a reported miss instead of a hung test.
    private const int32 StageFrameCap = 400;

    private const int32 Stage_PaintSampleable = 0;
    private const int32 Stage_AwaitLive       = 1;
    private const int32 Stage_DropSampleable  = 2;
    private const int32 Stage_PaintImpassable = 3;
    private const int32 Stage_AwaitHole       = 4;
    private const int32 Stage_DropImpassable  = 5;
    private const int32 Stage_AwaitRestore    = 6;

    private FVector _FloorOrigin = FVector::ZeroVector;
    private FVector _FloorExtent = FVector::ZeroVector;
    private FVector _RimOrigin = FVector::ZeroVector;
    private FVector _RimExtent = FVector::ZeroVector;
    private float _FloorTopZ = 0.0;

    // Wall-independent clock. The sequencer keeps its own elapsed seconds but does not expose them,
    // so this test runs its own per-frame timer for the seconds half of every number below.
    private FCk_Handle_Timer _ClockTimer;
    private float _ClockSeconds = 0.0;

    private FCk_Handle_NavSurfaceMarkup _Markup;
    private FVector _SpotCentre = FVector::ZeroVector;

    private int32 _Round = 0;
    private int32 _Stage = 0;
    private int64 _LastSampledFrame = -1;
    private int64 _StageStartFrame = 0;
    private float _StageStartSeconds = 0.0;
    private int32 _StagePolls = 0;
    private int64 _RevisionBefore = 0;
    private ECk_NavSurface_Reachability _ReachBefore = ECk_NavSurface_Reachability::Unknown_ProviderNotReady;

    private int32 _LiveCount = 0;
    private int32 _LiveFrameMin = 0;
    private int32 _LiveFrameMax = 0;
    private int32 _LiveFrameSum = 0;
    private float _LiveSecondsSum = 0.0;

    private int32 _HoleCount = 0;
    private int32 _HoleFrameMin = 0;
    private int32 _HoleFrameMax = 0;
    private int32 _HoleFrameSum = 0;
    private float _HoleSecondsSum = 0.0;

    private int32 _MissCount = 0;
    private int64 _RevisionAtStart = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready", n"Check_ProviderIsReady", 900);
        Add_Step(          "find the level floor and its rectangle",    n"Step_FindFloor");
        Add_Step(          "ask the provider to build its surface",     n"Step_KickRebuild");
        Add_Step_WaitUntil("the first paint spot projects",             n"Check_FirstSpotProjects", 900);
        Add_Step_WaitUntil("every paint round has been observed",       n"Check_RoundsComplete", 9000);
        Add_Step(          "report what a paint cost to reach the tiles", n"Step_Report");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_FindFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto LocalHandle = InHandle;

        auto Floor = assets::StaticMeshActor_1().Get();

        if (!System::IsValid(Floor))
        {
            FinishFailure("staging failed: the level floor StaticMeshActor_1 could not be reached - the fixture, not the provider, is broken");
            return;
        }

        Floor.GetActorBounds(false, _FloorOrigin, _FloorExtent);

        auto Volume = assets::NavMeshBoundsVolume_1().Get();

        if (!System::IsValid(Volume))
        {
            FinishFailure("staging failed: the level nav bounds volume NavMeshBoundsVolume_1 could not be reached - the fixture, not the provider, is broken");
            return;
        }

        auto VolumeOrigin = FVector::ZeroVector;
        auto VolumeExtent = FVector::ZeroVector;
        Volume.GetActorBounds(false, VolumeOrigin, VolumeExtent);

        const auto FloorMin = _FloorOrigin - _FloorExtent;
        const auto FloorMax = _FloorOrigin + _FloorExtent;
        const auto VolumeMin = VolumeOrigin - VolumeExtent;
        const auto VolumeMax = VolumeOrigin + VolumeExtent;

        const auto RimMin = FVector(Math::Max(FloorMin.X, VolumeMin.X), Math::Max(FloorMin.Y, VolumeMin.Y), FloorMin.Z);
        const auto RimMax = FVector(Math::Min(FloorMax.X, VolumeMax.X), Math::Min(FloorMax.Y, VolumeMax.Y), FloorMax.Z);

        _RimOrigin = (RimMin + RimMax) * 0.5;
        _RimExtent = (RimMax - RimMin) * 0.5;
        _FloorTopZ = float(_FloorOrigin.Z + _FloorExtent.Z);

        // Every box must sit wholly inside the rim, or the carve is clipped by the volume edge and
        // what the probe reads is the edge rather than the paint.
        const auto NeededUu = RingRadiusUu + float(BoxHalfExtents.X) + 100.0;

        ck::nav::Display(f"[RECAST-BUDGET] markup fixture: rim origin={_RimOrigin} extent={_RimExtent} | box halfExtents={BoxHalfExtents} | ring radius={RingRadiusUu}uu | rounds={RoundCount}");

        if (float(_RimExtent.X) < NeededUu || float(_RimExtent.Y) < NeededUu)
        {
            FinishFailure(f"staging failed: the rim {_RimExtent} is too small to hold a {BoxHalfExtents} box on a {RingRadiusUu}uu ring - the fixture, not the provider, is broken");
            return;
        }

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.0f));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);

        auto Clock = utils_timer::Add(LocalHandle, Params);
        Clock.BindTo_OnUpdate(FCk_Delegate_Timer(this, n"OnClockTick"));
        _ClockTimer = Clock;
    }

    UFUNCTION()
    private void OnClockTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _ClockSeconds += float(InDeltaT.Get_Seconds());
    }

    // A fresh session reports the provider Ready before it holds any tiles, so the surface is asked
    // for explicitly and then waited for as the condition it is - the first paint spot projecting -
    // rather than assumed from the health alone.
    UFUNCTION()
    private void Step_KickRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevisionAtStart = utils_nav_surface::Get_SurfaceRevision();
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    UFUNCTION()
    private void Check_FirstSpotProjects(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Get_SpotProjects(Get_SpotCentre(0)));
    }

    private FVector Get_SpotCentre(int32 InRound) const
    {
        const auto Angle = (float(InRound) / float(RoundCount)) * 2.0 * Math::PI;

        return FVector(
            _RimOrigin.X + Math::Cos(Angle) * RingRadiusUu,
            _RimOrigin.Y + Math::Sin(Angle) * RingRadiusUu,
            _FloorTopZ);
    }

    // The probe the carve can actually move: search half-extents tighter than the hole, so a point
    // inside the carve has nothing to snap to.
    private bool Get_SpotProjects(FVector InCentre) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InCentre);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query).Get_Status() == ECk_NavSurface_QueryStatus::Success;
    }

    private ECk_NavSurface_Reachability Get_ReachabilityToSpot() const
    {
        const auto From = FVector(_RimOrigin.X, _RimOrigin.Y, _FloorTopZ);
        return utils_nav_surface::Get_IsReachable(FCk_NavSurface_ReachabilityQuery(From, _SpotCentre));
    }

    //------------------------------------------------------------------------
    // The round driver
    //------------------------------------------------------------------------
    //
    // One stage per frame, gated on the frame counter so a second poll inside one frame can never
    // double-count a repair into the numbers this test exists to produce. A stage that never
    // resolves inside StageFrameCap is recorded as a miss and the round moves on, because a
    // measurement that reports "the repair did not land in 400 frames" is worth more than one that
    // dies as an anonymous timeout.

    UFUNCTION()
    private void Check_RoundsComplete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (_Round >= RoundCount)
        {
            Res.Set(true);
            return;
        }

        const auto Frame = utils_time::Get_FrameCounter();
        if (Frame <= _LastSampledFrame)
        {
            Res.Set(false);
            return;
        }

        _LastSampledFrame = Frame;

        if      (_Stage == Stage_PaintSampleable) { Do_PaintSampleable(); }
        else if (_Stage == Stage_AwaitLive)       { Do_AwaitLive(); }
        else if (_Stage == Stage_DropSampleable)  { Do_DropMarkup(Stage_PaintImpassable); }
        else if (_Stage == Stage_PaintImpassable) { Do_PaintImpassable(); }
        else if (_Stage == Stage_AwaitHole)       { Do_AwaitHole(); }
        else if (_Stage == Stage_DropImpassable)  { Do_DropMarkup(Stage_AwaitRestore); }
        else                                      { Do_AwaitRestore(); }

        Res.Set(_Round >= RoundCount);
    }

    private void Do_StampStageStart()
    {
        _StageStartFrame = utils_time::Get_FrameCounter();
        _StageStartSeconds = _ClockSeconds;
        _StagePolls = 0;
    }

    private int32 Get_StageFrames() const
    { return int32(utils_time::Get_FrameCounter() - _StageStartFrame); }

    private float Get_StageSeconds() const
    { return _ClockSeconds - _StageStartSeconds; }

    private void Do_PaintMarkup(FGameplayTag InAreaTag)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(BoxHalfExtents)),
            InAreaTag);
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, _SpotCentre, FVector::OneVector));

        _Markup = utils_nav_surface::Request_AreaMarkup(Request);

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints the carve on
        // every exit path, including the rounds this test drops itself.
        Track_ForCleanup(FCk_Handle(_Markup));
    }

    private void Do_PaintSampleable()
    {
        _SpotCentre = Get_SpotCentre(_Round);
        _RevisionBefore = utils_nav_surface::Get_SurfaceRevision();

        Do_PaintMarkup(utils_gameplay_tag::ResolveGameplayTag(n"Nav.Area.Restricted"));
        Do_StampStageStart();

        _Stage = Stage_AwaitLive;
    }

    private void Do_AwaitLive()
    {
        const auto IsLive = utils_nav_surface::Get_IsMarkupLive(_Markup);
        _StagePolls += 1;

        if (IsLive == false && _StagePolls < StageFrameCap)
        { return; }

        const auto Frames = Get_StageFrames();
        const auto Seconds = Get_StageSeconds();
        const auto RevisionAfter = utils_nav_surface::Get_SurfaceRevision();
        const auto RevisionBefore = _RevisionBefore;
        const auto Ordinal = _Round + 1;

        if (IsLive)
        {
            if (_LiveCount == 0 || Frames < _LiveFrameMin) { _LiveFrameMin = Frames; }
            if (_LiveCount == 0 || Frames > _LiveFrameMax) { _LiveFrameMax = Frames; }

            _LiveCount += 1;
            _LiveFrameSum += Frames;
            _LiveSecondsSum += Seconds;
        }
        else
        { _MissCount += 1; }

        const auto Cap = StageFrameCap;
        const auto Verdict = IsLive
            ? f"frames={Frames} seconds={Seconds :.4}"
            : f"NOT OBSERVED within {Cap} frames ({Seconds :.4}s)";

        ck::nav::Display(f"[RECAST-BUDGET] markup-live latency: {Verdict} revisionBefore={RevisionBefore} revisionAfter={RevisionAfter} (paint {Ordinal} of {RoundCount}, Nav.Area.Restricted at {_SpotCentre})");

        _Stage = Stage_DropSampleable;
    }

    // The destroy is deferred, so the impassable paint that follows can momentarily overlap the carve
    // being torn down. That is benign: Restricted is walkable at normal cost, so removing it changes
    // no polygon's existence, and the tiles simply rebuild once for both modifier changes.
    private void Do_DropMarkup(int32 InNextStage)
    {
        if (ck::IsValid(_Markup))
        { utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup)); }

        Do_StampStageStart();

        _Stage = InNextStage;
    }

    private void Do_PaintImpassable()
    {
        _RevisionBefore = utils_nav_surface::Get_SurfaceRevision();
        _ReachBefore = Get_ReachabilityToSpot();

        Do_PaintMarkup(utils_gameplay_tag::ResolveGameplayTag(n"Nav.Area.Impassable"));
        Do_StampStageStart();

        _Stage = Stage_AwaitHole;
    }

    private void Do_AwaitHole()
    {
        const auto HoleIsOpen = Get_SpotProjects(_SpotCentre) == false;
        _StagePolls += 1;

        if (HoleIsOpen == false && _StagePolls < StageFrameCap)
        { return; }

        const auto Frames = Get_StageFrames();
        const auto Seconds = Get_StageSeconds();
        const auto RevisionAfter = utils_nav_surface::Get_SurfaceRevision();
        const auto RevisionBefore = _RevisionBefore;
        const auto Ordinal = _Round + 1;
        const auto LiveFlag = utils_nav_surface::Get_IsMarkupLive(_Markup) ? "true" : "false";
        const auto ReachBefore = _ReachBefore;
        const auto ReachAfter = Get_ReachabilityToSpot();

        if (HoleIsOpen)
        {
            if (_HoleCount == 0 || Frames < _HoleFrameMin) { _HoleFrameMin = Frames; }
            if (_HoleCount == 0 || Frames > _HoleFrameMax) { _HoleFrameMax = Frames; }

            _HoleCount += 1;
            _HoleFrameSum += Frames;
            _HoleSecondsSum += Seconds;
        }
        else
        { _MissCount += 1; }

        const auto Cap = StageFrameCap;
        const auto Verdict = HoleIsOpen
            ? f"frames={Frames} seconds={Seconds :.4}"
            : f"NOT OBSERVED within {Cap} frames ({Seconds :.4}s)";

        ck::nav::Display(f"[RECAST-BUDGET] impassable-hole latency: {Verdict} revisionBefore={RevisionBefore} revisionAfter={RevisionAfter} (paint {Ordinal} of {RoundCount} at {_SpotCentre})");

        // The live flag is an observation here, never a gate: the impassable area removes the polygons the
        // flag samples, so it is expected to read false at the very moment the carve took effect.
        ck::nav::Display(f"[RECAST-BUDGET] impassable paint {Ordinal} of {RoundCount}: liveFlagAtHole={LiveFlag} reachabilityToCentre before={ReachBefore} after={ReachAfter} - the reachability facade projects endpoints with the project-wide extent, which is wider than this hole, so it is reported and not asserted on");

        _Stage = Stage_DropImpassable;
    }

    private void Do_AwaitRestore()
    {
        const auto Restored = Get_SpotProjects(_SpotCentre);
        _StagePolls += 1;

        if (Restored == false && _StagePolls < StageFrameCap)
        { return; }

        const auto Frames = Get_StageFrames();
        const auto Seconds = Get_StageSeconds();
        const auto Ordinal = _Round + 1;

        if (Restored == false)
        { _MissCount += 1; }

        const auto Cap = StageFrameCap;
        const auto Verdict = Restored
            ? f"frames={Frames} seconds={Seconds :.4}"
            : f"NOT OBSERVED within {Cap} frames ({Seconds :.4}s)";

        ck::nav::Display(f"[RECAST-BUDGET] unpaint repair latency: {Verdict} (paint {Ordinal} of {RoundCount} at {_SpotCentre})");

        _Round += 1;
        _Stage = Stage_PaintSampleable;
    }

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RevisionNow = utils_nav_surface::Get_SurfaceRevision();
        const auto RevisionAtStart = _RevisionAtStart;

        auto LiveMeanFrames = 0.0f;
        auto LiveMeanSeconds = 0.0f;
        if (_LiveCount > 0)
        {
            LiveMeanFrames = float32(_LiveFrameSum) / float32(_LiveCount);
            LiveMeanSeconds = float32(_LiveSecondsSum) / float32(_LiveCount);
        }

        auto HoleMeanFrames = 0.0f;
        auto HoleMeanSeconds = 0.0f;
        if (_HoleCount > 0)
        {
            HoleMeanFrames = float32(_HoleFrameSum) / float32(_HoleCount);
            HoleMeanSeconds = float32(_HoleSecondsSum) / float32(_HoleCount);
        }

        const auto LiveCount = _LiveCount;
        const auto LiveMin = _LiveFrameMin;
        const auto LiveMax = _LiveFrameMax;
        const auto HoleCount = _HoleCount;
        const auto HoleMin = _HoleFrameMin;
        const auto HoleMax = _HoleFrameMax;
        const auto Misses = _MissCount;

        ck::nav::Display(f"[RECAST-BUDGET] markup-live latency over {LiveCount} of {RoundCount} paints: frames min={LiveMin} max={LiveMax} mean={LiveMeanFrames :.2} | seconds mean={LiveMeanSeconds :.4}");
        ck::nav::Display(f"[RECAST-BUDGET] impassable-hole latency over {HoleCount} of {RoundCount} paints: frames min={HoleMin} max={HoleMax} mean={HoleMeanFrames :.2} | seconds mean={HoleMeanSeconds :.4}");
        ck::nav::Display(f"[RECAST-BUDGET] surface revision across the whole run: {RevisionAtStart} -> {RevisionNow}, stages that never resolved={Misses}");

        Assert_True(_LiveCount > 0,
            f"a run in which no paint ever read live measures nothing about how long a paint takes to reach the tiles - {LiveCount} of {RoundCount} were observed");

        Assert_True(_HoleCount > 0,
            f"a run in which no impassable box ever carved its hole measures nothing about the consequence of a paint - {HoleCount} of {RoundCount} were observed");

        Assert_True(RevisionNow > RevisionAtStart,
            f"a run of paints and unpaints over a built surface must move the revision - was {RevisionAtStart}, now {RevisionNow}");
    }
}
