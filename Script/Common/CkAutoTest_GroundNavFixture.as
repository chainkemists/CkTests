// Language=angelscript

//============================================================================
// CK AUTOTEST - GROUNDNAV ORIGIN-FIELD FIXTURE
//============================================================================
//
// The shared autotest level ships ONE piece of ground at the origin -
// StaticMeshActor_1, roughly X/Y +/-1500 with its top face at Z 0 - and the
// obstacle fixtures under Script/CkCrowd and Script/CkQueue all settle on the
// Recast navmesh baked over it. Nothing in that level publishes a GroundNav
// field, so a world switched to ECk_NavSurface_Provider::GroundNav has no
// ground to answer over and every one of those fixtures fails for the fixture's
// reason rather than the provider's.
//
// This is the missing half: it stages and bakes one GroundNav volume covering
// that floor, gives a test the two named conditions it needs to wait on, and
// emits one grep-able result line per test so a crossover run's evidence can be
// pulled out of a scoped log without reading the whole run.
//
//----------------------------------------------------------------------------
// HOW A TEST USES IT - composition, plus one-line forwarders
//----------------------------------------------------------------------------
//
// This is a VALUE-TYPE struct with plain methods (Script/ARCHITECTURE.md 9),
// held as a member, in the same "compose, don't inherit" spirit as
// CkAutoTest_ActorEntity_Helper.as. It is NOT a base class.
//
// The forwarders are not ceremony and cannot be designed away:
// UCk_AutoTest_Base::Do_EvaluatePredicate binds
// FCk_Predicate_InHandle_OutResult(this, InPredicateName) against the TEST
// object, so a predicate named in Add_Step_WaitUntil must be a UFUNCTION on the
// test. The fixture therefore exposes the predicate BODIES in exactly the
// predicate signature, and the test wraps each in one line:
//
//   class UCk_AutoTest_Crowd_Foo : UCk_AutoTest_Base
//   {
//       private FCkAutoTest_GroundNavFixture _Field;
//       private ECk_NavSurface_Provider _ProviderBefore = ECk_NavSurface_Provider::Recast;
//       private bool _ProviderSwapped = false;
//
//       UFUNCTION(BlueprintOverride)
//       void DoBeginPlay(FCk_Handle InHandle)
//       {
//           _ProviderBefore = utils_nav_surface::Get_Provider();
//           Add_Step(          "stage a GroundNav field over the origin floor", n"Step_StageField");
//           Add_Step_WaitUntil("the origin field reports itself built",         n"Check_OriginFieldBuilt", 3600);
//           Add_Step(          "switch the world onto GroundNav",               n"Step_SwitchProvider");
//           Add_Step_WaitUntil("the surface settles",                           n"Check_SurfaceSettled", 900);
//           ... the fixture's own steps ...
//           Run_Steps(InHandle);
//       }
//
//       UFUNCTION() private void Step_StageField(FCk_Handle InHandle, FInstancedStruct InPayload)
//       {
//           if (_Field.Request_StageOriginField(InHandle) == false)
//           { FinishFailure(_Field.Get_StagingError()); }
//       }
//
//       UFUNCTION() private void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
//       { _Field.Check_OriginFieldBuilt(InHandle, OutResult, InPayload); }
//
//       UFUNCTION() private void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
//       { _Field.Check_SurfaceSettled(InHandle, OutResult, InPayload); }
//
//       UFUNCTION(BlueprintOverride)
//       void DoEndPlay(FCk_Handle InHandle) { Teardown(); }
//
//       private void Teardown()
//       {
//           _Field.Do_ReportCrossover("Crowd_Foo", _Verdict);
//           if (_ProviderSwapped) { _ProviderSwapped = false; utils_nav_surface::Request_SetProvider(_ProviderBefore); }
//           _Field.Request_ReleaseOriginField();
//       }
//   }
//
// THE PROVIDER IS THE TEST'S BUSINESS, NOT THE FIXTURE'S. Staging a field does
// not switch anything: the provider is a WORLD selection every later test in
// the map reads, so whoever swaps it owns capturing the previous value and
// handing it back on EVERY exit path including DoEndPlay (the engine TimeLimit
// path never runs the finish path). A run-level default may also have already
// put the world on GroundNav, in which case a test swaps nothing at all.
//
//----------------------------------------------------------------------------
// THE CLOSED-COLLISION CONTRACT THIS FIXTURE CANNOT HIDE
//----------------------------------------------------------------------------
//
// GroundNav bakes from the JOLT STATIC WORLD, not from UE collision, and it
// sees FACES ONLY. A Solid body whose mesh is not closed - a slab with no
// underside, a plane, a wall whose bottom was never modelled - presents nothing
// in the columns beneath it and BAKES AS OPEN GROUND. The bake reports that
// once per build through ck::groundnav::Warning, and the AutoTest harness
// escalates a Warning into a test failure.
//
// This fixture CANNOT suppress that and deliberately does not try. Whether the
// level's origin floor is a closed body is a property of that asset's collision
// setup, unknown until a bake runs over it, and this fixture's own bake is what
// answers it. If the run comes back with an OPEN
// COLLISION warning, the finding is about StaticMeshActor_1's collision (simple
// box vs. a one-sided complex mesh), not about the tests that failed.
//
// Get_OriginVolume() is exposed so a test can interrogate the field it got.
// There is no AngelScript reader for the open-body count:
// FCk_GroundNav_Field::Get_OpenBodyCount and
// FCk_GroundNav_DebugSnapshot::Get_OpenBodyCount are both plain C++ accessors,
// neither is a UFUNCTION on a Utils class, and nothing under
// CkFoundation/Script/Generated mentions OpenBody. What a test CAN read off the
// handle today: Get_IsBuilt, Get_IsBuilding, Get_BuiltTileCount, Get_TileCount,
// Get_WalkableCellCount, Get_SurfaceBounds, Get_BuildEpoch, Get_ProviderHealth,
// Get_RegionStatusAt/Within, Get_SeamPortalCount.
//
//============================================================================

struct FCkAutoTest_GroundNavFixture
{
    //------------------------------------------------------------------------
    // Resolved fixture. All UPROPERTY because AS structs reflect their fields.
    //------------------------------------------------------------------------

    UPROPERTY() FCk_Handle _RunnerHandle;
    UPROPERTY() FCk_Handle _VolumeEntity;
    UPROPERTY() FCk_Handle_GroundNavVolume _Volume;

    UPROPERTY() AStaticMeshActor _FloorActor;

    // True only when THIS fixture put the floor into the Jolt static world. A floor another test
    // (or the host's own level sweep) baked is left exactly as it was found - removing it would
    // pull the ground out from under whoever owns it.
    UPROPERTY() bool _FloorBakedByThisFixture = false;

    UPROPERTY() FVector _FloorCentre;
    UPROPERTY() float _FloorTopZ = 0.0;

    // Polls of Check_SurfaceSettled since the last Request_KickSettleCount. Reported as
    // settledFrames so a crossover line says how long the surface took to go quiet, without any
    // test asserting against the number - how many passes a settle needs is a property of the
    // provider and of processor ordering.
    UPROPERTY() int32 _SettledPolls = 0;

    UPROPERTY() bool _Staged = false;
    UPROPERTY() FString _StagingError;

    //------------------------------------------------------------------------
    // Staging
    //------------------------------------------------------------------------

    // Bakes one GroundNav field over the level's origin floor. Returns false when the fixture
    // itself could not be built, with the reason in Get_StagingError() - the caller decides how to
    // fail, because this struct cannot reach the test's FinishFailure.
    //
    // The volume entity is created UNDER InRunnerHandle, so ACk_AutoTestRunner's per-test teardown
    // cascades it. That is why it is not registered with Track_ForCleanup: the base tracks
    // OUT-of-subtree owners, and this one is inside.
    //
    // InHalfExtentXY defaults to 1000: the extent of the level's own navmesh bounds volume, which is
    // the ground the obstacle fixtures were authored against - a wall that runs off the navmesh's
    // edge on Recast has to run off the field's edge here, or the same wall leaves a corridor open
    // that no fixture expects. The floor itself reaches roughly +/-1500, so the field sits entirely
    // on floor and no perimeter cliff is inside it; LedgeSensitivity is pinned to 0 all the same so
    // the bake stays indifferent to the floor's edge whatever extent a caller asks for.
    //
    // The Z span is measured from the floor's own top face rather than assumed: the defaults give
    // exactly -100 .. +400 for a floor whose top sits at Z 0, which is what the WalksInstalledRoute
    // fixture pins as SurfaceZ.
    bool Request_StageOriginField(
        FCk_Handle InRunnerHandle,
        float InHalfExtentXY = 1000.0,
        float InFloorDropUu = 100.0,
        float InCeilingRiseUu = 400.0,
        float InAgentRadiusUu = 42.0,
        float InAgentHalfHeightUu = 96.0)
    {
        if (_Staged)
        { return true; }

        _RunnerHandle = InRunnerHandle;

        if (ck::Is_NOT_Valid(_RunnerHandle))
        {
            _StagingError = "GroundNav origin field staging failed: the runner handle is invalid";
            return false;
        }

        _FloorActor = assets::StaticMeshActor_1().Get();

        if (!System::IsValid(_FloorActor))
        {
            _StagingError = "GroundNav origin field staging failed: the level floor StaticMeshActor_1 could not be reached - the fixture, not the feature, is broken";
            return false;
        }

        auto FloorOrigin = FVector::ZeroVector;
        auto FloorExtent = FVector::ZeroVector;
        _FloorActor.GetActorBounds(false, FloorOrigin, FloorExtent);

        // Narrowed explicitly: FVector components are float64 and every tunable here is float32, and
        // arithmetic straddling the two is an overload resolution nobody should have to guess at.
        _FloorTopZ = float(FloorOrigin.Z + FloorExtent.Z);
        _FloorCentre = FVector(FloorOrigin.X, FloorOrigin.Y, FloorOrigin.Z);

        if (Do_EnsureFloorIsStaticWorldGeometry() == false)
        { return false; }

        _VolumeEntity = utils_entity_lifetime::Request_CreateEntity(_RunnerHandle);
        _VolumeEntity.Request_OverrideToSelf();
        _VolumeEntity.Set_DebugName(n"AutoTest_GroundNav_OriginField");

        // The same bake shape every GroundNav fixture in this corpus uses, so a failure here is
        // never about a one-off bake config.
        auto Config = FCk_GroundNav_BakeConfig(25.0f, 10.0f);
        Config.Set_TileSizeUu(500.0f);

        // Radius is deliberately absent from the standing profile - clearance is answered per query
        // as clearance >= R - so only the height matters to the bake, and the querying agent feeds
        // its own radius in.
        auto Profile = FCk_GroundNav_AgentProfile(
            utils_shapes::Make_Capsule(
                FCk_ShapeCapsule_Dimensions(float32(InAgentHalfHeightUu), float32(InAgentRadiusUu))));
        Profile.Set_LedgeSensitivity(0.0f);

        const auto Bounds = FBox(
            FVector(_FloorCentre.X - InHalfExtentXY, _FloorCentre.Y - InHalfExtentXY, _FloorTopZ - InFloorDropUu),
            FVector(_FloorCentre.X + InHalfExtentXY, _FloorCentre.Y + InHalfExtentXY, _FloorTopZ + InCeilingRiseUu));

        auto VolumeParams = FCk_Fragment_GroundNavVolume_ParamsData(Bounds, Config, Profile);
        // The bake waited on must be the one asked for, not one that happened to run at setup.
        VolumeParams.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);

        _Volume = utils_ground_nav_volume::Add(_VolumeEntity, VolumeParams);

        if (ck::Is_NOT_Valid(_Volume))
        {
            _StagingError = "GroundNav origin field staging failed: Add() returned an invalid volume handle";
            return false;
        }

        // No completion delegate: a struct cannot host a UFUNCTION, and the named condition a test
        // waits on is Get_IsBuilt rather than a callback count.
        utils_ground_nav_volume::Request_Build(_Volume, FCk_Request_GroundNavVolume_Build());

        _Staged = true;
        _SettledPolls = 0;

        ck::nav::Display(f"[GROUNDNAV-CROSSOVER] staged origin field: centre={_FloorCentre} floorTopZ={_FloorTopZ} halfXY={InHalfExtentXY} floorBakedHere={_FloorBakedByThisFixture}");

        return true;
    }

    // GroundNav reads the Jolt static world, not UE collision, and whether the host's level sweep
    // has already put the floor there is the host project's business rather than a test's. Probing
    // first and baking only on a miss is what makes this safe to call from ten fixtures in one lane.
    // No access specifiers and no const on any method here: Script/ARCHITECTURE.md 9's struct
    // example declares plain methods only, so nothing beyond that shape is assumed of the AS
    // struct compiler. The Do_ prefix carries the "internal" meaning instead.
    bool Do_EnsureFloorIsStaticWorldGeometry()
    {
        const auto ProbeStart = FVector(_FloorCentre.X, _FloorCentre.Y, _FloorTopZ + 200.0);
        const auto ProbeEnd = FVector(_FloorCentre.X, _FloorCentre.Y, _FloorTopZ - 200.0);

        if (utils_jolt_static_world::Get_RayCastStaticWorld(ProbeStart, ProbeEnd).Get_HasHit())
        {
            ck::nav::Display("[GROUNDNAV-CROSSOVER] the level floor is already in the Jolt static world");
            return true;
        }

        const auto BodiesAdded = utils_jolt_static_world::Request_BakeActor(_FloorActor);

        if (BodiesAdded < 1)
        {
            _StagingError = f"GroundNav origin field staging failed: the level floor is not in the Jolt static world and baking it produced {BodiesAdded} bodies, so the field would bake over nothing at all";
            return false;
        }

        _FloorBakedByThisFixture = true;
        return true;
    }

    //------------------------------------------------------------------------
    // Wait predicates - bodies only. See the header: the UFUNCTION that names
    // these to Add_Step_WaitUntil has to live on the test.
    //------------------------------------------------------------------------

    // The field this fixture asked for has finished baking.
    void Check_OriginFieldBuilt(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        // A local copy, never the parameter: AS treats a by-value struct param as read-only and
        // rejects OutResult.Set(...). FCk_SharedBool holds a shared cell, so the copy writes through.
        auto Res = OutResult;
        Res.Set(ck::IsValid(_Volume) && utils_ground_nav_volume::Get_IsBuilt(_Volume));
    }

    // The world's provider has nothing in flight and nothing pending: its published surface is the
    // one every query will answer from. This is the ONE named settle to wait on after a provider
    // switch, a paint, a release, or a rebuild kick - a fixed number of ticks only ever happens to
    // be enough for whichever provider it was measured against.
    void Check_SurfaceSettled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _SettledPolls += 1;

        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsSurfaceSettled());
    }

    // Zeroes the settle counter. Call it immediately before whatever re-dirties the surface - the
    // provider switch, a paint, a release - so the number reported afterwards measures that kick
    // rather than the sum of every kick in the test.
    void Request_KickSettleCount()
    {
        _SettledPolls = 0;
    }

    //------------------------------------------------------------------------
    // Reporting
    //------------------------------------------------------------------------

    // One grep-able line per test. Emitted at Display level on purpose: the AutoTest harness
    // escalates a Warning into a test failure, so evidence must never be logged above Display.
    void Do_ReportCrossover(FString InTestName, FString InVerdict)
    {
        const auto Provider = utils_nav_surface::Get_Provider();
        const auto Built = ck::IsValid(_Volume) && utils_ground_nav_volume::Get_IsBuilt(_Volume);
        const auto SettledFrames = _SettledPolls;

        ck::nav::Display(f"[GROUNDNAV-CROSSOVER] test={InTestName} provider={Provider} originFieldBuilt={Built} settledFrames={SettledFrames} verdict={InVerdict}");
    }

    //------------------------------------------------------------------------
    // Readers
    //------------------------------------------------------------------------

    FCk_Handle_GroundNavVolume Get_OriginVolume() { return _Volume; }
    FCk_Handle Get_OriginVolumeEntity() { return _VolumeEntity; }

    // The floor's own top face, so a test can place agents and goals on the ground the field was
    // baked over rather than assuming Z 0.
    float Get_FloorTopZ() { return _FloorTopZ; }
    FVector Get_FloorCentre() { return _FloorCentre; }

    int32 Get_SettledFrames() { return _SettledPolls; }
    bool Get_IsStaged() { return _Staged; }
    FString Get_StagingError() { return _StagingError; }

    //------------------------------------------------------------------------
    // Release
    //------------------------------------------------------------------------

    // Idempotent, and safe to call from both the conclusion and DoEndPlay.
    //
    // The volume entity would be cascaded by the harness anyway; destroying it here retires the
    // published field before the next test in the shared PIE world starts looking at the surface.
    // The floor removal is the part that is NOT optional: a floor this fixture pushed into the Jolt
    // static world stays there for the rest of the lane otherwise, and every later bake in the map
    // silently gains ground it did not stage.
    void Request_ReleaseOriginField()
    {
        _Staged = false;

        if (ck::IsValid(_VolumeEntity))
        {
            utils_entity_lifetime::Request_DestroyEntity(_VolumeEntity);
            _VolumeEntity = FCk_Handle();
            _Volume = FCk_Handle_GroundNavVolume();
        }

        if (_FloorBakedByThisFixture && System::IsValid(_FloorActor))
        {
            _FloorBakedByThisFixture = false;
            utils_jolt_static_world::Request_RemoveActor(_FloorActor);
        }
    }
}
