// Language=angelscript

//============================================================================
// CK GROUND NAV - AUTOMATION TEST: SETTLED IMPLIES LIVE, ON THE SHARED FLOOR
//============================================================================
//
// Two things are pinned here, and the second is the reason the first is worth
// pinning.
//
//   1. THE SHARED LEVEL'S ORIGIN FLOOR BAKES ON GROUNDNAV AT ALL. This bakes
//      over StaticMeshActor_1 rather than over a slab it staged itself, so it
//      also answers whether that asset's collision is CLOSED. GroundNav bakes
//      from the Jolt static world and sees faces only: a slab with no underside
//      presents nothing in the columns beneath it and bakes as OPEN GROUND, and
//      the bake says so once per build through ck::groundnav::Warning. The
//      AutoTest harness escalates a Warning into a failure, and NOTHING here
//      suppresses it. A run that comes back red on an OPEN COLLISION warning is
//      this test doing its job - the finding is about the level asset, not about
//      the fixture and not about GroundNav.
//
//   2. SETTLED IMPLIES LIVE. utils_nav_surface::Get_IsSurfaceSettled is the one
//      named condition a caller should need after ANY surface mutation - a
//      provider switch, a paint, a release, a rebuild. The claim it makes is
//      strictly stronger than Get_IsMarkupLive: a settled surface has nothing in
//      flight and nothing pending, so every paint requested before the kick must
//      ALREADY be applied at the first poll that answers settled. This test
//      therefore waits on SETTLED and never on live, and then reads liveness
//      with no further wait at all.
//
//----------------------------------------------------------------------------
// WHY THE HOLE IS THE DISCRIMINATING ASSERTION, AND WHY IT COMES FIRST
//----------------------------------------------------------------------------
//
// ck.GroundNav.Debug.MarkupLiveGate 0 forces Get_IsMarkupLive true without
// asking the field. Under that bypass the liveAtSettled assertion is satisfied
// trivially and proves nothing whatsoever. holeAtSettled - a tight-extent
// projection at the painted spot FAILING at that same moment - reads the baked
// field rather than the liveness flag, and no bypass can make it pass over a
// surface the paint has not reached. That is why the hole is asserted FIRST in
// step 4: the assertion that can actually fail under the bypass runs before the
// one that cannot, so a red run names the real condition.
//
// The honest failure mode of this shape is worth stating too. If the settle
// query answered true on its FIRST poll after a paint - before the markup's own
// deferral had even dirtied the surface - then "settled implies live" would be
// vacuous. It would not pass vacuously: holeAtSettled would read false and this
// test would go red naming the projection. A settle that resolves before the
// mutation it was kicked for is exactly the defect this shape surfaces.
//
//----------------------------------------------------------------------------
// EVERY WAIT IS A NAMED CONDITION
//----------------------------------------------------------------------------
//
// There is no WaitOneFrame and no frame-count wait anywhere in this file. How
// many passes a bake, a repair or a publish needs is a property of the probe
// budget and of processor ordering; a hop count would bake a guess in and read
// as a defect the moment either changed. Every budget below is a CEILING on a
// named condition, so a wait that expires names the step and the condition that
// were pending rather than dying as the harness's anonymous TimesUp.
//
// The settle counters are LOGGED and never asserted against, for the same
// reason: how long a surface takes to go quiet is a measurement, not a contract.
//
//----------------------------------------------------------------------------
// FIXTURE AND WORLD STATE
//----------------------------------------------------------------------------
//
// FCkAutoTest_GroundNavFixture stages the volume over the level's origin floor,
// pushing that floor into the Jolt static world only if nothing else already
// had, and releases both on every exit path. It deliberately does NOT touch the
// provider: the provider is a WORLD selection every later fixture in this map
// reads, so this test captures the previous value before the swap and hands it
// back both when it concludes AND in DoEndPlay - the engine TimeLimit path never
// runs the finish path.
//
// The spot is the origin floor at (300, 300) on the floor's own top face, well
// inside the field and far from its perimeter.
//============================================================================

class UCk_AutoTest_GroundNav_Settle_PaintThenSettleThenLive : UCk_AutoTest_Base
{
    // A 16-tile bake of the origin floor plus three kicked settles, each with its own budgeted
    // condition. Deliberately slack: a contract that expires on the harness's anonymous TimesUp
    // names nothing.
    default _TimeoutSeconds = 240.0f;

    //------------------------------------------------------------------------
    // The spot, and the probe that can tell a hole from ground
    //------------------------------------------------------------------------

    // Offsets from the floor's own centre rather than world absolutes: the shared level's origin
    // floor is centred on the origin with its top face at Z 0, so this resolves to (300, 300, 0) -
    // but it resolves to a point ON THE FLOOR whatever that asset's transform turns out to be.
    private const float SpotOffsetX = 300.0;
    private const float SpotOffsetY = 300.0;

    private const float BlockHalfXY = 150.0;
    private const float BlockHalfZ = 200.0;

    // Tighter than the hole a 300uu box leaves, so a probe inside the carve has nothing beside it
    // to snap to. The vertical half-extent stays well under the box height, so nothing baked above
    // the carve is ever mistaken for floor.
    private const FVector ProbeHalfExtents = FVector(60.0, 60.0, 80.0);

    //------------------------------------------------------------------------
    // Budgets - every one is a ceiling on a NAMED condition, never a settle.
    //
    // The origin floor spans roughly +/-1500 and the field covers the level's
    // +/-1000 navmesh bounds; at 500uu tiles that is a 4x4 lattice, and at the default probe
    // budget it bakes in a handful of frames. The build ceiling stands at some
    // hundreds of times that on purpose - it is the ONE wait in this file that
    // covers an unmeasured asset, and a fixture that starved its own bake would
    // report an open-collision finding it never actually reached.
    //------------------------------------------------------------------------

    private const int32 BuildFrameBudget = 7200;
    private const int32 SurfaceFrameBudget = 1800;
    private const int32 SettleFrameBudget = 3600;

    //------------------------------------------------------------------------
    // Fixture
    //------------------------------------------------------------------------

    private FCkAutoTest_GroundNavFixture _Field;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_NavSurfaceMarkup _Markup;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;

    //------------------------------------------------------------------------
    // Samples, every one taken at the FIRST poll that answers settled and never
    // overwritten. What the pin is about is the state of the surface at the
    // moment the wait let go, not at the moment the next step read it out.
    //------------------------------------------------------------------------

    private bool _PaintSampled = false;
    private bool _LiveAtSettled = false;
    private bool _HoleAtSettled = false;
    private int32 _PaintSettledFrames = -1;

    private bool _ReleaseSampled = false;
    private bool _ProjectsAtSettled = false;
    private int32 _ReleaseSettledFrames = -1;

    private bool _RebuildSampled = false;
    private bool _ProjectsAfterRebuild = false;
    private int32 _RebuildSettledFrames = -1;
    private int64 _RevisionBeforeRebuild = -1;
    private int64 _RevisionAfterRebuild = -1;

    //------------------------------------------------------------------------
    // Reporting state
    //------------------------------------------------------------------------

    private FString _Verdict = "incomplete";
    private bool _Reported = false;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        Add_Step(          "stage a GroundNav field over the origin floor",         n"Step_StageField");
        Add_Step_WaitUntil("the origin field reports itself built",                 n"Check_OriginFieldBuilt",    BuildFrameBudget);
        Add_Step(          "switch the world onto GroundNav",                       n"Step_SwitchProvider");
        Add_Step_WaitUntil("the surface settles after the provider switch",         n"Check_SurfaceSettled",      SurfaceFrameBudget);
        Add_Step(          "the spot projects on bare floor",                       n"Step_AssertSpotProjects");
        Add_Step(          "paint the spot and kick the settle counter",            n"Step_PaintAndKick");
        Add_Step_WaitUntil("the surface settles after the paint",                   n"Check_SettledAfterPaint",   SettleFrameBudget);
        Add_Step(          "the paint was already live and the hole already cut",   n"Step_AssertPaintLiveAtSettle");
        Add_Step(          "drop the markup and kick the settle counter",           n"Step_ReleaseAndKick");
        Add_Step_WaitUntil("the surface settles after the release",                 n"Check_SettledAfterRelease", SettleFrameBudget);
        Add_Step(          "the spot projects again the moment it settled",         n"Step_AssertProjectsAtSettle");
        Add_Step(          "kick a rebuild and the settle counter",                 n"Step_RebuildAndKick");
        Add_Step_WaitUntil("the surface settles after the rebuild",                 n"Check_SettledAfterRebuild", SettleFrameBudget);
        Add_Step(          "the rebuild advanced the revision and kept the ground", n"Step_AssertRebuild");
        Add_Step(          "hand the world back",                                   n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging - the fixture owns the field, this test owns the provider
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_StageField(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (_Field.Request_StageOriginField(_SelfHandle) == false)
        { FinishFailure(_Field.Get_StagingError()); }
    }

    // The fixture exposes predicate BODIES, not UFUNCTIONs: Do_EvaluatePredicate binds the named
    // predicate against THIS object, so every wait below needs its own one-line forwarder here.
    UFUNCTION()
    private void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_OriginFieldBuilt(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_SwitchProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Kicked before the mutation, so the number reported afterwards measures THIS switch rather
        // than every poll since staging.
        _Field.Request_KickSettleCount();

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"the world must report the provider it was told to answer on (got {ProviderNow})");
    }

    UFUNCTION()
    private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);
    }

    UFUNCTION()
    private void Step_AssertSpotProjects(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _Field.Get_SettledFrames();
        const auto Spot = Get_SpotCentre();
        const auto ProbeReachUu = ProbeHalfExtents.X;

        ck::nav::Display(f"[GROUNDNAV-SETTLE] switch: settledFrames={Frames} spot={Spot}");

        // The POSITIVE the whole file rests on: without ground here to begin with, the hole asserted
        // after the paint would be indistinguishable from a field that never carried the floor at
        // all, and every assertion downstream would be about nothing.
        Assert_True(Get_SpotProjects(),
            f"the origin floor is baked and the world answers on GroundNav, so a projection at the spot with {ProbeReachUu}uu search half-extents must find ground. It found none, which means the field carries no walkable ground where the level floor stands - the bake saw no closed body beneath the spot, or the field never covered it.");
    }

    //------------------------------------------------------------------------
    // The paint - settled implies live
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_PaintAndKick(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(BlockHalfXY, BlockHalfXY, BlockHalfZ))),
            FGameplayTag());
        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_SpotCentre(), FVector::OneVector));

        _Markup = utils_nav_surface::Request_ImpassableBox(Request);

        Assert_True(ck::IsValid(_Markup),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints the carve on
        // every exit path, including the engine TimeLimit one.
        Track_ForCleanup(FCk_Handle(_Markup));

        _Field.Request_KickSettleCount();
    }

    // The wait is on SETTLED and on nothing else. Liveness and the hole are SAMPLED here, at the
    // first poll that answers settled, precisely because the claim under test is that no further
    // wait is owed once the surface is quiet.
    UFUNCTION()
    private void Check_SettledAfterPaint(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_PaintSampled)
        { return; }

        _PaintSampled = true;
        _LiveAtSettled = utils_nav_surface::Get_IsMarkupLive(_Markup);
        _HoleAtSettled = !Get_SpotProjects();
        _PaintSettledFrames = _Field.Get_SettledFrames();
    }

    UFUNCTION()
    private void Step_AssertPaintLiveAtSettle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _PaintSettledFrames;
        const auto Live = _LiveAtSettled;
        const auto Hole = _HoleAtSettled;
        const auto ProbeReachUu = ProbeHalfExtents.X;

        ck::nav::Display(f"[GROUNDNAV-SETTLE] paint: settledFrames={Frames} liveAtSettled={Live} holeAtSettled={Hole}");

        // FIRST, and deliberately so - see the header. This reads the BAKED FIELD, so it is the one
        // assertion of the two that ck.GroundNav.Debug.MarkupLiveGate 0 cannot make pass.
        Assert_True(Hole,
            f"the surface reported itself SETTLED after the paint, so the paint must already be applied to the field it publishes - yet a projection at the painted spot with {ProbeReachUu}uu search half-extents still found ground. Settled means nothing in flight and nothing pending, so either the settle resolved before the markup deferral had dirtied the surface, or a settled surface can publish ground a live record has already carved.");

        // Second, because a forced-live gate satisfies it without asking the field. It still earns
        // its place: with the hole cut and liveness false, the facade would be under-reporting a
        // paint the field has demonstrably applied.
        Assert_True(Live,
            "the surface reported itself SETTLED after the paint, so Get_IsMarkupLive must ALREADY answer true at that same moment with no further wait - a caller told the surface is quiet has been told the strictly stronger thing, and a paint still reading not-live there makes settled the weaker condition of the two");
    }

    //------------------------------------------------------------------------
    // The release
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_ReleaseAndKick(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        if (ck::IsValid(_Markup))
        { utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup)); }

        _Markup = FCk_Handle_NavSurfaceMarkup();

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void Check_SettledAfterRelease(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_ReleaseSampled)
        { return; }

        _ReleaseSampled = true;
        _ProjectsAtSettled = Get_SpotProjects();
        _ReleaseSettledFrames = _Field.Get_SettledFrames();
    }

    UFUNCTION()
    private void Step_AssertProjectsAtSettle(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _ReleaseSettledFrames;
        const auto Projects = _ProjectsAtSettled;

        ck::nav::Display(f"[GROUNDNAV-SETTLE] release: settledFrames={Frames} projectsAtSettled={Projects}");

        Assert_True(Projects,
            "releasing a walkability record owes the same repair that painting it did, and the surface reported itself SETTLED across that release - so the ground must already be back at that same moment. It was not, which means a settled surface can still publish a hole cut by a record that no longer exists.");
    }

    //------------------------------------------------------------------------
    // The rebuild
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_RebuildAndKick(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevisionBeforeRebuild = utils_nav_surface::Get_SurfaceRevision();

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        _Field.Request_KickSettleCount();
    }

    UFUNCTION()
    private void Check_SettledAfterRebuild(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload);

        if (utils_shared_bool::Get(OutResult) == false)
        { return; }

        if (_RebuildSampled)
        { return; }

        _RebuildSampled = true;
        _RevisionAfterRebuild = utils_nav_surface::Get_SurfaceRevision();
        _ProjectsAfterRebuild = Get_SpotProjects();
        _RebuildSettledFrames = _Field.Get_SettledFrames();
    }

    UFUNCTION()
    private void Step_AssertRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Frames = _RebuildSettledFrames;
        const auto Before = _RevisionBeforeRebuild;
        const auto After = _RevisionAfterRebuild;
        const auto Projects = _ProjectsAfterRebuild;

        ck::nav::Display(f"[GROUNDNAV-SETTLE] rebuild: settledFrames={Frames} revisionBefore={Before} revisionAfter={After}");

        // The POSITIVE that makes the ground assertion below worth making: over a rebuild that never
        // happened, the spot would of course still project.
        Assert_True(After > Before,
            f"a requested rebuild republishes the surface, so the revision has to advance across the kick - and the surface reported itself SETTLED afterwards, so the republish had already landed by the time this was read (was {Before}, now {After})");

        Assert_True(Projects,
            "a rebuild over unchanged geometry must publish the same ground it started with, so the spot has to project the moment the surface settles again. A rebuild that loses the floor is the failure mode this asserts against.");
    }

    //------------------------------------------------------------------------
    // The spot, and the probe the carve can actually move
    //------------------------------------------------------------------------

    // Valid only after staging - the floor readers answer off the actor the fixture resolved.
    private FVector Get_SpotCentre()
    {
        const auto Centre = _Field.Get_FloorCentre();

        return FVector(Centre.X + SpotOffsetX, Centre.Y + SpotOffsetY, _Field.Get_FloorTopZ());
    }

    // Search half-extents tighter than the hole, so a point inside the carve has nothing beside it
    // to snap to and a carved spot cannot answer Success off neighbouring ground.
    private bool Get_SpotProjects()
    {
        auto Query = FCk_NavSurface_ProjectionQuery(Get_SpotCentre());
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query).Get_Status()
            == ECk_NavSurface_QueryStatus::Success;
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Verdict = "green";

        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. Two things here outlive this
    // test's own subtree: the provider is a WORLD selection every later fixture in this map reads,
    // and the fixture's field - plus any floor body it pushed into the Jolt static world - would
    // otherwise stay staged for the rest of the lane.
    //
    // The crossover line is emitted BEFORE the provider is handed back, so it records the provider
    // the test actually ran on. A TimeLimit exit reaches here with the verdict still "incomplete",
    // which is the honest reading of a run that never got to the end.
    private void Teardown()
    {
        if (_Reported == false)
        {
            _Reported = true;
            _Field.Do_ReportCrossover("Settle_PaintThenSettleThenLive", _Verdict);
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_Markup))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Markup));
            _Markup = FCk_Handle_NavSurfaceMarkup();
        }

        _Field.Request_ReleaseOriginField();
    }
}
