// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: HOW LONG THE NAVMESH TAKES TO FOLLOW A MOVED OBSTACLE
//============================================================================
//
// A measurement, not a contract. Runtime navmesh generation is Dynamic for this project, so an
// obstacle arriving somewhere new does not wait for a full build: the tiles it left and the tiles
// it entered are both dirtied, and Recast repairs them over the following frames. A shop-floor
// prop that a player picks up and puts down 6 metres away is exactly that event, and how many
// frames the mesh lags behind it is the number every "can this agent still get there" answer is
// quietly built on.
//
// WHY A MARKUP BOX AND NOT A RUNTIME MESH. Two measured runs against a runtime-spawned 300uu
// AStaticMeshActor (Saved/Logs/P4-A6-Recast.log, Saved/Logs/P4-A6-Recast2.log) showed the dynamic
// tile rebuilds firing on every move - the surface revision climbed by one per move - while never
// carrying the geometry of the runtime cube, so the spot under it kept projecting until a full
// Request_SurfaceRebuild_ForTesting. The obstacle vocabulary of the fixture suite is the
// impassable markup box in any case: every crowd and queue fixture expresses a blocker as
// utils_nav_surface::Request_ImpassableBox.
//
// WHAT IS TIMED. A 300uu impassable markup box is painted on the level floor and waited on until
// it has actually carved its hole - the named condition is a projection probe at the box centre,
// with search half-extents tighter than the hole, no longer succeeding. A "move" is then that box
// being destroyed and a new one painted 600uu away in the SAME frame, and the two halves of the
// repair are timed SEPARATELY, because they are two different tile sets and there is no reason
// they should land on the same frame:
//
//   the OLD spot projecting again    - the tiles the box left being rebuilt as open floor.
//   the NEW spot no longer projecting - the tiles the box entered being rebuilt as a hole.
//
// The move ping-pongs between two spots 600uu apart, so every round is the same distance and the
// old and new roles simply swap. No rebuild is kicked between moves on purpose: kicking one would
// measure UNavigationSystemV1::Build(), not the dirty-area repair the move actually triggers.
//
// The assertions are sanity bounds only: the first paint must have carved its hole before any move
// is timed, at least one move must have been observed in full, and the surface revision must have
// moved. Anything tighter would be asserting the numbers this test exists to discover.
//
// SHARED-WORLD HYGIENE: the markup box is the only thing this test adds, it is registered for
// cleanup as it is painted and destroyed at the end, and the test does not finish until the floor
// it stood on projects again.
//============================================================================

class UCk_AutoTest_NavSurface_RecastBudgets_MovedObstacleRepairLatency : UCk_AutoTest_Base
{
    // Five moves, each waiting on two independent tile repairs. Deliberately slack - a measurement
    // that times out measures nothing.
    default _TimeoutSeconds = 240.0f;

    private const int32 MoveCount = 5;

    private const float BoxSizeUu = 300.0;

    // BoxSizeUu on a side, quoted as half-extents, and 200uu tall so the box straddles the floor
    // top rather than resting on it - a box that only touches the surface can leave the vertical
    // span of the tile outside the carve.
    private const FVector BoxHalfExtents = FVector(150.0, 150.0, 100.0);

    // The two spots the box ping-pongs between, as offsets from the rim centre. 600uu apart on X,
    // and pushed off the X axis so the corridor the other nav fixtures stage on is left alone.
    private const float SpotOffsetXUu = 300.0;
    private const float SpotOffsetYUu = 500.0;
    private const float MoveDistanceUu = 600.0;

    // Tighter than the hole a 300uu box leaves after agent-radius erosion, so a probe inside the
    // carve cannot snap to a polygon beside it. The vertical half-extent stays well under the box
    // height, so nothing Recast may bake above the carve is ever mistaken for floor.
    private const FVector ProbeHalfExtents = FVector(60.0, 60.0, 80.0);

    // Per-move ceiling. A dirty-area repair is a handful of frames; this is that with room over, and
    // it is what turns a wedged repair into a reported miss instead of a hung test.
    private const int32 MoveFrameCap = 400;

    private const int32 Stage_Move  = 0;
    private const int32 Stage_Await = 1;

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

    private FVector _FromCentre = FVector::ZeroVector;
    private FVector _ToCentre = FVector::ZeroVector;

    private int32 _Move = 0;
    private int32 _Stage = 0;
    private int64 _LastSampledFrame = -1;
    private int64 _StageStartFrame = 0;
    private float _StageStartSeconds = 0.0;
    private int32 _StagePolls = 0;
    private int64 _RevisionBefore = 0;
    private int64 _RevisionAtStart = 0;

    private bool _OldSeen = false;
    private bool _NewSeen = false;
    private int32 _OldFrames = 0;
    private float _OldSeconds = 0.0;
    private int32 _NewFrames = 0;
    private float _NewSeconds = 0.0;

    private int32 _OldCount = 0;
    private int32 _OldFrameMin = 0;
    private int32 _OldFrameMax = 0;
    private int32 _OldFrameSum = 0;
    private float _OldSecondsSum = 0.0;

    private int32 _NewCount = 0;
    private int32 _NewFrameMin = 0;
    private int32 _NewFrameMax = 0;
    private int32 _NewFrameSum = 0;
    private float _NewSecondsSum = 0.0;

    private int32 _BothCount = 0;

    private int32 _FirstPaintPolls = 0;
    private bool _FirstPaintCarveSeen = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",   n"Check_ProviderIsReady", 900);
        Add_Step(          "find the level floor and its rectangle",      n"Step_FindFloor");
        Add_Step(          "ask the provider to build its surface",       n"Step_KickRebuild");
        Add_Step_WaitUntil("both obstacle spots project on bare floor",   n"Check_BothSpotsProject", 900);
        Add_Step(          "paint the impassable box on the first spot",  n"Step_FirstPaint");
        Add_Step_WaitUntil("the first paint carve has been observed",     n"Check_FirstPaintCarveObserved", 900);
        Add_Step_WaitUntil("every move has been observed",                n"Check_MovesComplete", 9000);
        Add_Step(          "report what a move cost the navmesh",         n"Step_Report");
        Add_Step(          "destroy the last markup box",                 n"Step_TearDown");
        Add_Step_WaitUntil("the floor comes back where the box stood",    n"Check_BothSpotsProject", 900);
        Add_Step(          "judge the run",                               n"Step_Judge");
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

        // Both spots must sit wholly inside the rim, or what the probe reads is the volume edge
        // rather than the carve.
        const auto NeededX = SpotOffsetXUu + BoxSizeUu * 0.5 + 100.0;
        const auto NeededY = SpotOffsetYUu + BoxSizeUu * 0.5 + 100.0;

        ck::nav::Display(f"[RECAST-BUDGET] moved-markup-box fixture: rim origin={_RimOrigin} extent={_RimExtent} | obstacle=impassable markup box {BoxSizeUu}uu | move distance={MoveDistanceUu}uu | moves={MoveCount}");

        if (float(_RimExtent.X) < NeededX || float(_RimExtent.Y) < NeededY)
        {
            FinishFailure(f"staging failed: the rim {_RimExtent} is too small to hold a {BoxSizeUu}uu box at both ends of a {MoveDistanceUu}uu move - the fixture, not the provider, is broken");
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
    // for explicitly and then waited for as the condition it is - both spots projecting on bare
    // floor - rather than assumed from the health alone.
    UFUNCTION()
    private void Step_KickRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevisionAtStart = utils_nav_surface::Get_SurfaceRevision();
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    private FVector Get_SpotCentre(int32 InIndex) const
    {
        const auto SignedX = InIndex % 2 == 0 ? -SpotOffsetXUu : SpotOffsetXUu;

        return FVector(
            _RimOrigin.X + SignedX,
            _RimOrigin.Y + SpotOffsetYUu,
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

    UFUNCTION()
    private void Check_BothSpotsProject(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Get_SpotProjects(Get_SpotCentre(0)) && Get_SpotProjects(Get_SpotCentre(1)));
    }

    // Request_ImpassableBox ignores the area tag on the request and paints the well-known
    // impassable area, so the tag handed in here is deliberately empty.
    private void Do_PaintMarkup(FVector InCentre)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(BoxHalfExtents)),
            FGameplayTag());
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, InCentre, FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(Request);

        // The markup entity is parented to the WORLD, not to this runner, so the subtree teardown
        // the harness runs never reaches it - registering it here is what unpaints the carve on
        // every exit path, including the boxes this test drops itself.
        Track_ForCleanup(FCk_Handle(_Markup));
    }

    private void Do_DropMarkup()
    {
        if (ck::IsValid(_Markup))
        { utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup)); }

        _Markup = FCk_Handle_NavSurfaceMarkup();
    }

    UFUNCTION()
    private void Step_FirstPaint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ToCentre = Get_SpotCentre(0);
        _RevisionBefore = utils_nav_surface::Get_SurfaceRevision();

        Do_PaintMarkup(_ToCentre);

        if (!ck::IsValid(_Markup))
        {
            FinishFailure("staging failed: the impassable markup box could not be painted, so there is no obstacle to move - the fixture, not the provider, is broken");
            return;
        }

        _StageStartFrame = utils_time::Get_FrameCounter();
        _StageStartSeconds = _ClockSeconds;
        _FirstPaintPolls = 0;
    }

    // Soft-observed like every move below: a paint whose carve never lands is reported and the run
    // goes on to the moves and the teardown, so a wedged bake can neither hang this test nor leave
    // its carve in the shared world for the next one.
    UFUNCTION()
    private void Check_FirstPaintCarveObserved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        const auto Frame = utils_time::Get_FrameCounter();
        if (Frame <= _LastSampledFrame)
        {
            Res.Set(false);
            return;
        }

        _LastSampledFrame = Frame;
        _FirstPaintPolls += 1;

        const auto Frames = int32(Frame - _StageStartFrame);
        const auto Seconds = _ClockSeconds - _StageStartSeconds;
        const auto Carved = Get_SpotProjects(_ToCentre) == false;

        if (Carved == false && _FirstPaintPolls < MoveFrameCap)
        {
            Res.Set(false);
            return;
        }

        _FirstPaintCarveSeen = Carved;

        const auto RevisionBefore = _RevisionBefore;
        const auto RevisionAfter = utils_nav_surface::Get_SurfaceRevision();
        const auto Cap = MoveFrameCap;
        const auto Verdict = Carved
            ? f"frames={Frames} seconds={Seconds :.4}"
            : f"NOT OBSERVED within {Cap} frames";

        ck::nav::Display(f"[RECAST-BUDGET] impassable-box carve latency: {Verdict}, revisionBefore={RevisionBefore} revisionAfter={RevisionAfter} (box={BoxSizeUu}uu at {_ToCentre})");

        Res.Set(true);
    }

    //------------------------------------------------------------------------
    // The move driver
    //------------------------------------------------------------------------
    //
    // One stage per frame, gated on the frame counter so a second poll inside one frame can never
    // double-count a repair into the numbers this test exists to produce. A move whose two repairs
    // do not both land inside MoveFrameCap is recorded with whichever half did land and the run
    // moves on, because a measurement that reports "the far side never came back in 400 frames" is
    // worth more than one that dies as an anonymous timeout.

    UFUNCTION()
    private void Check_MovesComplete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        if (_Move >= MoveCount)
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

        if (_Stage == Stage_Move) { Do_Move(); }
        else                      { Do_AwaitRepair(); }

        Res.Set(_Move >= MoveCount);
    }

    // The drop and the repaint land in the same frame on purpose: what is being timed is one
    // obstacle arriving somewhere new, not an unpaint followed later by an unrelated paint.
    private void Do_Move()
    {
        if (!ck::IsValid(_Markup))
        {
            FinishFailure("the markup box went away mid-run, so there is nothing left to move - the fixture, not the provider, is broken");
            return;
        }

        _FromCentre = _ToCentre;
        _ToCentre = Get_SpotCentre(_Move + 1);

        _RevisionBefore = utils_nav_surface::Get_SurfaceRevision();

        _OldSeen = false;
        _NewSeen = false;
        _OldFrames = 0;
        _NewFrames = 0;
        _OldSeconds = 0.0;
        _NewSeconds = 0.0;

        _StageStartFrame = utils_time::Get_FrameCounter();
        _StageStartSeconds = _ClockSeconds;
        _StagePolls = 0;

        Do_DropMarkup();
        Do_PaintMarkup(_ToCentre);

        _Stage = Stage_Await;
    }

    private void Do_AwaitRepair()
    {
        _StagePolls += 1;

        const auto Frames = int32(utils_time::Get_FrameCounter() - _StageStartFrame);
        const auto Seconds = _ClockSeconds - _StageStartSeconds;

        if (_OldSeen == false && Get_SpotProjects(_FromCentre))
        {
            _OldSeen = true;
            _OldFrames = Frames;
            _OldSeconds = Seconds;
        }

        if (_NewSeen == false && Get_SpotProjects(_ToCentre) == false)
        {
            _NewSeen = true;
            _NewFrames = Frames;
            _NewSeconds = Seconds;
        }

        const auto BothSeen = _OldSeen && _NewSeen;

        if (BothSeen == false && _StagePolls < MoveFrameCap)
        { return; }

        Do_RecordMove(BothSeen, Frames, Seconds);
    }

    private void Do_RecordMove(bool InBothSeen, int32 InFrames, float InSeconds)
    {
        const auto RevisionAfter = utils_nav_surface::Get_SurfaceRevision();
        const auto RevisionBefore = _RevisionBefore;
        const auto Ordinal = _Move + 1;

        if (_OldSeen)
        {
            if (_OldCount == 0 || _OldFrames < _OldFrameMin) { _OldFrameMin = _OldFrames; }
            if (_OldCount == 0 || _OldFrames > _OldFrameMax) { _OldFrameMax = _OldFrames; }

            _OldCount += 1;
            _OldFrameSum += _OldFrames;
            _OldSecondsSum += _OldSeconds;
        }

        if (_NewSeen)
        {
            if (_NewCount == 0 || _NewFrames < _NewFrameMin) { _NewFrameMin = _NewFrames; }
            if (_NewCount == 0 || _NewFrames > _NewFrameMax) { _NewFrameMax = _NewFrames; }

            _NewCount += 1;
            _NewFrameSum += _NewFrames;
            _NewSecondsSum += _NewSeconds;
        }

        if (InBothSeen)
        { _BothCount += 1; }

        const auto OldFrames = _OldFrames;
        const auto OldSeconds = _OldSeconds;
        const auto NewFrames = _NewFrames;
        const auto NewSeconds = _NewSeconds;
        const auto Cap = MoveFrameCap;

        const auto OldVerdict = _OldSeen
            ? f"frames={OldFrames} seconds={OldSeconds :.4}"
            : f"NOT OBSERVED within {Cap} frames";

        const auto NewVerdict = _NewSeen
            ? f"frames={NewFrames} seconds={NewSeconds :.4}"
            : f"NOT OBSERVED within {Cap} frames";

        ck::nav::Display(f"[RECAST-BUDGET] moved-markup-box repair latency: move {Ordinal} of {MoveCount} by {MoveDistanceUu}uu, oldSpotProjectsAgain {OldVerdict}, newSpotStopsProjecting {NewVerdict}, revisionBefore={RevisionBefore} revisionAfter={RevisionAfter}, waitedFrames={InFrames} waitedSeconds={InSeconds :.4}");

        _Move += 1;
        _Stage = Stage_Move;
    }

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RevisionNow = utils_nav_surface::Get_SurfaceRevision();
        const auto RevisionAtStart = _RevisionAtStart;

        auto OldMeanFrames = 0.0f;
        auto OldMeanSeconds = 0.0f;
        if (_OldCount > 0)
        {
            OldMeanFrames = float32(_OldFrameSum) / float32(_OldCount);
            OldMeanSeconds = float32(_OldSecondsSum) / float32(_OldCount);
        }

        auto NewMeanFrames = 0.0f;
        auto NewMeanSeconds = 0.0f;
        if (_NewCount > 0)
        {
            NewMeanFrames = float32(_NewFrameSum) / float32(_NewCount);
            NewMeanSeconds = float32(_NewSecondsSum) / float32(_NewCount);
        }

        const auto OldCount = _OldCount;
        const auto OldMin = _OldFrameMin;
        const auto OldMax = _OldFrameMax;
        const auto NewCount = _NewCount;
        const auto NewMin = _NewFrameMin;
        const auto NewMax = _NewFrameMax;
        const auto BothCount = _BothCount;

        ck::nav::Display(f"[RECAST-BUDGET] moved-markup-box repair latency, OLD spot reopening over {OldCount} of {MoveCount} moves: frames min={OldMin} max={OldMax} mean={OldMeanFrames :.2} | seconds mean={OldMeanSeconds :.4}");
        ck::nav::Display(f"[RECAST-BUDGET] moved-markup-box repair latency, NEW spot closing over {NewCount} of {MoveCount} moves: frames min={NewMin} max={NewMax} mean={NewMeanFrames :.2} | seconds mean={NewMeanSeconds :.4}");
        ck::nav::Display(f"[RECAST-BUDGET] moves where both halves of the repair landed: {BothCount} of {MoveCount} | surface revision across the whole run: {RevisionAtStart} -> {RevisionNow}");
    }

    // After the teardown on purpose: a verdict that fires before it strands the carve in the shared
    // world and fails the next test for a reason it did not cause.
    UFUNCTION()
    private void Step_Judge(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RevisionNow = utils_nav_surface::Get_SurfaceRevision();
        const auto RevisionAtStart = _RevisionAtStart;
        const auto BothCount = _BothCount;

        Assert_True(_FirstPaintCarveSeen,
            "the first impassable box never carved the navmesh, so nothing this test moved was ever an obstacle to the provider");

        Assert_True(_BothCount > 0,
            f"a run in which no move ever had both halves of its repair land measures nothing about how fast the navmesh follows an obstacle - {BothCount} of {MoveCount} did");

        Assert_True(RevisionNow > RevisionAtStart,
            f"a paint and five moves over a built surface must move the revision - was {RevisionAtStart}, now {RevisionNow}");
    }

    // Teardown - the PIE world is shared, so nothing painted here outlives the test. The step after
    // this one waits for the floor to come back, so the test does not report green over a navmesh it
    // left with a hole in it.
    UFUNCTION()
    private void Step_TearDown(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Do_DropMarkup();
    }
}
