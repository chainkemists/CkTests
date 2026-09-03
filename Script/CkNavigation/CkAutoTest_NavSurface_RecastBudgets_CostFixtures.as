// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: WHAT SHAPE OF GROUND MOVES RECAST'S ROUTE CHOICE
//============================================================================
//
// A measurement, not a contract - the sibling of the origin-floor budget test, one level up. That
// one asks how far Recast's answers sit from ground it can see; this one asks what SHAPE of ground
// moves them, on the three shapes a second provider would have to agree with it about:
//
//   RAMP vs LEVEL - a short route over a hump against a longer flat way round. Which does Recast
//     take, and at what length ratio does the choice flip? Its default query filter carries
//     per-area costs and nothing else, so the expectation is that it ignores the climb entirely.
//   CORRIDOR - inside a 300uu corridor with one right-angle bend, how far do the waypoints sit from
//     the walls, and from the centre line? How tightly a funnel hugs the inside of a turn is what a
//     clearance budget is derived from.
//   CORNER - rounding a pillar, how far from the corner VERTEX does the waypoint land, in units of
//     agent radius? That is the form the shipping code's own corner-offset knob takes.
//
// THE CODE-SIDE PARITY VALUE FOR THE CORNER IS ZERO. FCk_Nav_Algorithm::FindPathSync forwards its
// InCornerOffsetDistance to FNavMeshPath::OffsetFromCorners only when that distance is finite and
// positive (CkNav_Algorithm.cpp:140-147), and the one production caller,
// FProcessor_Nav_HandleRequests, passes 0.0f (CkNav_Processor.cpp:446). So what is measured below
// is Recast's raw corridor corner after agent-radius erosion, with nothing layered on top.
//
// THE FIXTURES ARE SIZED FROM A MEASURED BAND, NOT AN ASSUMED ONE. They are built at runtime on the
// isolation band centred at (0, 110000, 0), which the level's second NavMeshBoundsVolume covers, and
// Recast bakes NOTHING outside that volume. The volume's extents are level content this test does
// not own and cannot read, so hard-coded extents lay fixtures past the real rim, leaving endpoints
// with no polygon under them. So the floor goes down first, the bakeable extent is WALKED OUT from
// the band centre until projection fails, and the fixtures are then laid out and scaled to fit what
// was actually found. A band too small for the fixture set fails loudly, naming what it measured.
//
// Placements are deterministic given the discovered extent; nothing here is random, and everything
// spawned is taken back down. The assertions are sanity only: each fixture must produce a Ready path
// with waypoints in it. Asserting a clearance or a route choice would be asserting the number this
// test exists to find.
//============================================================================

class UCk_AutoTest_NavSurface_RecastBudgets_CostFixtures : UCk_AutoTest_Base
{
    // Three fixtures, five queries and three rebuilds over runtime-spawned geometry. Deliberately
    // slack - a measurement that times out measures nothing.
    default _TimeoutSeconds = 180.0f;

    // /Engine/BasicShapes/Cube is 100uu on a side, so an actor scale of N gives N*100uu of extent.
    private const float64 CubeMeshSizeUu = 100.0;
    private const float64 BandY = 110000.0;
    private const float64 FloorTopZ = 0.0;

    // The floor is laid larger than any plausible volume so the walk-out below finds the VOLUME's
    // rim rather than the floor's. A slab thinner than half a cube bakes zero tiles, so it is 50uu
    // thick with its TOP at FloorTopZ - the Z every start, goal and waypoint is quoted against.
    private const float64 FloorHalfSpanUu = 2875.0;
    private const float64 FloorThicknessUu = 50.0;

    // The project's "Default" supported agent (Config/DefaultEngine.ini): radius 35, height 144,
    // step height 35. Stated here rather than inferred - FCk_Request_Nav_FindPath carries no radius
    // of its own, and FProcessor_Nav_HandleRequests passes 0 for the first-waypoint skip radius.
    private const float64 AgentRadiusUu = 35.0;

    //------------------------------------------------------------------------
    // Discovery
    //------------------------------------------------------------------------

    private const float64 DiscoveryStepUu = 100.0;
    private const float64 DiscoveryMaxUu = 3000.0;

    // Recast erodes the mesh back from the volume's rim as it does from any obstacle, and the walk
    // stops at the last point that still projected, so the usable span is pulled in by this much
    // again before anything is laid out on it.
    private const float64 RimMarginUu = 250.0;

    // Below this on any axis there is no point measuring anything: the corridor alone is 500uu
    // across its walls.
    private const float64 MinBandExtentUu = 700.0;

    // How far every endpoint is kept from the nearest face. Recast erodes by the agent radius plus
    // roughly a cell, so this is that with room over.
    private const float64 EndpointClearUu = 80.0;

    // Fraction of a cell a fixture is allowed to fill, so neighbouring fixtures never share tiles.
    private const float64 CellFillFraction = 0.9;

    //------------------------------------------------------------------------
    // Natural fixture dimensions - what is used when the band is large enough
    //------------------------------------------------------------------------

    // rise/run = 150/250 = 0.6, i.e. 30.9638 degrees, well inside Recast's 44-degree walkable limit.
    // Both scale together when the band is tight, so the ANGLE - the thing being measured - is the
    // one quantity that never changes.
    private const float64 NaturalHumpRiseUu = 150.0;
    private const float64 NaturalHumpRunUu = 250.0;
    private const float64 NaturalPlateauHalfUu = 150.0;
    private const float64 HumpRollDeg = 30.9638;
    private const float64 RampThicknessUu = 30.0;
    private const float64 RampBuryUu = 20.0;

    // The plateau has to stay wide enough to carry a walkable polygon after erosion from both sides,
    // which is what floors the hump's scale.
    private const float64 MinHumpScale = 0.533;

    private const float64 WallThicknessUu = 100.0;
    private const float64 WallHeightUu = 400.0;

    // Start and goal sit at +/- D on the ramp fixture's Y axis. Over the hump is 2D of planar travel;
    // round the wall's end is 2*sqrt(D^2 + E^2) for a wall of half-span E. Solving that ratio for D
    // gives D = E / K, with K below for detours of 1.2x, 1.5x and 2.0x.
    private const float64 DetourK12 = 0.66332;
    private const float64 DetourK15 = 1.11803;
    private const float64 DetourK20 = 1.73205;

    // Fixed at 300uu whatever the band allows: the corridor's width IS the clearance question, so
    // scaling it would change the number rather than fit it.
    private const float64 CorridorHalfWidthUu = 150.0;
    private const float64 NaturalCorridorLegUu = 900.0;
    private const float64 MinCorridorLegUu = 500.0;

    private const float64 NaturalPillarHalfUu = 300.0;
    private const float64 MinPillarHalfUu = 200.0;

    // The corner probes stand this far clear of the pillar's own half-extent on each axis. Recast
    // erodes ~60uu back from the pillar's faces, so 300 leaves a wide margin and keeps the fixture
    // small enough to share a column.
    private const float64 CornerStandoffUu = 300.0;

    //------------------------------------------------------------------------
    // Probes
    //------------------------------------------------------------------------

    // The VERTICAL bound is what keeps a probe honest, not the horizontal one. A solid cube's flat
    // top bakes as its own walkable island, but every one of those tops is at WallHeightUu, so a box
    // reaching only 250uu up from floor level cannot snap onto one however wide it is. That frees
    // the horizontal reach to be generous enough to survive Recast's erosion from every face.
    private const FVector ProbeHalfExtents = FVector(80.0, 80.0, 250.0);

    private const int32 LivePollLogInterval = 120;
    private int32 _LivePollCount = 0;

    //------------------------------------------------------------------------
    // State
    //------------------------------------------------------------------------

    private TArray<AStaticMeshActor> _SpawnedActors;
    private bool _BandAlreadyHadGround = false;

    private float64 _ExtentPlusX = 0.0;
    private float64 _ExtentMinusX = 0.0;
    private float64 _ExtentPlusY = 0.0;
    private float64 _ExtentMinusY = 0.0;

    // Resolved by Step_ResolveLayout from the discovered extent. Fixture positions are band-local:
    // X is a world offset, Y is an offset from BandY.
    private float64 _RampCentreX = 0.0;
    private float64 _RampCentreY = 0.0;
    private float64 _CorridorCentreX = 0.0;
    private float64 _CorridorCentreY = 0.0;
    private float64 _CornerCentreX = 0.0;
    private float64 _CornerCentreY = 0.0;

    private float64 _HumpScale = 1.0;
    private float64 _HumpRiseUu = 150.0;
    private float64 _HumpRunUu = 250.0;
    private float64 _PlateauHalfUu = 150.0;
    private float64 _RampWidthUu = 300.0;
    private float64 _WallHalfSpanUu = 830.0;
    private float64 _RampProbe12Uu = 1251.0;
    private float64 _RampProbe15Uu = 742.0;
    private float64 _RampProbe20Uu = 479.0;

    private float64 _CorridorLegUu = 900.0;
    private float64 _PillarHalfUu = 300.0;
    private float64 _CornerProbeUu = 800.0;

    // The corridor's four wall boxes in WORLD space, so waypoint-to-wall distance is measured
    // against the geometry this test authored rather than a tube approximation of it.
    private TArray<FVector> _CorridorWallMin;
    private TArray<FVector> _CorridorWallMax;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _Requester;
    private FVector _QueryStart = FVector::ZeroVector;
    private FVector _QueryGoal = FVector::ZeroVector;
    private FString _QueryLabel;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        Add_Step_WaitUntil("the nav surface provider settles at Ready",       n"Check_ProviderIsReady", 900);
        Add_Step(          "probe the band for ground that is already there", n"Step_ProbeBand");
        Add_Step(          "lay the floor over the band",                     n"Step_LayFloor");
        Add_Step_WaitUntil("the floor is live on the surface",                n"Check_FloorIsLive", 6000);
        Add_Step(          "walk out the band's bakeable extent",             n"Step_DiscoverExtent");
        Add_Step(          "lay the three fixtures out inside it",            n"Step_BuildFixtures");
        Add_Step_WaitUntil("the fixtures are live on the surface",            n"Check_FixturesAreLive", 6000);

        Add_Step(          "route the hump against a 1.2x detour",            n"Step_QueryRamp12");
        Add_Step_WaitUntil("the 1.2x query settles",                          n"Check_QuerySettled", 900);
        Add_Step(          "record which route the 1.2x case took",           n"Step_RecordRamp");

        Add_Step(          "route the hump against a 1.5x detour",            n"Step_QueryRamp15");
        Add_Step_WaitUntil("the 1.5x query settles",                          n"Check_QuerySettled", 900);
        Add_Step(          "record which route the 1.5x case took",           n"Step_RecordRamp");

        Add_Step(          "route the hump against a 2.0x detour",            n"Step_QueryRamp20");
        Add_Step_WaitUntil("the 2.0x query settles",                          n"Check_QuerySettled", 900);
        Add_Step(          "record which route the 2.0x case took",           n"Step_RecordRamp");

        Add_Step(          "route the bent corridor end to end",              n"Step_QueryCorridor");
        Add_Step_WaitUntil("the corridor query settles",                      n"Check_QuerySettled", 900);
        Add_Step(          "measure the corridor route's clearances",         n"Step_RecordCorridor");

        Add_Step(          "route around the pillar on the diagonal",         n"Step_QueryCorner");
        Add_Step_WaitUntil("the corner query settles",                        n"Check_QuerySettled", 900);
        Add_Step(          "measure the corner waypoint's offset",            n"Step_RecordCorner");

        Add_Step(          "take the fixtures back down",                     n"Step_TearDown");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Geometry helpers
    //------------------------------------------------------------------------

    // Band-local: InCentreX is a world X, InCentreY an offset from BandY, and the local pair is the
    // point's position inside its own fixture.
    private FVector Get_FixturePoint(float64 InCentreX, float64 InCentreY, float64 InLocalX, float64 InLocalY, float64 InZ) const
    { return FVector(InCentreX + InLocalX, BandY + InCentreY + InLocalY, InZ); }

    private AStaticMeshActor DoSpawn_Box(FVector InCentre, FVector InSizeUu, FRotator InRotation)
    {
        auto Box = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, InCentre, InRotation));
        if (!System::IsValid(Box))
        { return nullptr; }

        // A runtime-spawned AStaticMeshActor must be Movable BEFORE it will accept a mesh.
        Box.StaticMeshComponent.SetMobility(EComponentMobility::Movable);

        auto CubeMesh = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!System::IsValid(CubeMesh))
        {
            Box.DestroyActor();
            return nullptr;
        }

        Box.StaticMeshComponent.SetStaticMesh(CubeMesh);
        Box.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");
        Box.SetActorScale3D(InSizeUu * (1.0 / CubeMeshSizeUu));

        // Explicit, because actor-level relevance is not covered by a NavModifier toggle, and a
        // body Recast never registered is free space to the bake.
        utils_nav::Request_SetActorNavigationRegistered(Box, true);

        _SpawnedActors.Add(Box);
        return Box;
    }

    private float64 Get_Distance2D_PointToSegment(FVector InPoint, FVector InA, FVector InB) const
    {
        auto P = InPoint; P.Z = 0.0;
        auto A = InA;     A.Z = 0.0;
        auto B = InB;     B.Z = 0.0;

        const auto AB = B - A;
        const auto LengthSquared = AB.SizeSquared();
        if (LengthSquared < 0.0001)
        { return (P - A).Size(); }

        const auto T = Math::Clamp((P - A).DotProduct(AB) / LengthSquared, 0.0, 1.0);
        return (P - (A + AB * T)).Size();
    }

    private float64 Get_Distance2D_PointToBox(FVector InPoint, FVector InMin, FVector InMax) const
    {
        const auto OutsideX = Math::Max(Math::Max(InMin.X - InPoint.X, InPoint.X - InMax.X), 0.0);
        const auto OutsideY = Math::Max(Math::Max(InMin.Y - InPoint.Y, InPoint.Y - InMax.Y), 0.0);
        return FVector(OutsideX, OutsideY, 0.0).Size();
    }

    private bool Get_PointProjects(FVector InPoint) const
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);

        const auto Result = utils_nav_surface::Try_ProjectPoint(Query);
        return Result.Get_Status() == ECk_NavSurface_QueryStatus::Success;
    }

    private int32 Get_ProbeFlag(FVector InPoint) const
    { return Get_PointProjects(InPoint) ? 1 : 0; }

    // Blocked is a two-in-one positive: the surface has to exist under the start point for the ray
    // to be walked at all, and something has to stop it before the target. Over open floor the same
    // ray answers Clear, so this is what separates "the walls are baked" from "the floor is baked".
    private bool Get_RaycastBlocked(FVector InFrom, FVector InTo) const
    {
        const auto Result = utils_nav_surface::Try_SurfaceRaycast(FCk_NavSurface_RaycastQuery(InFrom, InTo));
        return Result.Get_Status() == ECk_NavSurface_QueryStatus::Blocked;
    }

    //------------------------------------------------------------------------
    // Staging: floor, then discovery, then fixtures
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_ProbeBand(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        _BandAlreadyHadGround = Get_PointProjects(FVector(0.0, BandY, FloorTopZ));
        const auto Verdict = _BandAlreadyHadGround ? "yes" : "no";

        ck::nav::Display(f"[RECAST-BUDGET] band centre (0, {BandY}, 0) already carried walkable ground before staging: {Verdict} - a floor is laid either way, so every fixture rests on geometry this test owns and removes");
    }

    UFUNCTION()
    private void Step_LayFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Floor = DoSpawn_Box(
            FVector(0.0, BandY, FloorTopZ - FloorThicknessUu * 0.5),
            FVector(FloorHalfSpanUu * 2.0, FloorHalfSpanUu * 2.0, FloorThicknessUu),
            FRotator::ZeroRotator);

        if (!System::IsValid(Floor))
        {
            DoTearDown();
            FinishFailure("staging failed: the band floor could not be spawned - /Engine/BasicShapes/Cube.Cube did not load, so the fixture is broken, not the provider");
            return;
        }

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    UFUNCTION()
    private void Check_FloorIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Get_PointProjects(FVector(0.0, BandY, FloorTopZ)));
    }

    // The floor is laid wider than any plausible volume, so what this finds is where RECAST stops
    // answering - the volume's rim, eroded - not where the floor ends.
    private float64 Get_WalkedExtent(float64 InDirX, float64 InDirY) const
    {
        auto Reached = 0.0;

        for (auto Step = DiscoveryStepUu; Step <= DiscoveryMaxUu; Step += DiscoveryStepUu)
        {
            const auto Point = FVector(InDirX * Step, BandY + InDirY * Step, FloorTopZ);
            if (Get_PointProjects(Point) == false)
            { break; }

            Reached = Step;
        }

        return Reached;
    }

    UFUNCTION()
    private void Step_DiscoverExtent(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _ExtentPlusX = Get_WalkedExtent(1.0, 0.0);
        _ExtentMinusX = Get_WalkedExtent(-1.0, 0.0);
        _ExtentPlusY = Get_WalkedExtent(0.0, 1.0);
        _ExtentMinusY = Get_WalkedExtent(0.0, -1.0);

        ck::nav::Display(f"[RECAST-BUDGET] band bake extent discovered: +X={_ExtentPlusX}uu -X={_ExtentMinusX}uu +Y={_ExtentPlusY}uu -Y={_ExtentMinusY}uu (floor was laid to +/-{FloorHalfSpanUu}uu, so anything short of that is the nav bounds volume, not the floor)");

        DoResolve_Layout();
    }

    // The discovered rectangle is split into two columns, and the right column into two rows. The
    // ramp fixture takes the whole left column because it is the one fixture that is far taller than
    // it is wide - its 1.2x probes sit at E/0.66 on the Y axis while the wall only spans E on X - and
    // giving it a square cell is what would force the whole set to be scaled down to fit its worst
    // axis. The corridor and the corner, both roughly square, share the right column. Each fixture is
    // then scaled to fit its region, keeping the quantities that ARE the measurement fixed: the
    // hump's 0.6 rise/run, the corridor's 300uu width, the agent radius.
    private void DoResolve_Layout()
    {
        const auto SmallestAxis = Math::Min(
            Math::Min(_ExtentPlusX, _ExtentMinusX),
            Math::Min(_ExtentPlusY, _ExtentMinusY));

        if (SmallestAxis < MinBandExtentUu)
        {
            DoTearDown();
            FinishFailure(f"the nav bounds volume over this band bakes only +X={_ExtentPlusX}uu -X={_ExtentMinusX}uu +Y={_ExtentPlusY}uu -Y={_ExtentMinusY}uu, and {MinBandExtentUu}uu on every axis is the floor for a fixture set whose corridor alone is {CorridorHalfWidthUu * 2.0 + WallThicknessUu * 2.0}uu across - widen the volume rather than shrinking the measurement");
            return;
        }

        const auto SafeHalfX = Math::Min(_ExtentPlusX, _ExtentMinusX) - RimMarginUu;
        const auto SafeHalfY = Math::Min(_ExtentPlusY, _ExtentMinusY) - RimMarginUu;

        const auto ColumnHalfX = SafeHalfX * 0.5;
        const auto RowHalfY = SafeHalfY * 0.5;

        // Left column, full height: the ramp. Right column, half height each: corridor then corner.
        const auto RampUseX = ColumnHalfX * CellFillFraction;
        const auto RampUseY = SafeHalfY * CellFillFraction;
        const auto UseX = ColumnHalfX * CellFillFraction;
        const auto UseY = RowHalfY * CellFillFraction;
        const auto UseMin = Math::Min(UseX, UseY);

        _RampCentreX = -ColumnHalfX;
        _RampCentreY = 0.0;
        _CorridorCentreX = ColumnHalfX;
        _CorridorCentreY = -RowHalfY;
        _CornerCentreX = ColumnHalfX;
        _CornerCentreY = RowHalfY;

        // RAMP. The wall's half-span E sets every probe distance: the widest is D12 = E/K12, which
        // must fit the column's full height, and E itself must fit its width.
        _WallHalfSpanUu = Math::Min(RampUseX, DetourK12 * RampUseY);
        _RampProbe12Uu = _WallHalfSpanUu / DetourK12;
        _RampProbe15Uu = _WallHalfSpanUu / DetourK15;
        _RampProbe20Uu = _WallHalfSpanUu / DetourK20;

        // The tightest start is the 2.0x one; it has to clear the ramp's toe, which sits at
        // (plateau + run) from the fixture centre. That inequality is what sizes the hump.
        const auto NaturalHumpHalfYUu = NaturalPlateauHalfUu + NaturalHumpRunUu;
        _HumpScale = Math::Min(1.0, (_RampProbe20Uu - EndpointClearUu) / NaturalHumpHalfYUu);

        if (_HumpScale < MinHumpScale)
        {
            DoTearDown();
            FinishFailure(f"the discovered band (+X={_ExtentPlusX}uu -X={_ExtentMinusX}uu +Y={_ExtentPlusY}uu -Y={_ExtentMinusY}uu) leaves the ramp fixture a wall half-span of {_WallHalfSpanUu}uu, which puts its 2.0x start {_RampProbe20Uu}uu out - closer to the hump than a scale of {MinHumpScale} allows, and a plateau narrower than that carries no walkable polygon after erosion");
            return;
        }

        _HumpRiseUu = NaturalHumpRiseUu * _HumpScale;
        _HumpRunUu = NaturalHumpRunUu * _HumpScale;
        _PlateauHalfUu = NaturalPlateauHalfUu * _HumpScale;
        _RampWidthUu = _PlateauHalfUu * 2.0;

        // CORRIDOR. Its footprint is (leg + 500) on each axis, halved about the cell centre.
        _CorridorLegUu = Math::Clamp(UseMin * 2.0 - (CorridorHalfWidthUu + WallThicknessUu) * 2.0,
            MinCorridorLegUu, NaturalCorridorLegUu);

        if (UseMin * 2.0 - (CorridorHalfWidthUu + WallThicknessUu) * 2.0 < MinCorridorLegUu)
        {
            DoTearDown();
            FinishFailure(f"the discovered band leaves the corridor a {UseX}x{UseY}uu region, and a {CorridorHalfWidthUu * 2.0}uu corridor with a real right-angle bend needs legs of at least {MinCorridorLegUu}uu - widen the volume (+X={_ExtentPlusX}uu -X={_ExtentMinusX}uu +Y={_ExtentPlusY}uu -Y={_ExtentMinusY}uu)");
            return;
        }

        // CORNER. The probes stand CornerStandoffUu diagonally clear of the pillar, so the fixture's
        // half-footprint is pillar half plus that.
        _PillarHalfUu = Math::Clamp(UseMin - CornerStandoffUu, MinPillarHalfUu, NaturalPillarHalfUu);
        _CornerProbeUu = _PillarHalfUu + CornerStandoffUu;

        if (_CornerProbeUu > UseMin)
        {
            DoTearDown();
            FinishFailure(f"the discovered band leaves the corner a {UseX}x{UseY}uu region, and it needs {_CornerProbeUu}uu to stand its probes clear of a {MinPillarHalfUu}uu pillar - widen the volume (+X={_ExtentPlusX}uu -X={_ExtentMinusX}uu +Y={_ExtentPlusY}uu -Y={_ExtentMinusY}uu)");
            return;
        }

        ck::nav::Display(f"[RECAST-BUDGET] layout resolved: safe half-span {SafeHalfX}x{SafeHalfY}uu, ramp takes the left column ({RampUseX}x{RampUseY}uu usable), corridor and corner share the right ({UseX}x{UseY}uu each). humpScale={_HumpScale} rise/run={_HumpRiseUu}/{_HumpRunUu} wallHalfSpan={_WallHalfSpanUu}uu probes={_RampProbe12Uu}/{_RampProbe15Uu}/{_RampProbe20Uu}uu corridorLeg={_CorridorLegUu}uu pillarHalf={_PillarHalfUu}uu cornerProbe={_CornerProbeUu}uu");
    }

    UFUNCTION()
    private void Step_BuildFixtures(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (IsFinished())
        { return; }

        if (DoBuild_RampFixture() == false)
        { return; }

        DoBuild_CorridorFixture();

        DoSpawn_Box(
            Get_FixturePoint(_CornerCentreX, _CornerCentreY, 0.0, 0.0, FloorTopZ + WallHeightUu * 0.5),
            FVector(_PillarHalfUu * 2.0, _PillarHalfUu * 2.0, WallHeightUu),
            FRotator::ZeroRotator);

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        ck::nav::Display(f"[RECAST-BUDGET] staged {_SpawnedActors.Num()} cubes on the band: floor half-span {FloorHalfSpanUu}uu, hump rise/run {_HumpRiseUu}/{_HumpRunUu}, wall half-span {_WallHalfSpanUu}uu, corridor width {CorridorHalfWidthUu * 2.0}uu, pillar half-extent {_PillarHalfUu}uu, agent radius {AgentRadiusUu}uu");
    }

    // A hump the direct route climbs, walled off on both sides so the only alternative is the long
    // way round the wall's end.
    private bool DoBuild_RampFixture()
    {
        DoSpawn_Box(
            Get_FixturePoint(_RampCentreX, _RampCentreY, 0.0, 0.0, FloorTopZ + _HumpRiseUu * 0.5),
            FVector(_PlateauHalfUu * 2.0, _PlateauHalfUu * 2.0, _HumpRiseUu),
            FRotator::ZeroRotator);

        const auto WallSpanUu = _WallHalfSpanUu - _PlateauHalfUu;
        const auto WallCentreX = (_WallHalfSpanUu + _PlateauHalfUu) * 0.5;
        const auto WallSize = FVector(WallSpanUu, WallThicknessUu, WallHeightUu);
        const auto WallZ = FloorTopZ + WallHeightUu * 0.5;

        DoSpawn_Box(Get_FixturePoint(_RampCentreX, _RampCentreY, -WallCentreX, 0.0, WallZ), WallSize, FRotator::ZeroRotator);
        DoSpawn_Box(Get_FixturePoint(_RampCentreX, _RampCentreY,  WallCentreX, 0.0, WallZ), WallSize, FRotator::ZeroRotator);

        // Two mirrored ramps, rolled about X so the slab's local +Y axis is the slope. The slope is
        // the hypotenuse of the rise and the run; the slab is then EXTENDED past its low end by
        // RampBuryUu of vertical drop, so its top face starts BELOW FloorTopZ instead of meeting it
        // on a knife edge and Recast rasterizes a slope continuous with the floor. The high end
        // still lands exactly on the plateau's edge at the hump's rise.
        //
        // Extending one end moves the slab's centre half that distance down-slope, which is what the
        // RampBuryUu * 0.5 in Z and the matching CosSlope term in Y account for. Half the slab's
        // thickness, measured along the slope normal, drops the centre again so the TOP face - the
        // one that bakes - is the surface these numbers describe.
        const auto SlopeLengthUu = FVector(_HumpRunUu, _HumpRiseUu, 0.0).Size();
        const auto SinSlope = _HumpRiseUu / SlopeLengthUu;
        const auto CosSlope = _HumpRunUu / SlopeLengthUu;
        const auto ExtendUu = RampBuryUu / SinSlope;
        const auto SlabLengthUu = SlopeLengthUu + ExtendUu;
        const auto ExpectedClimbUu = _HumpRiseUu + RampBuryUu;

        const auto RampCentreZ = FloorTopZ + _HumpRiseUu * 0.5 - (RampThicknessUu * 0.5) / CosSlope - RampBuryUu * 0.5;
        const auto RampOffsetY = _PlateauHalfUu + _HumpRunUu * 0.5 + ExtendUu * 0.5 * CosSlope;

        return DoSpawn_Ramp(-RampOffsetY, RampCentreZ, SlabLengthUu, ExpectedClimbUu, 1.0)
            && DoSpawn_Ramp( RampOffsetY, RampCentreZ, SlabLengthUu, ExpectedClimbUu, -1.0);
    }

    // InRiseSign is +1 when the slab must climb toward +Y and -1 when it must climb toward -Y.
    // Which roll sign produces each is a property of the engine's rotator convention, so it is
    // DERIVED rather than assumed: the slab is spawned, its own transform is asked where its two
    // ends landed, and the roll is flipped if the answer came back upside down.
    private bool DoSpawn_Ramp(float64 InOffsetY, float64 InCentreZ, float64 InSlabLengthUu, float64 InExpectedClimbUu, float64 InRiseSign)
    {
        auto Ramp = DoSpawn_Box(
            Get_FixturePoint(_RampCentreX, _RampCentreY, 0.0, InOffsetY, InCentreZ),
            FVector(_RampWidthUu, InSlabLengthUu, RampThicknessUu),
            FRotator(0.0, 0.0, HumpRollDeg * InRiseSign));

        if (!System::IsValid(Ramp))
        {
            DoTearDown();
            FinishFailure("staging failed: a ramp slab could not be spawned");
            return false;
        }

        auto RiseUu = Get_RampRise(Ramp);

        if (RiseUu * InRiseSign < 0.0)
        {
            Ramp.SetActorRotation(FRotator(0.0, 0.0, -HumpRollDeg * InRiseSign));
            RiseUu = Get_RampRise(Ramp);
        }

        // The slab's own end-to-end climb has to be the one it was built for. Anything else means
        // the roll did not land where this fixture needs it and the ramp-vs-level question is
        // unanswerable - a staging failure, not a finding about Recast.
        if (Math::Abs(RiseUu * InRiseSign - InExpectedClimbUu) > 5.0)
        {
            DoTearDown();
            FinishFailure(f"staging failed: a ramp slab rolled to an end-to-end climb of {RiseUu}uu where {InExpectedClimbUu * InRiseSign}uu was required - the hump would not bake as connected ground");
            return false;
        }

        return true;
    }

    // FTransform::TransformPosition takes MESH-local coordinates and applies the actor's scale
    // itself, so the slab's two ends are the UNSCALED cube's own +/-Y faces at half the mesh size,
    // not the scaled half-length. Feeding it the scaled length multiplies the scale in twice and
    // reports a climb the slab does not have.
    private float64 Get_RampRise(AStaticMeshActor InRamp) const
    {
        const auto Transform = InRamp.GetActorTransform();
        const auto PlusEnd = Transform.TransformPosition(FVector(0.0, CubeMeshSizeUu * 0.5, 0.0));
        const auto MinusEnd = Transform.TransformPosition(FVector(0.0, -CubeMeshSizeUu * 0.5, 0.0));
        return PlusEnd.Z - MinusEnd.Z;
    }

    // An L of four walls, two outer and two inner, meeting at a right angle. The corridor between
    // them is 2*CorridorHalfWidthUu wide and its centre line runs (0,0) -> (Leg,0) -> (Leg,Leg) in
    // the fixture's local space, whose origin is offset so the L sits centred in its cell.
    private float64 Get_CorridorOriginX() const
    { return _CorridorCentreX - _CorridorLegUu * 0.5; }

    private float64 Get_CorridorOriginY() const
    { return _CorridorCentreY - _CorridorLegUu * 0.5; }

    private void DoBuild_CorridorFixture()
    {
        const auto Half = CorridorHalfWidthUu;
        const auto Leg = _CorridorLegUu;
        const auto Thick = WallThicknessUu;
        const auto OuterEdge = Leg + Half + Thick;

        DoAdd_CorridorWall(-Half - Thick,      -Half - Thick, OuterEdge,   -Half);        // outer, first leg
        DoAdd_CorridorWall(Leg + Half,         -Half - Thick, OuterEdge,   OuterEdge);    // outer, second leg
        DoAdd_CorridorWall(-Half - Thick,      Half,          Leg - Half,  Half + Thick); // inner, first leg
        DoAdd_CorridorWall(Leg - Half - Thick, Half,          Leg - Half,  OuterEdge);    // inner, second leg
    }

    private void DoAdd_CorridorWall(float64 InMinX, float64 InMinY, float64 InMaxX, float64 InMaxY)
    {
        const auto OriginX = Get_CorridorOriginX();
        const auto OriginY = Get_CorridorOriginY();

        const auto WorldMin = Get_FixturePoint(OriginX, OriginY, InMinX, InMinY, FloorTopZ);
        const auto WorldMax = Get_FixturePoint(OriginX, OriginY, InMaxX, InMaxY, FloorTopZ + WallHeightUu);

        _CorridorWallMin.Add(WorldMin);
        _CorridorWallMax.Add(WorldMax);

        DoSpawn_Box(
            FVector((WorldMin.X + WorldMax.X) * 0.5, (WorldMin.Y + WorldMax.Y) * 0.5, FloorTopZ + WallHeightUu * 0.5),
            FVector(WorldMax.X - WorldMin.X, WorldMax.Y - WorldMin.Y, WallHeightUu),
            FRotator::ZeroRotator);
    }

    // All positives, deliberately. "A point buried in a wall must NOT project" reads like the obvious
    // proof that a wall is baked, and it is worthless: a solid cube's flat top bakes as its own
    // walkable island, so a buried probe can snap onto the wall top and answer Success - and a probe
    // narrow enough to miss the top answers the same before the wall exists at all. What separates
    // the two states is a ray that CAN be stopped, so the walls are proven by raycasts that must come
    // back Blocked and the ground by projections that must come back Success.
    UFUNCTION()
    private void Check_FixturesAreLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;

        const auto RampStart12 = Get_RampProbe(_RampProbe12Uu, -1.0);
        const auto RampGoal12 = Get_RampProbe(_RampProbe12Uu, 1.0);
        const auto RampStart20 = Get_RampProbe(_RampProbe20Uu, -1.0);

        const auto RampStart12Flag = Get_ProbeFlag(RampStart12);
        const auto RampGoal12Flag = Get_ProbeFlag(RampGoal12);
        const auto RampStart20Flag = Get_ProbeFlag(RampStart20);
        const auto CorridorStartFlag = Get_ProbeFlag(Get_CorridorStart());
        const auto CorridorGoalFlag = Get_ProbeFlag(Get_CorridorGoal());
        const auto CornerStartFlag = Get_ProbeFlag(Get_CornerStart());
        const auto CornerGoalFlag = Get_ProbeFlag(Get_CornerGoal());

        const auto EndpointScore =
            RampStart12Flag + RampGoal12Flag + RampStart20Flag +
            CorridorStartFlag + CorridorGoalFlag + CornerStartFlag + CornerGoalFlag;

        const auto EndpointsLive = EndpointScore == 7;

        // Each ray runs along the route its fixture is about to be measured on and must be stopped by
        // the geometry that shapes that route. While the floor is baked and the blocks are not, every
        // one of them answers Clear - exactly the state a measurement taken too early would be
        // silently taken in.
        const auto WallProbeX = (_PlateauHalfUu + _WallHalfSpanUu) * 0.5;
        const auto WallProbeY = WallThicknessUu * 0.5 + CorridorHalfWidthUu;

        const auto RampWallLive = Get_RaycastBlocked(
            Get_FixturePoint(_RampCentreX, _RampCentreY, WallProbeX, -WallProbeY, FloorTopZ),
            Get_FixturePoint(_RampCentreX, _RampCentreY, WallProbeX, WallProbeY, FloorTopZ));

        const auto CorridorWallsLive = Get_RaycastBlocked(Get_CorridorStart(), Get_CorridorGoal());
        const auto PillarLive = Get_RaycastBlocked(Get_CornerStart(), Get_CornerGoal());

        const auto AllLive = EndpointsLive && RampWallLive && CorridorWallsLive && PillarLive;

        if (_LivePollCount % LivePollLogInterval == 0)
        {
            // Hoisted, not inlined: a ternary inside an f-string brace collides with the format-spec
            // separator, so the colon would be read as ":0" rather than as the else-branch.
            const auto EndpointFlag = EndpointsLive ? 1 : 0;
            const auto RampWallFlag = RampWallLive ? 1 : 0;
            const auto CorridorWallFlag = CorridorWallsLive ? 1 : 0;
            const auto PillarFlag = PillarLive ? 1 : 0;

            ck::nav::Display(f"[RECAST-BUDGET] waiting on the surface, poll {_LivePollCount}: endpoints={EndpointFlag} ({EndpointScore}/7) rampWall={RampWallFlag} corridorWalls={CorridorWallFlag} pillar={PillarFlag}");
            ck::nav::Display(f"[RECAST-BUDGET] endpoint probes: rampStart12={RampStart12Flag} rampGoal12={RampGoal12Flag} rampStart20={RampStart20Flag} corridorStart={CorridorStartFlag} corridorGoal={CorridorGoalFlag} cornerStart={CornerStartFlag} cornerGoal={CornerGoalFlag}");
        }

        // Once, so a failing probe can be read as a place rather than as a name.
        if (_LivePollCount == 0)
        {
            ck::nav::Display(f"[RECAST-BUDGET] endpoint positions: rampStart12={RampStart12} rampGoal12={RampGoal12} rampStart20={RampStart20}");
            ck::nav::Display(f"[RECAST-BUDGET] endpoint positions: corridorStart={Get_CorridorStart()} corridorGoal={Get_CorridorGoal()} cornerStart={Get_CornerStart()} cornerGoal={Get_CornerGoal()}");
        }

        ++_LivePollCount;

        Res.Set(AllLive);
    }

    //------------------------------------------------------------------------
    // Queries
    //------------------------------------------------------------------------

    private FVector Get_RampProbe(float64 InOffsetUu, float64 InSide) const
    { return Get_FixturePoint(_RampCentreX, _RampCentreY, 0.0, InOffsetUu * InSide, FloorTopZ); }

    private FVector Get_CorridorStart() const
    { return Get_FixturePoint(Get_CorridorOriginX(), Get_CorridorOriginY(), 0.0, 0.0, FloorTopZ); }

    private FVector Get_CorridorGoal() const
    { return Get_FixturePoint(Get_CorridorOriginX(), Get_CorridorOriginY(), _CorridorLegUu, _CorridorLegUu - CorridorHalfWidthUu, FloorTopZ); }

    private FVector Get_CornerStart() const
    { return Get_FixturePoint(_CornerCentreX, _CornerCentreY, -_CornerProbeUu, -_CornerProbeUu, FloorTopZ); }

    private FVector Get_CornerGoal() const
    { return Get_FixturePoint(_CornerCentreX, _CornerCentreY, _CornerProbeUu, _CornerProbeUu, FloorTopZ); }

    // A fresh requester per query: the status slot then starts at None, so every wait below is a
    // genuine transition rather than a value already true on arrival. The requester is a child of
    // this test's entity, so the harness's subtree teardown reclaims it.
    private void DoIssue_Query(FString InLabel, FVector InStart, FVector InGoal)
    {
        _QueryLabel = InLabel;
        _QueryStart = InStart;
        _QueryGoal = InGoal;

        _Requester = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        utils_transform::Add(_Requester,
            FTransform(FRotator::ZeroRotator, InStart, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Partial paths off: a route that does not exist must report Failed rather than hand back a
        // truncated polyline that would be measured as though it were the answer.
        auto Request = FCk_Request_Nav_FindPath(InGoal);
        Request.Set_AllowPartialPath(false);

        utils_nav::Request_FindPath(_Requester, Request);
    }

    UFUNCTION()
    private void Check_QuerySettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto Status = utils_nav::Get_PathStatus(_Requester);
        Res.Set(Status == ECk_Nav_PathStatus::Ready || Status == ECk_Nav_PathStatus::Failed);
    }

    UFUNCTION()
    private void Step_QueryRamp12(FCk_Handle InHandle, FInstancedStruct InPayload)
    { DoIssue_Query("1.2", Get_RampProbe(_RampProbe12Uu, -1.0), Get_RampProbe(_RampProbe12Uu, 1.0)); }

    UFUNCTION()
    private void Step_QueryRamp15(FCk_Handle InHandle, FInstancedStruct InPayload)
    { DoIssue_Query("1.5", Get_RampProbe(_RampProbe15Uu, -1.0), Get_RampProbe(_RampProbe15Uu, 1.0)); }

    UFUNCTION()
    private void Step_QueryRamp20(FCk_Handle InHandle, FInstancedStruct InPayload)
    { DoIssue_Query("2.0", Get_RampProbe(_RampProbe20Uu, -1.0), Get_RampProbe(_RampProbe20Uu, 1.0)); }

    UFUNCTION()
    private void Step_QueryCorridor(FCk_Handle InHandle, FInstancedStruct InPayload)
    { DoIssue_Query("corridor", Get_CorridorStart(), Get_CorridorGoal()); }

    UFUNCTION()
    private void Step_QueryCorner(FCk_Handle InHandle, FInstancedStruct InPayload)
    { DoIssue_Query("corner", Get_CornerStart(), Get_CornerGoal()); }

    // Every record step opens with this, so a failed route names itself instead of being measured.
    private bool DoAssert_RouteExists(const FCk_Nav_PathResult& InResult)
    {
        const auto Count = InResult.Get_Waypoints().Num();
        const auto RouteExists = InResult.Get_Status() == ECk_Nav_PathStatus::Ready && Count > 0;

        Assert_True(RouteExists,
            f"the '{_QueryLabel}' fixture must produce a Ready path carrying waypoints - got status {InResult.Get_Status()} with {Count} waypoints, reason {InResult.Get_Diagnostics().Get_LastFailReason()}");

        return RouteExists;
    }

    // The extracted waypoints drop the start, so the polyline this measures runs from the query's
    // own start point through them.
    private float64 Get_PlanarLength(const TArray<FVector>& InWaypoints) const
    {
        auto Length = 0.0;
        auto Previous = _QueryStart;

        for (auto Waypoint : InWaypoints)
        {
            auto Step = Waypoint - Previous;
            Step.Z = 0.0;
            Length += Step.Size();
            Previous = Waypoint;
        }

        return Length;
    }

    //------------------------------------------------------------------------
    // Recording
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RecordRamp(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_nav::Get_PathResult(_Requester);
        if (DoAssert_RouteExists(Result) == false)
        { return; }

        const auto Waypoints = Result.Get_Waypoints();

        auto MaxWaypointZ = FloorTopZ;
        auto MaxLateralUu = 0.0;

        for (auto Waypoint : Waypoints)
        {
            MaxWaypointZ = Math::Max(MaxWaypointZ, Waypoint.Z);
            MaxLateralUu = Math::Max(MaxLateralUu, Math::Abs(Waypoint.X - _RampCentreX));
        }

        const auto ProbeUu = Math::Abs(_QueryGoal.Y - (BandY + _RampCentreY));
        const auto HumpEstimateUu = ProbeUu * 2.0;
        const auto DetourEstimateUu = FVector(ProbeUu, _WallHalfSpanUu, 0.0).Size() * 2.0;

        // A route that stayed inside the hump's own width went over it; one that reached out toward
        // the wall's end went round. Read in preference to waypoint Z, because a funnel crossing the
        // hump in a straight line can legitimately emit no waypoint on the plateau at all.
        const auto LateralThresholdUu = (_PlateauHalfUu + _WallHalfSpanUu) * 0.5;
        const auto RouteName = MaxLateralUu < LateralThresholdUu ? "over-the-hump" : "around-the-wall";
        const auto MeasuredUu = Get_PlanarLength(Waypoints);

        ck::nav::Display(f"[RECAST-BUDGET] slope choice at detour {_QueryLabel}x: route={RouteName} riseOverRun={_HumpRiseUu / _HumpRunUu} maxWaypointZ={MaxWaypointZ}uu maxLateral={MaxLateralUu}uu planarLength={MeasuredUu}uu humpEstimate={HumpEstimateUu}uu detourEstimate={DetourEstimateUu}uu waypoints={Waypoints.Num()}");
    }

    UFUNCTION()
    private void Step_RecordCorridor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_nav::Get_PathResult(_Requester);
        if (DoAssert_RouteExists(Result) == false)
        { return; }

        const auto Waypoints = Result.Get_Waypoints();

        // The centre line in world space: one segment down each leg, meeting at the bend.
        const auto OriginX = Get_CorridorOriginX();
        const auto OriginY = Get_CorridorOriginY();
        const auto Bend = Get_FixturePoint(OriginX, OriginY, _CorridorLegUu, 0.0, FloorTopZ);
        const auto CentreEnd = Get_FixturePoint(OriginX, OriginY, _CorridorLegUu, _CorridorLegUu, FloorTopZ);

        auto MinWallUu = -1.0;
        auto MinCentreUu = -1.0;
        auto SumWallUu = 0.0;
        auto SumCentreUu = 0.0;
        auto Index = 0;

        for (auto Waypoint : Waypoints)
        {
            auto WallUu = -1.0;
            for (auto WallIndex = 0; WallIndex < _CorridorWallMin.Num(); ++WallIndex)
            {
                const auto Candidate = Get_Distance2D_PointToBox(Waypoint, _CorridorWallMin[WallIndex], _CorridorWallMax[WallIndex]);
                if (WallUu < 0.0 || Candidate < WallUu)
                { WallUu = Candidate; }
            }

            const auto CentreUu = Math::Min(
                Get_Distance2D_PointToSegment(Waypoint, Get_CorridorStart(), Bend),
                Get_Distance2D_PointToSegment(Waypoint, Bend, CentreEnd));

            ck::nav::Display(f"[RECAST-BUDGET] corridor waypoint {Index}: wallDistance={WallUu}uu centreLineDistance={CentreUu}uu at {Waypoint}");

            if (MinWallUu < 0.0 || WallUu < MinWallUu)
            { MinWallUu = WallUu; }

            if (MinCentreUu < 0.0 || CentreUu < MinCentreUu)
            { MinCentreUu = CentreUu; }

            SumWallUu += WallUu;
            SumCentreUu += CentreUu;
            ++Index;
        }

        const auto Count = float64(Waypoints.Num());

        ck::nav::Display(f"[RECAST-BUDGET] corridor clearance over {Waypoints.Num()} waypoints in a {CorridorHalfWidthUu * 2.0}uu corridor with one right-angle bend (leg {_CorridorLegUu}uu): minWall={MinWallUu}uu meanWall={SumWallUu / Count}uu minCentreLine={MinCentreUu}uu meanCentreLine={SumCentreUu / Count}uu agentRadius={AgentRadiusUu}uu minWallInRadii={MinWallUu / AgentRadiusUu}");
    }

    UFUNCTION()
    private void Step_RecordCorner(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Result = utils_nav::Get_PathResult(_Requester);
        if (DoAssert_RouteExists(Result) == false)
        { return; }

        const auto Waypoints = Result.Get_Waypoints();

        // All four vertices, not the two the diagonal is expected to favour: which corner the route
        // rounds is Recast's choice on a symmetric fixture, and the measurement should not presume it.
        auto Vertices = TArray<FVector>();
        Vertices.Add(Get_FixturePoint(_CornerCentreX, _CornerCentreY, -_PillarHalfUu, -_PillarHalfUu, FloorTopZ));
        Vertices.Add(Get_FixturePoint(_CornerCentreX, _CornerCentreY,  _PillarHalfUu, -_PillarHalfUu, FloorTopZ));
        Vertices.Add(Get_FixturePoint(_CornerCentreX, _CornerCentreY,  _PillarHalfUu,  _PillarHalfUu, FloorTopZ));
        Vertices.Add(Get_FixturePoint(_CornerCentreX, _CornerCentreY, -_PillarHalfUu,  _PillarHalfUu, FloorTopZ));

        auto BestUu = -1.0;
        auto BestVertex = 0;
        auto BestWaypoint = 0;
        auto Index = 0;

        for (auto Waypoint : Waypoints)
        {
            for (auto VertexIndex = 0; VertexIndex < Vertices.Num(); ++VertexIndex)
            {
                auto Delta = Waypoint - Vertices[VertexIndex];
                Delta.Z = 0.0;

                const auto Candidate = Delta.Size();
                if (BestUu < 0.0 || Candidate < BestUu)
                {
                    BestUu = Candidate;
                    BestVertex = VertexIndex;
                    BestWaypoint = Index;
                }
            }
            ++Index;
        }

        const auto MeasuredUu = Get_PlanarLength(Waypoints);

        ck::nav::Display(f"[RECAST-BUDGET] corner offset: waypoint {BestWaypoint} of {Waypoints.Num()} sits {BestUu}uu from pillar vertex {BestVertex}, i.e. {BestUu / AgentRadiusUu} x agentRadius ({AgentRadiusUu}uu) - pillar half-extent {_PillarHalfUu}uu, planarLength={MeasuredUu}uu");

        // The shipping path's own value for the same knob, so the two sit side by side in one log.
        ck::nav::Display("[RECAST-BUDGET] corner offset applied by the shipping path: 0uu - FProcessor_Nav_HandleRequests passes InCornerOffsetDistance 0 (CkNav_Processor.cpp:446), so OffsetFromCorners is skipped and the number above is raw Recast corridor geometry after agent-radius erosion");
    }

    // Teardown - the PIE world is shared, so nothing spawned here outlives the test

    UFUNCTION()
    private void Step_TearDown(FCk_Handle InHandle, FInstancedStruct InPayload)
    { DoTearDown(); }

    private void DoTearDown()
    {
        if (ck::IsValid(_Requester) && utils_nav::Has_Path(_Requester))
        { utils_nav::Request_AbandonPath(_Requester, FCk_Request_Nav_AbandonPath(1)); }

        for (auto Actor : _SpawnedActors)
        {
            if (!System::IsValid(Actor))
            { continue; }

            utils_nav::Request_SetActorNavigationRegistered(Actor, false);
            Actor.DestroyActor();
        }

        _SpawnedActors.Reset();
        _CorridorWallMin.Reset();
        _CorridorWallMax.Reset();

        // The requester entities are children of this test's own entity, so the harness's subtree
        // teardown takes them; the tiles the cubes dirtied are what has to be handed back here.
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }
}
