// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: STATIC BAKE, SIMPLE BOX, RAYCAST PARITY
//============================================================================
//
// Seed of the geometry-parity harness: a static-mesh cube (engine basic shape,
// simple box collision from AggGeom) baked into the Jolt static world must
// answer a raycast at the same position Chaos does.
//
//   1. Spawn a StaticMeshActor with /Engine/BasicShapes/Cube (100uu, scaled x2).
//   2. Request_BakeActor -> exactly one Jolt body.
//   3. Down-ray through the cube: Jolt hit position == Chaos hit position (<=1uu).
//   4. Side-ray: same.
//============================================================================

class UCk_AutoTest_CkJolt_StaticBake_SimpleBox_RaycastMatchesChaos : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AStaticMeshActor _CubeActor;
    // Unique parking spot (Y=9000) - shared-session discipline: content at the world origin outlives
    // its test if cleanup is missed and corrupts unrelated tests' traces (bit RaySense once).
    private FVector _CubeCenter = FVector(0.0, 9000.0, 300.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!IsValid(Cube))
        {
            FinishFailure("Failed to load /Engine/BasicShapes/Cube.Cube");
            return;
        }

        _CubeActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, _CubeCenter));
        if (!IsValid(_CubeActor))
        {
            FinishFailure("Failed to spawn AStaticMeshActor");
            return;
        }

        // Runtime-spawned actors must be Movable to accept a mesh; the ExplicitActor bake policy
        // accepts them (the caller declares them static-in-intent).
        _CubeActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _CubeActor.StaticMeshComponent.SetStaticMesh(Cube);
        _CubeActor.SetActorScale3D(FVector(2.0, 2.0, 2.0));
        _CubeActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        // Let physics state settle (Chaos body creation) before comparing.
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto NumBaked = utils_jolt_static_world::Request_BakeActor(_CubeActor);
        Assert_Equals_Int(NumBaked, 1, "A simple-collision cube should bake exactly ONE Jolt body");

        // ---- Down ray through the cube -------------------------------------------------------
        auto DownStart = _CubeCenter + FVector(0.0, 0.0, 700.0);
        auto DownEnd = _CubeCenter - FVector(0.0, 0.0, 700.0);

        auto JoltHit = utils_jolt_static_world::Get_RayCastStaticWorld(DownStart, DownEnd);
        Assert_True(JoltHit.Get_HasHit(), "Jolt down-ray should hit the baked cube");

        TArray<AActor> IgnoreActors;
        FHitResult ChaosHit;
        auto ChaosDidHit = System::LineTraceSingle(
            DownStart, DownEnd, ETraceTypeQuery::Visibility, false, IgnoreActors,
            EDrawDebugTrace::None, ChaosHit, true);
        Assert_True(ChaosDidHit, "Chaos down-ray should hit the cube actor");

        if (JoltHit.Get_HasHit() && ChaosDidHit)
        {
            Assert_True(JoltHit.Get_Position().Distance(ChaosHit.Location) <= 1.0,
                f"Down-ray parity: Jolt {JoltHit.Get_Position()} vs Chaos {ChaosHit.Location}");
        }

        // ---- Side ray -------------------------------------------------------------------------
        auto SideStart = _CubeCenter + FVector(-700.0, 0.0, 0.0);
        auto SideEnd = _CubeCenter + FVector(700.0, 0.0, 0.0);

        auto JoltSideHit = utils_jolt_static_world::Get_RayCastStaticWorld(SideStart, SideEnd);
        Assert_True(JoltSideHit.Get_HasHit(), "Jolt side-ray should hit the baked cube");

        FHitResult ChaosSideHit;
        auto ChaosSideDidHit = System::LineTraceSingle(
            SideStart, SideEnd, ETraceTypeQuery::Visibility, false, IgnoreActors,
            EDrawDebugTrace::None, ChaosSideHit, true);
        Assert_True(ChaosSideDidHit, "Chaos side-ray should hit the cube actor");

        if (JoltSideHit.Get_HasHit() && ChaosSideDidHit)
        {
            Assert_True(JoltSideHit.Get_Position().Distance(ChaosSideHit.Location) <= 1.0,
                f"Side-ray parity: Jolt {JoltSideHit.Get_Position()} vs Chaos {ChaosSideHit.Location}");
        }

        // Shared-session cleanup: un-bake the Jolt body and destroy the Chaos-collidable cube, or it
        // persists into every later test in the session (leaked here once and broke a RaySense trace).
        utils_jolt_static_world::Request_RemoveActor(_CubeActor);
        _CubeActor.DestroyActor();

        FinishSuccess();
    }
}
