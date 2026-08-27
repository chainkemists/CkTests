// Language=angelscript

//============================================================================
// CK JOLT GYM - STATIC BAKE
//
// Exercises and self-verifies the Jolt static-world bake paths. Each lane
// builds (or scans) geometry, bakes it into the Jolt static world, and fires
// "witness" ray pairs - one CHANNEL-FILTERED Jolt ray (Visibility/Block, same
// filter the Chaos side uses) vs one Chaos line trace from identical
// start/end. A witness PASSES when both hit within 1uu, or when both miss and
// the witness expected a miss; anything else is a FAIL logged with both
// positions.
//
//   1.  StaticMesh   - one AStaticMeshActor (engine Cube, scale 2). Bake -> 1.
//   2.  HISM sparse  - 5 instances (< compound threshold) -> per-instance bodies (5).
//   3.  HISM dense   - 40 instances, 8-wide grid (>= threshold) -> 1 compound body.
//   4.  SplineMesh   - runtime-spawned; documents the runtime-cook gap (skipped
//                      when collision never cooks - expected).
//   4b. SplineMesh (authored) - scans actors tagged CkJoltGym.AuthoredSpline
//                      (editor-authored via Ck.Gym.AuthorJoltStaticBakeContent);
//                      the lane that actually exercises the spline bake branch.
//   5.  Volume/Brush - LEVEL-SWEEP bake path; scans authored volumes.
//   6.  Landscape    - scans authored landscapes (author one with the same command).
//
// The player's view also fires a CONTINUOUS Jolt ray (green hit / red miss
// see OnViewRayTick) for free-aim visual verification of any geometry.
//
// The station is PINNED at (500, 20000, 0) - the authored landscape/spline are
// permanent level content parked at the Y=20000 band so the 42 other gyms
// sharing this level never collide with them; Request_StartGym teleports the
// player there. Keep coordinates in sync with CkGymJoltStaticBakeAuthoring.cpp.
//
// Runtime content is built in world -X from the station anchor (house rule:
// stations face -X), spread across Y, elevated so lane centers sit ~+250 above
// anchor. Witness rays stay tightly bounded in Z so a MISS never reaches the
// gym floor below (which would let the Chaos trace hit the floor and pollute
// parity).
//============================================================================

// One witness: a start/end ray pair plus whether both sides are expected to miss.
USTRUCT()
struct FCkJoltStaticBake_Witness
{
    UPROPERTY() FString Label;
    UPROPERTY() FVector Start = FVector::ZeroVector;
    UPROPERTY() FVector End = FVector::ZeroVector;
    UPROPERTY() bool ExpectMiss = false;
}

class ACk_JoltGym_StaticBake_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_StaticBake_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_StaticBake_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;

    // Host entity for the settle timer (mirrors the gym base's _SelfEntity + WaitOneFrame).
    private FCk_Handle _GymEntity;

    private TArray<FCkJoltStaticBake_Witness> _Witnesses;
    private TArray<AActor> _LaneActors;          // runtime-baked lane actors, for Rebake
    private AActor _SplineActor;                 // resolved (baked) or left skipped in settle
    private FVector _SplineMidWorld = FVector::ZeroVector;

    private int32 _SkippedGapCount = 0;
    private int32 _LastTotal = 0;
    private int32 _LastPass = 0;
    private int32 _LastFail = 0;
    private int32 _LastExpectedMiss = 0;

    // Layout (relative to _Origin). Content sits in -X; lanes spread across Y at 500uu pitch.
    private float _ContentX = -400.0;
    private float _LaneCenterZ = 250.0;
    private float _WitnessTopZ = 400.0;      // ray top    = laneCenterZ + this
    private float _WitnessBottomZ = 200.0;   // ray bottom = laneCenterZ - this (stays above floor)

    private float _LaneY_StaticMesh = -1000.0;
    private float _LaneY_HismSparse = -500.0;
    private float _LaneY_HismDense = 0.0;
    private float _LaneY_Spline = 500.0;

    // Continuous player view-ray vs the full Jolt query layer - instant visual confirmation of
    // which geometry Jolt actually has (a rendered mesh with NO hit = a bake gap, e.g. the
    // runtime spline-mesh lane). Toggled by Ck_GymJoltStaticBake_ToggleRay.
    private bool _ViewRayEnabled = true;
    private float _ViewRayRange = 8000.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.StaticBake");
        Station.Title = FText::FromString("JOLT STATIC BAKE");

        // Pinned off the shared default grid - the authored landscape/spline are permanent level
        // content at the Y=20000 band (see the header comment). Keep in sync with
        // CkGymJoltStaticBakeAuthoring.cpp.
        Station.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(500.0, 20000.0, 0.0), FVector::OneVector);

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Runtime geometry baked into the Jolt static world, each lane self-verified by Jolt-vs-Chaos witness rays (watch the log for PASS/FAIL/MISS)."));
        Description.Add(FText::FromString("Lanes: StaticMesh | HISM sparse (5) | HISM dense (40) | SplineMesh (runtime gap + authored) | Volume/Brush scan | Landscape scan."));
        Description.Add(FText::FromString("Your view fires a continuous Jolt ray: GREEN beam + entity label = Jolt has that geometry; RED beam through a rendered mesh = bake gap."));
        Description.Add(FText::FromString("Ck_GymJoltStaticBake_RunWitnesses\nCk_GymJoltStaticBake_Rebake\nCk_GymJoltStaticBake_ToggleRay"));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.StaticBake", ECk_GymStation_Anchor::FootprintCenter);

        // The station is pinned far off the default grid - bring the player to it (retried in
        // OnWitnessSettle in case the pawn isn't possessed yet this early).
        DoBringPlayerToStation();

        // Host entity for the settle timer (mirrors the gym base's _SelfEntity + WaitOneFrame,
        // both of which are private to the base and unreachable from this subclass).
        _GymEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        _GymEntity.Request_OverrideToSelf();
        _GymEntity.Set_DebugName(n"StaticBake.GymEntity");

        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (ck::Is_NOT_Valid(Cube))
        {
            ck::Trace("StaticBakeGym: FAILED to load /Engine/BasicShapes/Cube.Cube - gym cannot build lanes");
            return;
        }

        DoBuildLane_StaticMesh(Cube);
        DoBuildLane_HismSparse(Cube);
        DoBuildLane_HismDense(Cube);
        DoBuildLane_Spline_Geometry(Cube);   // geometry only; probe + bake happen in settle
        DoScanLane_AuthoredSplines();
        DoScanLane_Volumes();
        DoScanLane_Landscapes();

        ck::Trace("JoltStaticBakeGym: lanes built + baked - set ck.Jolt.DebugDraw.Enabled 1 to see baked wireframes");

        // Continuous view-ray: every frame, cast from the player's view through the Jolt world
        // and draw the result (see OnViewRayTick).
        utils_timer::Create_Tick(_GymEntity, FCk_Delegate_Timer(this, n"OnViewRayTick"));

        // Defer the first witness run one frame so runtime Chaos bodies register before the
        // Jolt-vs-Chaos comparison (mirrors CkAutoTest_Base::WaitOneFrame).
        DoWaitOneFrame(n"OnWitnessSettle");
    }

    UFUNCTION()
    private void OnWitnessSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DoBringPlayerToStation();   // retry - the pawn may not have been possessed at StartGym
        DoResolveSplineLane();   // Chaos body now exists - probe then bake-or-skip
        DoRunAllWitnesses();
        DoLogWitnessSummary("initial");
    }

    // The station is pinned at the Y=20000 band, far from the level's PlayerStart - without this
    // the player spawns ~20k units from the gym. Traced so a stranded player is diagnosable from
    // the log.
    private void DoBringPlayerToStation()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        {
            ck::Trace("StaticBakeGym: no controlled pawn yet - teleport to the pinned station skipped");
            return;
        }

        ViewPawn.SetActorLocation(_Origin + FVector(600.0, 0.0, 350.0));
        SetControlRotation(FRotator(-15.0, 180.0, 0.0));
        ck::Trace(f"StaticBakeGym: teleported player to the pinned station at {_Origin}");
    }

    // ------------------------------------------------------------------------------------------
    // Lane 1 - StaticMesh: one engine Cube (scale 2), simple box collision, one Jolt body.
    // ------------------------------------------------------------------------------------------
    private void DoBuildLane_StaticMesh(UStaticMesh InCube)
    {
        auto SpawnAt = _Origin + FVector(_ContentX, _LaneY_StaticMesh, _LaneCenterZ);
        auto Actor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, SpawnAt));
        if (ck::Is_NOT_Valid(Actor))
        {
            ck::Trace("StaticBakeGym: [FAIL] StaticMesh lane - could not spawn AStaticMeshActor");
            return;
        }

        // Runtime-spawned actors must be Movable to accept a mesh (ExplicitActor bake policy).
        Actor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        Actor.StaticMeshComponent.SetStaticMesh(InCube);
        Actor.SetActorScale3D(FVector(2.0, 2.0, 2.0));
        Actor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        DoBakeAndReport(Actor, 1, "StaticMesh");

        // Down + side witnesses (mirror the SimpleBox autotest).
        DoAddDownWitness("StaticMesh down-ray", SpawnAt.X, SpawnAt.Y, false);

        auto SideZ = _Origin.Z + _LaneCenterZ;
        auto SideStart = FVector(SpawnAt.X - 300.0, SpawnAt.Y, SideZ);
        auto SideEnd = FVector(SpawnAt.X + 300.0, SpawnAt.Y, SideZ);
        DoAddWitness("StaticMesh side-ray", SideStart, SideEnd, false);
    }

    // ------------------------------------------------------------------------------------------
    // Lane 2 - HISM sparse: 5 instances (below compound threshold) => 5 per-instance bodies.
    // ------------------------------------------------------------------------------------------
    private void DoBuildLane_HismSparse(UStaticMesh InCube)
    {
        auto CompWorld = _Origin + FVector(_ContentX, _LaneY_HismSparse, _LaneCenterZ);
        auto Actor = SpawnActor(AActor, CompWorld);
        if (ck::Is_NOT_Valid(Actor))
        {
            ck::Trace("StaticBakeGym: [FAIL] HISM sparse lane - could not spawn host actor");
            return;
        }

        auto Hism = UHierarchicalInstancedStaticMeshComponent::Create(Actor);
        // A plain AActor has no root component - place the created component explicitly.
        Hism.SetWorldLocation(CompWorld);
        Hism.SetStaticMesh(InCube);
        Hism.SetCollisionProfileName(n"BlockAll");

        // AddInstance transforms are COMPONENT-space; row extends into -X.
        for (int32 Index = 0; Index < 5; ++Index)
        {
            auto Local = FVector(Index * -200.0, 0.0, 0.0);
            Hism.AddInstance(FTransform(FRotator::ZeroRotator, Local, FVector::OneVector), false);
        }

        DoBakeAndReport(Actor, 5, "HISM sparse");

        // Down-rays over the FIRST (local 0) and LAST (local -800) instances.
        DoAddDownWitness("HISM sparse first", CompWorld.X, CompWorld.Y, false);
        DoAddDownWitness("HISM sparse last", CompWorld.X - 800.0, CompWorld.Y, false);
    }

    // ------------------------------------------------------------------------------------------
    // Lane 3 - HISM dense: 40 instances in an 8-wide grid (>= threshold) => 1 compound body.
    // ------------------------------------------------------------------------------------------
    private void DoBuildLane_HismDense(UStaticMesh InCube)
    {
        auto CompWorld = _Origin + FVector(_ContentX, _LaneY_HismDense, _LaneCenterZ);
        auto Actor = SpawnActor(AActor, CompWorld);
        if (ck::Is_NOT_Valid(Actor))
        {
            ck::Trace("StaticBakeGym: [FAIL] HISM dense lane - could not spawn host actor");
            return;
        }

        auto Hism = UHierarchicalInstancedStaticMeshComponent::Create(Actor);
        Hism.SetWorldLocation(CompWorld);
        Hism.SetStaticMesh(InCube);
        Hism.SetCollisionProfileName(n"BlockAll");

        // 8 cols (into -X) x 5 rows (centered on Y), spacing 120uu (cube 100uu => clean gaps).
        for (int32 Index = 0; Index < 40; ++Index)
        {
            auto Row = Math::IntegerDivisionTrunc(Index, 8);
            auto Col = Index % 8;
            auto Local = FVector(Col * -120.0, (Row - 2) * 120.0, 0.0);
            Hism.AddInstance(FTransform(FRotator::ZeroRotator, Local, FVector::OneVector), false);
        }

        DoBakeAndReport(Actor, 1, "HISM dense");

        // First (col0,row0) and last (col7,row4) instances both HIT.
        DoAddDownWitness("HISM dense first", CompWorld.X, CompWorld.Y - 240.0, false);
        DoAddDownWitness("HISM dense last", CompWorld.X - 840.0, CompWorld.Y + 240.0, false);

        // A ray in a grid gap: both MISS (expected-miss witness - the compound isn't a blob).
        DoAddDownWitness("HISM dense gap", CompWorld.X - 60.0, CompWorld.Y - 180.0, true);
    }

    // ------------------------------------------------------------------------------------------
    // Lane 4 - SplineMesh (experimental; coverage-gap item 8). Geometry is built here; the
    // Chaos precondition probe + bake happen in settle once the Chaos body exists.
    // ------------------------------------------------------------------------------------------
    private void DoBuildLane_Spline_Geometry(UStaticMesh InCube)
    {
        // Component origin pulled to X=-600 so the spline midpoint lands near the lane center.
        auto CompWorld = _Origin + FVector(-600.0, _LaneY_Spline, _LaneCenterZ);
        _SplineActor = SpawnActor(AActor, CompWorld);
        if (ck::Is_NOT_Valid(_SplineActor))
        {
            ck::Trace("StaticBakeGym: [FAIL] SplineMesh lane - could not spawn host actor");
            return;
        }

        auto Spline = USplineMeshComponent::Create(_SplineActor);
        // The plain-AActor host is rootless, so the ACTOR transform reads (0,0,0) in the
        // outliner forever - the component below carries the real world position. Same story
        // for the HISM lane hosts.
        Spline.SetWorldLocation(CompWorld);
        Spline.SetMobility(EComponentMobility::Movable);
        Spline.SetStaticMesh(InCube);
        Spline.SetCollisionProfileName(n"BlockAll");
        Spline.SetStartAndEnd(FVector(0.0, 0.0, 0.0), FVector(400.0, 0.0, 0.0),
                              FVector(400.0, 0.0, 0.0), FVector(400.0, 400.0, 0.0));

        // Cubic-Hermite midpoint (t=0.5) of the start/end/tangents above ~ local (200,-50,0).
        _SplineMidWorld = CompWorld + FVector(200.0, -50.0, 0.0);
    }

    private void DoResolveSplineLane()
    {
        if (ck::Is_NOT_Valid(_SplineActor)) { return; }

        auto Top = FVector(_SplineMidWorld.X, _SplineMidWorld.Y, _SplineMidWorld.Z + _WitnessTopZ);
        auto Bottom = FVector(_SplineMidWorld.X, _SplineMidWorld.Y, _SplineMidWorld.Z - _WitnessBottomZ);

        // Precondition probe: if Chaos misses, runtime collision never cooked - do NOT bake
        // (a bodyless bake fires a CK_ENSURE by design). Editor-authored spline meshes remain
        // the coverage path for this branch.
        if (DoChaosHits(Top, Bottom) == false)
        {
            ck::Trace("StaticBakeGym: [GAP] SplineMesh runtime collision did not cook - lane skipped (editor-authored spline meshes remain the coverage path)");
            _SkippedGapCount += 1;
            return;
        }

        auto NumBaked = utils_jolt_static_world::Request_BakeActor(_SplineActor);
        ck::Trace(f"StaticBakeGym: SplineMesh baked - {NumBaked} body/bodies");
        _LaneActors.Add(_SplineActor);
        DoAddWitness("SplineMesh parity", Top, Bottom, false);
    }

    // ------------------------------------------------------------------------------------------
    // Lane 4b - authored SplineMesh scan: actors tagged CkJoltGym.AuthoredSpline (created once
    // in the editor by Ck.Gym.AuthorJoltStaticBakeContent). Editor machinery cooks the deformed
    // collision, so THIS lane exercises the spline extraction branch - the runtime lane above
    // documents the runtime-cook gap. The witness fires through the S-curve midpoint: local
    // (200, -50, 0) for the authored curve; keep in sync with CkGymJoltStaticBakeAuthoring.cpp.
    // ------------------------------------------------------------------------------------------
    private void DoScanLane_AuthoredSplines()
    {
        auto AllActors = TArray<AActor>();
        GetAllActorsOfClass(AActor, AllActors);

        auto NumFound = 0;
        for (auto Actor : AllActors)
        {
            if (ck::Is_NOT_Valid(Actor)) { continue; }
            if (!Actor.ActorHasTag(n"CkJoltGym.AuthoredSpline")) { continue; }

            NumFound += 1;
            auto MidWorld = Actor.GetActorLocation() + FVector(200.0, -50.0, 0.0);
            auto Top = FVector(MidWorld.X, MidWorld.Y, MidWorld.Z + _WitnessTopZ);
            auto Bottom = FVector(MidWorld.X, MidWorld.Y, MidWorld.Z - _WitnessBottomZ);
            DoAddWitness(f"SplineMesh authored {Actor.GetName()}", Top, Bottom, false);
        }

        if (NumFound == 0)
        {
            ck::Trace("StaticBakeGym: no authored spline meshes - run Ck.Gym.AuthorJoltStaticBakeContent in the editor (TestGyms level, then save) to exercise the spline bake branch");
        }
    }

    // ------------------------------------------------------------------------------------------
    // Lane 5 - Volume/Brush scan: the only lane exercising the LEVEL-SWEEP bake path (brushes
    // cannot be authored at runtime). Scans authored volumes; a witness per found actor.
    // ------------------------------------------------------------------------------------------
    private void DoScanLane_Volumes()
    {
        auto Volumes = TArray<AVolume>();
        GetAllActorsOfClass(AVolume, Volumes);

        if (Volumes.Num() == 0)
        {
            ck::Trace("StaticBakeGym: no volumes/brushes in this level - place a BlockingVolume in TestGyms_CkTests_Level to exercise the brush bake branch");
            return;
        }

        for (auto Volume : Volumes)
        {
            if (ck::Is_NOT_Valid(Volume)) { continue; }
            DoAddBoundsWitness(Volume, f"Volume {Volume.GetName()}");
        }
    }

    // ------------------------------------------------------------------------------------------
    // Lane 6 - Landscape scan: same scan pattern for authored landscapes.
    // ------------------------------------------------------------------------------------------
    private void DoScanLane_Landscapes()
    {
        auto Landscapes = TArray<ALandscapeProxy>();
        GetAllActorsOfClass(ALandscapeProxy, Landscapes);

        if (Landscapes.Num() == 0)
        {
            ck::Trace("StaticBakeGym: no landscapes in this level - run Ck.Gym.AuthorJoltStaticBakeContent in the editor (TestGyms level, then save) to exercise the landscape bake branch");
            return;
        }

        for (auto Landscape : Landscapes)
        {
            if (ck::Is_NOT_Valid(Landscape)) { continue; }
            DoAddBoundsWitness(Landscape, f"Landscape {Landscape.GetName()}");
        }
    }

    // Fires a down-ray through the actor's world-space bounds origin, bounded to the actor's
    // own Z band (+/- margin) so a miss never reaches the gym floor below.
    //
    // Only actors Chaos itself collides with get a witness: a differential probe traces the
    // ray twice - once normally, once ignoring the scanned actor. If ignoring it changes
    // nothing, the "hit" was unrelated geometry inside the actor's bounds (the transient
    // DefaultPhysicsVolume, a no-collision NavMeshBounds) and a parity row would mislead.
    private void DoAddBoundsWitness(AActor InActor, FString InLabel)
    {
        FVector Origin;
        FVector Extent;
        InActor.GetActorBounds(false, Origin, Extent);

        auto Top = FVector(Origin.X, Origin.Y, Origin.Z + Extent.Z + 50.0);
        auto Bottom = FVector(Origin.X, Origin.Y, Origin.Z - Extent.Z - 50.0);

        TArray<AActor> NoIgnores;
        FHitResult HitWith;
        auto DidHitWith = System::LineTraceSingle(
            Top, Bottom, ETraceTypeQuery::Visibility, false, NoIgnores,
            EDrawDebugTrace::None, HitWith, true);

        TArray<AActor> IgnoreScanned;
        IgnoreScanned.Add(InActor);
        FHitResult HitWithout;
        auto DidHitWithout = System::LineTraceSingle(
            Top, Bottom, ETraceTypeQuery::Visibility, false, IgnoreScanned,
            EDrawDebugTrace::None, HitWithout, true);

        auto ActorItselfBlocks = DidHitWith &&
            (!DidHitWithout || HitWith.ImpactPoint.Distance(HitWithout.ImpactPoint) > 1.0);

        if (!ActorItselfBlocks)
        {
            ck::Trace(f"StaticBakeGym: [INERT] {InLabel} - not Chaos-blocking itself (no parity witness)");
            return;
        }

        DoAddWitness(InLabel, Top, Bottom, false);
    }

    // ------------------------------------------------------------------------------------------
    // Witness plumbing
    // ------------------------------------------------------------------------------------------
    private void DoAddDownWitness(FString InLabel, float InWorldX, float InWorldY, bool InExpectMiss)
    {
        auto Top = FVector(InWorldX, InWorldY, _Origin.Z + _LaneCenterZ + _WitnessTopZ);
        auto Bottom = FVector(InWorldX, InWorldY, _Origin.Z + _LaneCenterZ - _WitnessBottomZ);
        DoAddWitness(InLabel, Top, Bottom, InExpectMiss);
    }

    private void DoAddWitness(FString InLabel, FVector InStart, FVector InEnd, bool InExpectMiss)
    {
        auto W = FCkJoltStaticBake_Witness();
        W.Label = InLabel;
        W.Start = InStart;
        W.End = InEnd;
        W.ExpectMiss = InExpectMiss;
        _Witnesses.Add(W);
    }

    private void DoBakeAndReport(AActor InActor, int32 InExpected, FString InLaneName)
    {
        auto NumBaked = utils_jolt_static_world::Request_BakeActor(InActor);
        if (NumBaked == InExpected)
        {
            ck::Trace(f"StaticBakeGym: [PASS] {InLaneName} bake - {NumBaked} body/bodies (expected {InExpected})");
        }
        else
        {
            ck::Trace(f"StaticBakeGym: [FAIL] {InLaneName} bake - {NumBaked} body/bodies (expected {InExpected})");
        }
        _LaneActors.Add(InActor);
    }

    private bool DoChaosHits(FVector InStart, FVector InEnd)
    {
        TArray<AActor> IgnoreActors;
        FHitResult ChaosHit;
        return System::LineTraceSingle(
            InStart, InEnd, ETraceTypeQuery::Visibility, false, IgnoreActors,
            EDrawDebugTrace::None, ChaosHit, true);
    }

    private void DoRunAllWitnesses()
    {
        _LastTotal = 0;
        _LastPass = 0;
        _LastFail = 0;
        _LastExpectedMiss = 0;

        for (auto Witness : _Witnesses)
        {
            DoRunWitness(Witness);
        }
    }

    private void DoRunWitness(FCkJoltStaticBake_Witness InWitness)
    {
        _LastTotal += 1;

        // Channel-filtered query, NOT the unfiltered static-world introspection ray - Chaos's
        // line trace below is Visibility-filtered, so true parity must exercise Jolt's channel
        // filter too. (An ignore-everything collision signature is invisible to the unfiltered
        // ray: the landscape bug hid behind exactly that.)
        auto WitnessFilter = FCk_Jolt_QueryFilter();
        WitnessFilter.Set_Channel(ECollisionChannel::ECC_Visibility);
        WitnessFilter.Set_MinResponse(ECk_Jolt_PairInteraction::Block);
        auto JoltHit = utils_jolt_query::Get_RayCast(InWitness.Start, InWitness.End, WitnessFilter);
        auto JoltDidHit = JoltHit.Get_HasHit();

        TArray<AActor> IgnoreActors;
        FHitResult ChaosHit;
        auto ChaosDidHit = System::LineTraceSingle(
            InWitness.Start, InWitness.End, ETraceTypeQuery::Visibility, false, IgnoreActors,
            EDrawDebugTrace::None, ChaosHit, true);

        // PASS: both hit and positions agree within 1uu.
        if (JoltDidHit && ChaosDidHit && JoltHit.Get_Position().Distance(ChaosHit.Location) <= 1.0)
        {
            _LastPass += 1;
            ck::Trace(f"StaticBakeGym: [PASS] {InWitness.Label} - Jolt {JoltHit.Get_Position()} == Chaos {ChaosHit.Location}");
            return;
        }

        // PASS: both missed and the witness expected a miss.
        if (JoltDidHit == false && ChaosDidHit == false && InWitness.ExpectMiss)
        {
            _LastPass += 1;
            _LastExpectedMiss += 1;
            ck::Trace(f"StaticBakeGym: [PASS] {InWitness.Label} - both missed (expected miss)");
            return;
        }

        // Everything else FAILs - report both hit-flags and both positions.
        _LastFail += 1;
        ck::Trace(f"StaticBakeGym: [FAIL] {InWitness.Label} - Jolt(hit={JoltDidHit}) {JoltHit.Get_Position()} vs Chaos(hit={ChaosDidHit}) {ChaosHit.Location}");
    }

    private void DoLogWitnessSummary(FString InContext)
    {
        auto NumBodies = utils_jolt_static_world::Get_NumStaticBodies();
        ck::Trace(f"StaticBakeGym: witnesses [{InContext}] - total {_LastTotal} / PASS {_LastPass} / FAIL {_LastFail} / expected-miss {_LastExpectedMiss} / skipped-gap {_SkippedGapCount} | NumStaticBodies {NumBodies}");
    }

    // ------------------------------------------------------------------------------------------
    // Continuous view-ray - fired every frame from the player's view against the FULL Jolt
    // query layer (baked statics + dynamic bodies), drawn green on hit / red on miss. The hit
    // marker shows the impact point, surface normal, and the resolved entity (baked statics
    // resolve to their JoltStaticActor attribution entity).
    // ------------------------------------------------------------------------------------------
    UFUNCTION()
    private void OnViewRayTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!_ViewRayEnabled)
        { return; }

        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        { return; }

        auto ViewRot = GetControlRotation();
        auto Forward = ViewRot.GetForwardVector();

        // The camera sits at the pawn origin (ADefaultPawn); pull the beam origin forward and
        // down so it reads as a beam instead of a dot in the view center.
        auto CamLoc = ViewPawn.GetActorLocation();
        auto Start = CamLoc + Forward * 60.0 - ViewRot.GetUpVector() * 25.0;
        auto End = CamLoc + Forward * _ViewRayRange;

        auto Filter = FCk_Jolt_QueryFilter();
        Filter.Set_Channel(ECollisionChannel::ECC_Visibility);
        Filter.Set_MinResponse(ECk_Jolt_PairInteraction::Block);

        auto Hit = utils_jolt_query::Get_RayCast(Start, End, Filter);

        if (Hit.Get_HasHit())
        {
            auto HitPos = Hit.Get_Position();
            auto HitColor = FLinearColor(0.1, 1.0, 0.1, 1.0);
            UCk_Utils_DebugDraw_UE::DrawDebugLine(Start, HitPos, HitColor, 0.0, 1.5);
            UCk_Utils_DebugDraw_UE::DrawDebugSphere(HitPos, 10.0, 12, HitColor, 0.0, 1.0);
            UCk_Utils_DebugDraw_UE::DrawDebugLine(HitPos, HitPos + Hit.Get_Normal() * 75.0,
                FLinearColor(1.0, 0.9, 0.1, 1.0), 0.0, 1.0);

            auto HitEntity = Hit.Get_Entity();
            auto Label = FString("<no entity>");
            // NOT an f-string: FCk_Handle (typesafe OR generic) is not appendable in AS string
            // interpolation - it compiles but throws "Invalid type to append to string" at
            // runtime. The entity's DebugName is the label we actually want anyway.
            if (ck::IsValid(HitEntity))
            { Label = utils_handle::Get_DebugName(HitEntity).ToString(); }
            UCk_Utils_DebugDraw_UE::DrawDebugString(HitPos + FVector(0.0, 0.0, 25.0), Label,
                FLinearColor(1.0, 1.0, 1.0, 1.0), 0.0);
        }
        else
        {
            UCk_Utils_DebugDraw_UE::DrawDebugLine(Start, End, FLinearColor(1.0, 0.15, 0.15, 1.0), 0.0, 0.75);
        }
    }

    // Mirrors the gym base's private WaitOneFrame - schedules a one-frame timer on the gym's
    // own entity and invokes InCallbackName (FCk_Delegate_Timer signature) once it fires.
    private void DoWaitOneFrame(FName InCallbackName)
    {
        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto Timer = utils_timer::Add(_GymEntity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, InCallbackName));
    }

    // ------------------------------------------------------------------------------------------
    // Console commands
    // ------------------------------------------------------------------------------------------
    UFUNCTION(Exec, DisplayName="Jolt StaticBake - Run Witnesses")
    void Ck_GymJoltStaticBake_RunWitnesses()
    {
        DoRunAllWitnesses();
        DoLogWitnessSummary("manual re-run");
    }

    UFUNCTION(Exec, DisplayName="Jolt StaticBake - Toggle View Ray")
    void Ck_GymJoltStaticBake_ToggleRay()
    {
        _ViewRayEnabled = !_ViewRayEnabled;
        if (_ViewRayEnabled)
        { ck::Trace("StaticBakeGym: view-ray ON"); }
        else
        { ck::Trace("StaticBakeGym: view-ray OFF"); }
    }

    UFUNCTION(Exec, DisplayName="Jolt StaticBake - Rebake")
    void Ck_GymJoltStaticBake_Rebake()
    {
        ck::Trace("StaticBakeGym: Rebake - removing all runtime-baked lane bodies");
        for (auto Actor : _LaneActors)
        {
            utils_jolt_static_world::Request_RemoveActor(Actor);
        }

        ck::Trace("StaticBakeGym: Rebake - witnesses post-remove (lanes 1-4 Jolt-side MISS is the EXPECTED observation)");
        DoRunAllWitnesses();
        DoLogWitnessSummary("post-remove (expected Jolt-side misses)");

        ck::Trace("StaticBakeGym: Rebake - re-baking all runtime lanes");
        for (auto Actor : _LaneActors)
        {
            auto NumBaked = utils_jolt_static_world::Request_BakeActor(Actor);
            ck::Trace(f"StaticBakeGym: Rebake - {NumBaked} body/bodies for {Actor.GetName()}");
        }

        ck::Trace("StaticBakeGym: Rebake - witnesses post-rebake (parity should be restored)");
        DoRunAllWitnesses();
        DoLogWitnessSummary("post-rebake");
    }
}
