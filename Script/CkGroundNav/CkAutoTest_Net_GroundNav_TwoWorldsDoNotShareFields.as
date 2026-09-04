// Language=angelscript

//============================================================================
// CK GROUND NAV - NET AUTOMATION TEST: TWO WORLDS DO NOT SHARE FIELDS
//============================================================================
//
// The multi-PIE half of the per-world isolation contract. The Layer-1 pins in
// Test_GroundNav_MultiWorld.cpp already hold the property hermetically against
// two bare UWorlds; this one holds it where it actually has to be true - two
// live PIE worlds, each with its own Jolt static world, its own GroundNav
// volume, its own provider selection and its own published surface, ticking
// side by side in one process.
//
// The three maps that make this a real question are all process-wide statics
// keyed by TWeakObjectPtr<UWorld>: the GroundNav world-field registry
// (CkGroundNav_WorldFieldRegistry.cpp) and the provider table's two mirrors
// (CkNavSurface_ProviderTable.cpp). A single-world test cannot tell a per-world
// map from a global one - every read returns what the only writer wrote either
// way.
//
// NOTHING REPLICATES HERE. No state crosses the two worlds by design; the
// NetSubject exists only so each body can read a real net role off a replicated
// handle (CkAutoTest_NetBase.as:20-37, and the trap
// CkAutoTest_Net_DeferredQueue_PerWorldIsolation documents:
// utils_net::Get_HasAuthority(InHandle) is TRUE on the client too, because the
// harness spawns the test entity locally in every world).
//
// WHAT EACH WORLD PROVES, on its own Y band - server 140000, client 142000
// (136000/138000 belong to the Repair_* pins; the two bands here are 2000uu
// apart, so a 1000uu gap separates the two volumes' outermost faces):
//
//   1. its own field is real - a tight-extent projection at its own paint spot
//      SUCCEEDS on bare floor;
//   2. its published surface is its own - Get_SurfaceBounds never meets the
//      other world's band;
//   3. its own paint is real - the same projection FAILS once its markup is
//      live, and its own surface revision advanced across the paint;
//   4. the other world's paint is not its - its revision is UNMOVED across the
//      window in which the other world paints;
//   5. the other world's ground is not its - a projection at the other band's
//      off-carve spot FAILS here, while the mirror probe on its OWN band at the
//      same offset SUCCEEDS;
//   6. the other world's repairs are not its - OnSurfaceRebuilt never delivered
//      a changed-bounds box meeting the other band.
//
// HOW THE TWO WORLDS ARE ORDERED. The net harness offers no cross-world
// coordination primitive and this test replicates nothing, so there is no signal
// one world could send the other. What both worlds DO share is the wall clock:
// FCk_Latent_RunAsTestOnAllWorlds spawns every world's body in a single pass
// over the PIE worlds, so the bodies start within a frame or two of each other
// and a schedule of CkTimers armed in DoBeginPlay is a genuine ordering device.
// Same reasoning, and the same tool, as the 7s horizon timers in
// CkAutoTest_Net_DeferredQueue_PerWorldIsolation.
//
//   T=0    both worlds stage a slab, bake a volume, select GroundNav, settle.
//   T=6s   GATE A. Both sample their revision. The SERVER paints.
//   T=12s  GATE B. Both sample again. The server's paint lies inside [A,B], so
//          the CLIENT's sample pair brackets it - unmoved is the assertion.
//          The CLIENT paints.
//   T=18s  GATE C. Both sample a third time. The client's paint lies inside
//          [B,C], so the SERVER's pair brackets it - unmoved again, and the
//          server re-reads its own carve to prove that the other world
//          finishing left its field exactly where it was.
//
// THE SCHEDULE IS CHECKED, NOT ASSUMED. Every phase records whether the gate it
// had to beat had already elapsed when it finished, and asserts it had not:
// staging must land before gate A, the server's markup must go live and its
// repair go quiet before gate B, the client's before gate C. A run whose PIE
// worlds were too slow for the windows fails naming the phase that overran,
// rather than passing on a bracket that never bracketed anything.
//
// WHY THE GATE WAITS CARRY HUGE POLL BUDGETS. A wait budget counts POLLS, and
// polls-per-second is whatever the automation lane's frame rate happens to be -
// which under -nullrhi is not 60. The real ceiling on a gate wait is the
// sequencer's own wall-clock deadline (_TimeoutSeconds * 0.9), so the poll
// budgets here are set past any plausible frame rate rather than encoding one.
//
// THE HARNESS DEADLINE IS 30 SECONDS AND IT IS NOT NEGOTIABLE. The net stub
// generator HARDCODES kTimeoutSeconds = 30.0f for FCk_Latent_RunAsTestOnAllWorlds
// (CkAutoTestNetStubGenerator.cpp:228) - it does NOT read _TimeoutSeconds off the
// CDO the way the PIE wrapper generator does. Everything above therefore has to
// fit inside it, which is why the volume is a 2x2 lattice baked at the default
// probe budget (a build that lands in a tick) rather than the sliced 5x5 the
// Repair_* pins bake, and why the gates sit at 6/12/18s.
//
// PROVIDER RESTORE. The provider is a per-world selection every later consumer
// in that world reads, so the previous one is captured before anything can fail
// and handed back on every exit path - the conclusion, DoEndPlay, and the
// harness's own TimeLimit. OnSurfaceRebuilt is a WORLD signal, so the same
// teardown unbinds it.
//============================================================================

class UCk_AutoTest_Net_GroundNav_TwoWorldsDoNotShareFields : UCk_AutoTest_NetBase
{
    // Gate C lands at 18s and the tail is a handful of steps, so the sequencer's
    // own deadline (0.9 * 26 = 23.4s) fires with room to spare and still well
    // inside the harness's hard 30s.
    default _TimeoutSeconds = 26.0f;

    // The default 240 polls is ~4s at 60fps - far short of an 18s gate, and the
    // lane's actual frame rate is not 60. See the header.
    default _DefaultWaitFrameBudget = 6000;

    //------------------------------------------------------------------------
    // Bands - one per world, and each world stages only its own
    //------------------------------------------------------------------------

    private const float ServerBandY = 140000.0;
    private const float ClientBandY = 142000.0;

    //------------------------------------------------------------------------
    // Fixture geometry - a 2x2 lattice at 500uu tiles, the smallest field that
    // still exercises the seam derivation. Taken from
    // CkAutoTest_GroundNav_VolumeBakesThroughARequest, the cheapest bake in the
    // corpus: cost is the binding constraint here, not coverage.
    //------------------------------------------------------------------------

    private const float VolumeHalfX = 500.0;
    private const float VolumeHalfY = 500.0;
    private const float VolumeHalfZ = 200.0;

    // Overhangs the volume by 200uu on every horizontal side, so the volume's
    // interior never contains a slab edge for the ledge filter to find.
    private const float SlabHalfX = 700.0;
    private const float SlabHalfY = 700.0;
    private const float SlabHalfZ = 50.0;

    private const float SurfaceZ = 0.0;

    private const float CellSizeUu = 25.0;
    private const float CellHeightUu = 10.0;
    private const float TileSizeUu = 500.0;
    private const int32 TileCountTotal = 4;

    private const float AgentRadius = 20.0;
    private const float ProfileHalfHeightUu = 70.0;

    // The paint: an impassable box on the volume centre.
    private const float PaintHalfXY = 150.0;
    private const float PaintHalfZ = 200.0;

    // Tighter than the hole a 300uu box leaves, so a probe inside the carve has
    // nothing beside it to snap to. The same numbers the Repair_* pins use.
    private const FVector ProbeHalfExtents = FVector(60.0, 60.0, 80.0);

    // The off-carve probe, offset on X so it stays on its band's centre line.
    // Its search box spans X 290..410 - clear of the carve's 150uu half-span and
    // well inside the volume's 500uu one. This is the point each world probes on
    // the OTHER band: probing the other band's CENTRE would answer "no ground"
    // for the carve's sake by gate C and would prove nothing.
    private const float OffPaintProbeX = 350.0;

    //------------------------------------------------------------------------
    // The gate schedule - wall clock from DoBeginPlay, shared by both worlds
    //------------------------------------------------------------------------

    private const float GateASeconds = 6.0;
    private const float GateBSeconds = 12.0;
    private const float GateCSeconds = 18.0;

    //------------------------------------------------------------------------
    // Budgets - a ceiling on a NAMED condition, never a settle. The gate ones
    // are deliberately past any plausible poll rate; the wall clock bounds them.
    //------------------------------------------------------------------------

    private const int32 BodyFrameBudget = 3000;
    private const int32 BuildFrameBudget = 6000;
    private const int32 SurfaceFrameBudget = 3000;
    private const int32 ProjectFrameBudget = 3000;
    private const int32 LiveFrameBudget = 6000;
    private const int32 QuietFrameBudget = 3000;
    private const int32 GateFrameBudget = 200000;

    //------------------------------------------------------------------------
    // Fixture handles
    //------------------------------------------------------------------------

    private FCk_Handle _SelfHandle;
    private FCk_Handle _FloorEntity;
    private FCk_Handle _VolumeEntity;

    private FCk_Handle_JoltBody _FloorBody;
    private FCk_Handle_GroundNavVolume _Volume;
    private FCk_Handle_NavSurfaceMarkup _Paint;

    //------------------------------------------------------------------------
    // World state this test changes and must hand back
    //------------------------------------------------------------------------

    private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
    private bool _ProviderSwapped = false;
    private bool _RebuiltBound = false;

    //------------------------------------------------------------------------
    // Which world this body is
    //------------------------------------------------------------------------

    private bool _IsAuthority = false;

    //------------------------------------------------------------------------
    // The schedule, and whether each phase beat the gate it had to beat
    //------------------------------------------------------------------------

    private bool _GateAElapsed = false;
    private bool _GateBElapsed = false;
    private bool _GateCElapsed = false;

    private bool _StagedBeforeGateA = false;
    private bool _PaintQuietBeforeItsGate = false;

    //------------------------------------------------------------------------
    // Samples
    //------------------------------------------------------------------------

    private int64 _RevAtGateA = -1;
    private int64 _RevAtGateB = -1;
    private int64 _RevAtGateC = -1;

    private int32 _BuildCompletions = 0;
    private ECk_Request_OperationResult _LastBuildResult = ECk_Request_OperationResult::Failed;

    // Every OnSurfaceRebuilt broadcast this world saw, split by which band it
    // named. A box that names neither is counted apart rather than dropped: an
    // invalid changed-bounds box reads to every consumer as reaching everything,
    // and it is the one payload under which the band split decides nothing.
    private int32 _RebuiltOnOwnBand = 0;
    private int32 _RebuiltOnOtherBand = 0;
    private int32 _RebuiltBoundsUnknown = 0;

    //------------------------------------------------------------------------
    // Lifecycle
    //------------------------------------------------------------------------

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Captured BEFORE anything can fail, so DoEndPlay always has something
        // to put back.
        _ProviderBefore = utils_nav_surface::Get_Provider();

        // Branch on the SUBJECT's authority, not this test entity's. The harness
        // spawns the test entity on every PIE world's transient entity, locally
        // in each - so it is authoritative in its own world and
        // utils_net::Get_HasAuthority(InHandle) is TRUE on the client too. The
        // replicated NetSubject is the only handle here carrying a real net role.
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        {
            FinishFailure("net subject not found - harness misconfigured?");
            return;
        }

        _IsAuthority = utils_net::Get_HasAuthority(Subject);

        // Armed here rather than from the first step, so both worlds' clocks
        // start at the same point in the harness's single spawn pass. All three
        // run from that same instant - they are absolute marks on the schedule,
        // not a chain.
        Do_ArmGate(GateASeconds, n"OnGateA");
        Do_ArmGate(GateBSeconds, n"OnGateB");
        Do_ArmGate(GateCSeconds, n"OnGateC");

        Add_Step(          "stage this world's slab and volume",              n"Step_BuildFixture");
        Add_Step_WaitUntil("the slab reaches this world's Jolt static world", n"Check_FloorBodyAdded",  BodyFrameBudget);
        Add_Step(          "ask this world's volume to bake",                 n"Step_RequestBake");
        Add_Step_WaitUntil("this world's field reports itself built",         n"Check_FieldBuilt",      BuildFrameBudget);
        Add_Step(          "put this world on the GroundNav provider",        n"Step_SelectProvider");
        Add_Step_WaitUntil("this world's nav surface reports Ready",          n"Check_SurfaceReady",    SurfaceFrameBudget);
        Add_Step_WaitUntil("the paint spot projects on this world's floor",   n"Check_OwnSpotProjects", ProjectFrameBudget);
        Add_Step(          "staging beat gate A",                             n"Step_StagingLanded");

        Add_Step_WaitUntil("gate A",                                          n"Check_GateA",           GateFrameBudget);
        Add_Step(          "gate A - sample this world's revision",           n"Step_GateA");

        if (_IsAuthority)
        {
            Add_Step(          "gate A - the server paints its band",         n"Step_Paint");
            Add_Step_WaitUntil("the server's markup goes live",               n"Check_PaintIsLive",     LiveFrameBudget);
            Add_Step_WaitUntil("the server's repair goes quiet",              n"Check_SurfaceQuiet",    QuietFrameBudget);
            Add_Step(          "the server's paint beat gate B",              n"Step_PaintLandedBeforeGateB");
        }

        Add_Step_WaitUntil("gate B",                                          n"Check_GateB",           GateFrameBudget);
        Add_Step(          "gate B - sample this world's revision",           n"Step_GateB");

        if (!_IsAuthority)
        {
            Add_Step(          "gate B - the client paints its band",         n"Step_Paint");
            Add_Step_WaitUntil("the client's markup goes live",               n"Check_PaintIsLive",     LiveFrameBudget);
            Add_Step_WaitUntil("the client's repair goes quiet",              n"Check_SurfaceQuiet",    QuietFrameBudget);
            Add_Step(          "the client's paint beat gate C",              n"Step_PaintLandedBeforeGateC");
        }

        Add_Step_WaitUntil("gate C",                                          n"Check_GateC",           GateFrameBudget);
        Add_Step(          "gate C - sample this world's revision",           n"Step_GateC");

        Add_Step(          "the other world's paint never moved this one",    n"Step_AssertOtherWorldPaintDidNotMoveMe");
        Add_Step(          "the other world's ground is not in this field",   n"Step_AssertOtherBandHasNoGroundHere");
        Add_Step(          "the other world's repairs never published here",  n"Step_AssertNoForeignRebuilds");
        Add_Step(          "report what this world saw",                      n"Step_Report");
        Add_Step(          "hand the world back",                             n"Step_Cleanup");

        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        Teardown();
    }

    //------------------------------------------------------------------------
    // Staging - identical in both worlds except for the band
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_BuildFixture(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto BandY = Get_OwnBandY();

        _FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _FloorEntity.Request_OverrideToSelf();

        // The slab's TOP sits at the volume's mid height, so there is ground to
        // find rather than a volume of empty air that would bake successfully
        // and prove nothing.
        utils_transform::Add(_FloorEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, BandY, SurfaceZ - SlabHalfZ), FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        auto SlabShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        SlabShape.Set_HalfExtents(FVector(SlabHalfX, SlabHalfY, SlabHalfZ));

        auto SlabParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        SlabParams.Set_ShapeDimensions(SlabShape);
        SlabParams.Set_MotionType(ECk_MotionType::Static);

        _FloorBody = utils_jolt_body::Add(_FloorEntity, SlabParams);

        Assert_True(ck::IsValid(_FloorBody),
            "the slab's Jolt body must be valid - a world with no static geometry bakes an empty field, and every projection below would then answer for the wrong reason");

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _VolumeEntity.Request_OverrideToSelf();

        auto Config = FCk_GroundNav_BakeConfig(float32(CellSizeUu), float32(CellHeightUu));
        Config.Set_TileSizeUu(float32(TileSizeUu));

        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(float32(ProfileHalfHeightUu), float32(AgentRadius))));

        // The slab's own edges lie OUTSIDE the volume, but the field is clipped
        // to the volume, so the ledge filter would otherwise demote the whole
        // perimeter.
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(-VolumeHalfX, BandY - VolumeHalfY, SurfaceZ - VolumeHalfZ),
            FVector( VolumeHalfX, BandY + VolumeHalfY, SurfaceZ + VolumeHalfZ));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);

        // Auto-build off, so the bake this test waits on is the one it asked for
        // and not one that happened at composition.
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        Assert_True(ck::IsValid(_Volume), "Add() must return a valid GroundNav volume handle");

        // Bound before anything can publish, so what is counted afterwards is a
        // count of broadcasts this world saw arrive rather than of broadcasts it
        // happened to be listening for. The signal is a WORLD signal, so
        // Teardown unbinds it.
        utils_nav_surface::BindTo_OnSurfaceRebuilt(
            FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        _RebuiltBound = true;
    }

    UFUNCTION()
    private void Check_FloorBodyAdded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_FloorBody) && utils_jolt_body::Get_IsBodyAdded(_FloorBody));
    }

    UFUNCTION()
    private void Step_RequestBake(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build(),
            FCk_Delegate_Request_OnCompleted(this, n"OnBuildCompleted"));
    }

    UFUNCTION()
    private void OnBuildCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _BuildCompletions += 1;
        _LastBuildResult = InResult;
    }

    UFUNCTION()
    private void Check_FieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_BuildCompletions >= 1 && utils_ground_nav_volume::Get_IsBuilt(_Volume));
    }

    UFUNCTION()
    private void Step_SelectProvider(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_LastBuildResult == ECk_Request_OperationResult::Succeeded,
            f"a bake that finished must complete with Succeeded (got {_LastBuildResult})");

        const auto TileCount = utils_ground_nav_volume::Get_TileCount(_Volume);
        const auto VolumeSpanUu = VolumeHalfX * 2.0;

        Assert_Equals_Int(TileCount, TileCountTotal,
            f"a {VolumeSpanUu}uu volume at {TileSizeUu}uu tiles must be a 2x2 lattice - a volume that tiled differently is not the fixture this schedule was budgeted against (got {TileCount} tiles)");

        utils_nav_surface::Request_SetProvider(ECk_NavSurface_Provider::GroundNav);
        _ProviderSwapped = true;

        const auto ProviderNow = utils_nav_surface::Get_Provider();

        Assert_True(ProviderNow == ECk_NavSurface_Provider::GroundNav,
            f"this world must report the provider it was told to answer on (got {ProviderNow})");
    }

    UFUNCTION()
    private void Check_SurfaceReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Check_OwnSpotProjects(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Get_OwnSpotProjects());
    }

    UFUNCTION()
    private void Step_StagingLanded(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _StagedBeforeGateA = !_GateAElapsed;

        const auto GateSeconds = GateASeconds;

        // The whole ordering argument rests on this: if this world was still
        // staging when gate A passed, its gate-A sample is not a "before" of
        // anything and every bracket below brackets nothing.
        Assert_True(_StagedBeforeGateA,
            f"this world had to finish staging inside the first {GateSeconds}s so its gate-A revision sample precedes the server's paint. It did not, so the two worlds are no longer on the schedule these assertions are written against - the PIE lane is slower than this fixture was budgeted for.");
    }

    //------------------------------------------------------------------------
    // The gates - wall clock, because the thing they order is another world's
    // work and there is no signal between the two.
    //------------------------------------------------------------------------

    private void Do_ArmGate(float InSeconds, FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(InSeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);

        auto Timer = utils_timer::Add(_SelfHandle, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    UFUNCTION()
    private void OnGateA(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _GateAElapsed = true;
    }

    UFUNCTION()
    private void OnGateB(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _GateBElapsed = true;
    }

    UFUNCTION()
    private void OnGateC(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _GateCElapsed = true;
    }

    UFUNCTION()
    private void Check_GateA(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_GateAElapsed);
    }

    UFUNCTION()
    private void Check_GateB(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_GateBElapsed);
    }

    UFUNCTION()
    private void Check_GateC(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_GateCElapsed);
    }

    //------------------------------------------------------------------------
    // Samples
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_GateA(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevAtGateA = utils_nav_surface::Get_SurfaceRevision();

        const auto RevisionNow = _RevAtGateA;
        const auto OwnBandY = Get_OwnBandY();
        const auto OtherBandY = Get_OtherBandY();
        const auto ProbeOffsetUu = OffPaintProbeX;

        // A world reading a revision of nothing has no baseline to compare
        // against, and every "unmoved" assertion below would be about silence.
        Assert_True(RevisionNow > 0,
            f"this world baked and published a field of its own, so its surface revision must have advanced past zero by gate A (reads {RevisionNow})");

        // The strongest single reading that this body resolved its own world:
        // Get_SurfaceBounds folds THIS world's fields, and this world staged
        // ground on one band only. A shared registry - or a body answering for
        // the wrong world - shows up here as bounds reaching the other band.
        const auto Bounds = utils_nav_surface::Get_SurfaceBounds();
        const auto BoundsMin = Bounds.Min;
        const auto BoundsMax = Bounds.Max;

        Assert_True(Bounds.IsValid,
            "this world's published surface must have valid bounds by gate A - an invalid box means nothing is published, and the band assertion below could not have decided anything");

        Assert_False(Get_MeetsOtherBand(Bounds),
            f"this world staged ground on band {OwnBandY} and nothing at all on band {OtherBandY}, so its own published surface must not reach the other world's band. It reads {BoundsMin} to {BoundsMax}, which meets it - the two worlds are answering out of one field registry, or this body resolved the wrong world.");

        // The positives every paint assertion below rests on.
        Assert_True(Get_OwnSpotProjects(),
            "the paint spot must project on this world's bare floor before anything is painted - without it, a failing projection after the paint could just as well mean the field was never there");

        Assert_True(Get_OffPaintSpotProjects(OwnBandY),
            f"the off-carve probe offset ({ProbeOffsetUu}uu on X) must find ground on THIS world's band. It is the mirror of the probe taken on the other band at gate C, and unless it succeeds here that probe failing there says nothing about which world owns which ground.");
    }

    UFUNCTION()
    private void Step_GateB(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevAtGateB = utils_nav_surface::Get_SurfaceRevision();

        const auto Before = _RevAtGateA;
        const auto After = _RevAtGateB;
        const auto ProbeReachUu = ProbeHalfExtents.X;

        if (_IsAuthority)
        {
            // The server painted inside [A,B]. Its own carve is the POSITIVE
            // that makes the client's "unmoved" reading worth anything: with no
            // real paint in the other world there is nothing for a leak to leak.
            Assert_False(Get_OwnSpotProjects(),
                f"the server's markup is live, so a projection at its centre with {ProbeReachUu}uu search half-extents must find no ground. It still projects - the paint carved no hole, and the client's unmoved revision would then be a statement about a paint that never happened.");

            Assert_True(After > Before,
                f"a walkability paint repairs the tiles it reaches and republishes, so the SERVER's own surface revision has to advance across its own paint (was {Before}, now {After})");

            return;
        }

        Assert_True(After == Before,
            f"the server painted its own band, repaired its own tiles and republished its own field between gate A and gate B, while this world painted nothing. This world's surface revision must not have moved (was {Before}, now {After}) - a revision that advanced here means one world's field republished into the other's.");
    }

    UFUNCTION()
    private void Step_GateC(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevAtGateC = utils_nav_surface::Get_SurfaceRevision();

        const auto Before = _RevAtGateB;
        const auto After = _RevAtGateC;
        const auto ProbeReachUu = ProbeHalfExtents.X;

        if (_IsAuthority)
        {
            Assert_True(After == Before,
                f"the client painted its own band between gate B and gate C, while this world painted nothing. The server's surface revision must not have moved (was {Before}, now {After}).");

            // The server's own field must be exactly where it left it once the
            // other world has finished with its own - a shared field would have
            // been re-baked out from under it.
            Assert_False(Get_OwnSpotProjects(),
                "the server released nothing, so its own carve must still be in its field after the client finished painting and repairing its own band");

            return;
        }

        Assert_True(After > Before,
            f"this world painted its own band between gate B and gate C, so its own surface revision has to advance across it (was {Before}, now {After})");

        Assert_False(Get_OwnSpotProjects(),
            f"the client's markup is live, so a projection at its centre with {ProbeReachUu}uu search half-extents must find no ground");
    }

    //------------------------------------------------------------------------
    // The paint - the same body in both worlds, at different gates
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Paint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(
                FCk_ShapeBox_Dimensions(FVector(PaintHalfXY, PaintHalfXY, PaintHalfZ))),
            FGameplayTag());

        Request.Set_WorldTransform(
            FTransform(FRotator::ZeroRotator, Get_OwnPaintCentre(), FVector::OneVector));

        _Paint = utils_nav_surface::Request_ImpassableBox(Request);

        Assert_True(ck::IsValid(_Paint),
            "Request_ImpassableBox hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        // The markup entity is parented to the WORLD, not to this runner, so the
        // harness's own subtree teardown never reaches it. Registering it here is
        // what unpaints the carve on every exit path.
        Track_ForCleanup(FCk_Handle(_Paint));
    }

    UFUNCTION()
    private void Check_PaintIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsMarkupLive(_Paint));
    }

    // A repair still slicing when the next gate arrives would advance this
    // world's revision INSIDE the other world's paint window, and the "unmoved"
    // assertion there would fail for a reason that has nothing to do with
    // cross-world leakage. Settled is the one condition that names that door:
    // nothing building, no repair open or pending, nothing queued.
    UFUNCTION()
    private void Check_SurfaceQuiet(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsSurfaceSettled());
    }

    UFUNCTION()
    private void Step_PaintLandedBeforeGateB(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PaintQuietBeforeItsGate = !_GateBElapsed;

        const auto GateSeconds = GateBSeconds;

        Assert_True(_PaintQuietBeforeItsGate,
            f"the server's paint had to be live and its repair quiet before gate B ({GateSeconds}s), so that the client's gate-A/gate-B pair brackets it. It was not, so that pair no longer brackets the paint it was written to bracket.");
    }

    UFUNCTION()
    private void Step_PaintLandedBeforeGateC(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _PaintQuietBeforeItsGate = !_GateCElapsed;

        const auto GateSeconds = GateCSeconds;

        Assert_True(_PaintQuietBeforeItsGate,
            f"the client's paint had to be live and its repair quiet before gate C ({GateSeconds}s), so that the server's gate-B/gate-C pair brackets it. It was not, so that pair no longer brackets the paint it was written to bracket.");
    }

    //------------------------------------------------------------------------
    // The conclusions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_AssertOtherWorldPaintDidNotMoveMe(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Before = Get_RevisionBeforeOtherWorldPaint();
        const auto After = Get_RevisionAfterOtherWorldPaint();

        Assert_True(After == Before,
            f"the other world painted its own band, repaired its own tiles and republished its own field inside the window this pair brackets. This world's surface revision has to be untouched by all of it (was {Before}, now {After}) - the maps that answer these queries are keyed by UWorld, and a revision that moved here means one of them is answering globally.");
    }

    UFUNCTION()
    private void Step_AssertOtherBandHasNoGroundHere(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto OtherBandY = Get_OtherBandY();

        // Non-vacuous because gate A already proved this same probe offset finds
        // ground on this world's OWN band, and because by gate C the other world
        // has certainly baked its own - so a shared field would answer here.
        // Probed off the carve on purpose: the other band's CENTRE has a hole in
        // it by now, and a probe there would fail for the carve's sake.
        Assert_False(Get_OffPaintSpotProjects(OtherBandY),
            f"the other world baked ground on band {OtherBandY} and this world baked none there, so a projection at that band's off-carve spot must find nothing in THIS world's field. It found ground - the other world's field is reachable from this one.");
    }

    UFUNCTION()
    private void Step_AssertNoForeignRebuilds(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto OwnBand = _RebuiltOnOwnBand;
        const auto OtherBand = _RebuiltOnOtherBand;
        const auto Unknown = _RebuiltBoundsUnknown;
        const auto OtherBandY = Get_OtherBandY();

        // The POSITIVE first: with no broadcast at all there is nothing to have
        // been local, and the foreign count below would be zero over silence.
        Assert_True(OwnBand >= 1,
            f"this world baked and painted its own band, so the neutral OnSurfaceRebuilt signal must have delivered at least one publish naming it (got {OwnBand} on its own band, {OtherBand} on the other, {Unknown} with bounds unknown)");

        Assert_Equals_Int(Unknown, 0,
            f"a publish carried an INVALID changed-bounds box, which every consumer reads as reaching every corridor in the world - and it is the one payload under which the band split decides nothing (got {Unknown})");

        Assert_Equals_Int(OtherBand, 0,
            f"OnSurfaceRebuilt is a WORLD signal, and the other world republished its own field over this run. Not one of those publishes may be delivered here (got {OtherBand} broadcast(s) naming band {OtherBandY})");
    }

    UFUNCTION()
    private void Step_Report(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto WorldLabel = Get_WorldLabel();
        const auto Before = Get_RevisionBeforeOtherWorldPaint();
        const auto After = Get_RevisionAfterOtherWorldPaint();
        const auto MovedMe = After != Before;

        ck::nav::Display(f"[GROUNDNAV-MULTIWORLD] world={WorldLabel} revisionBefore={Before} revisionAfter={After} otherWorldPaintMovedMe={MovedMe}");

        const auto Band = Get_OwnBandY();
        const auto GateA = _RevAtGateA;
        const auto GateB = _RevAtGateB;
        const auto GateC = _RevAtGateC;
        const auto OwnBandRebuilds = _RebuiltOnOwnBand;
        const auto OtherBandRebuilds = _RebuiltOnOtherBand;

        ck::nav::Display(f"[GROUNDNAV-MULTIWORLD] world={WorldLabel} band={Band} revisionAtGates={GateA}/{GateB}/{GateC} rebuiltOnOwnBand={OwnBandRebuilds} rebuiltOnOtherBand={OtherBandRebuilds}");
    }

    //------------------------------------------------------------------------
    // The world signal
    //------------------------------------------------------------------------

    UFUNCTION()
    private void OnSurfaceRebuilt(FCk_Handle InWorldEntity, FBox InChangedBounds)
    {
        if (IsFinished()) { return; }

        if (!InChangedBounds.IsValid)
        {
            _RebuiltBoundsUnknown += 1;
            return;
        }

        if (Get_MeetsOtherBand(InChangedBounds))
        {
            _RebuiltOnOtherBand += 1;
            return;
        }

        if (Get_MeetsOwnBand(InChangedBounds))
        {
            _RebuiltOnOwnBand += 1;
        }
    }

    //------------------------------------------------------------------------
    // Fixture geometry - answered here rather than read back out of the system
    // under test
    //------------------------------------------------------------------------

    private float Get_OwnBandY()
    {
        if (_IsAuthority) { return ServerBandY; }

        return ClientBandY;
    }

    private float Get_OtherBandY()
    {
        if (_IsAuthority) { return ClientBandY; }

        return ServerBandY;
    }

    private FString Get_WorldLabel()
    {
        if (_IsAuthority) { return "server"; }

        return "client";
    }

    private FVector Get_OwnPaintCentre()
    {
        return FVector(0.0, Get_OwnBandY(), SurfaceZ);
    }

    // Which pair of samples brackets the OTHER world's paint. The server paints
    // in [A,B] and the client in [B,C], so each world reads back the window it
    // was idle through.
    private int64 Get_RevisionBeforeOtherWorldPaint()
    {
        if (_IsAuthority) { return _RevAtGateB; }

        return _RevAtGateA;
    }

    private int64 Get_RevisionAfterOtherWorldPaint()
    {
        if (_IsAuthority) { return _RevAtGateC; }

        return _RevAtGateB;
    }

    // Answered on components rather than through an FBox operator this fixture
    // cannot point at a binding for. Touching faces count as meeting, which is
    // the inclusive reading tile selection itself uses. Only Y is tested: the
    // two bands differ on Y alone, and both volumes span the same X.
    private bool Get_MeetsBand(FBox InBounds, float InBandY)
    {
        if (InBounds.Min.Y > InBandY + VolumeHalfY) { return false; }
        if (InBounds.Max.Y < InBandY - VolumeHalfY) { return false; }

        return true;
    }

    private bool Get_MeetsOwnBand(FBox InBounds)
    {
        return Get_MeetsBand(InBounds, Get_OwnBandY());
    }

    private bool Get_MeetsOtherBand(FBox InBounds)
    {
        return Get_MeetsBand(InBounds, Get_OtherBandY());
    }

    //------------------------------------------------------------------------
    // Probes - search half-extents tighter than the hole a 300uu box leaves, so
    // a point inside the carve has nothing beside it to snap to
    //------------------------------------------------------------------------

    private bool Get_PointProjects(FVector InPoint)
    {
        auto Query = FCk_NavSurface_ProjectionQuery(InPoint);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Query.Set_SearchHalfExtents(ProbeHalfExtents);

        return utils_nav_surface::Try_ProjectPoint(Query).Get_Status()
            == ECk_NavSurface_QueryStatus::Success;
    }

    private bool Get_OwnSpotProjects()
    {
        return Get_PointProjects(Get_OwnPaintCentre());
    }

    private bool Get_OffPaintSpotProjects(float InBandY)
    {
        return Get_PointProjects(FVector(OffPaintProbeX, InBandY, SurfaceZ));
    }

    //------------------------------------------------------------------------
    // Teardown
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Cleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Teardown();
    }

    // Idempotent, and called from BOTH the conclusion and DoEndPlay. Two things
    // here outlive this test's own subtree in its world: the provider is a WORLD
    // selection every later consumer reads, and OnSurfaceRebuilt is a WORLD
    // signal that would keep calling into a finished script. Every exit path -
    // including the engine TimeLimit one - has to put both back.
    private void Teardown()
    {
        if (_RebuiltBound)
        {
            _RebuiltBound = false;
            utils_nav_surface::UnbindFrom_OnSurfaceRebuilt(
                FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"));
        }

        if (_ProviderSwapped)
        {
            _ProviderSwapped = false;
            utils_nav_surface::Request_SetProvider(_ProviderBefore);
        }

        if (ck::IsValid(_Paint))
        {
            utils_entity_lifetime::Request_DestroyEntity(FCk_Handle(_Paint));
            _Paint = FCk_Handle_NavSurfaceMarkup();
        }

        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
        }

        if (ck::IsValid(_FloorEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_FloorEntity);
            _FloorEntity = FCk_Handle();
        }
    }
}
