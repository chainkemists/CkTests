// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: STATIC BAKE COLLISION-SYNC
//============================================================================
//
// Pins the collision-sync contract: engine collision state is the source of
// truth for whether a baked actor's static bodies are in the Jolt scene, with
// NO explicit Jolt call at the toggle site (the subsystem binds every tracked
// component's OnComponentCollisionSettingsChangedEvent at bake time).
//   1. Bake a cube -> body count rises, down-ray hits.
//   2. SetActorEnableCollision(false) -> count falls, ray misses (actor path).
//   3. SetActorEnableCollision(true)  -> count rises, ray hits again.
//   4. SetCollisionEnabled(NoCollision) on the COMPONENT -> falls/misses.
//   5. SetCollisionEnabled(QueryAndPhysics) -> rises/hits (component path).
//   6. Remove while flipped OUT -> count stays at baseline (the funnel must
//      destroy without double-removing) and nothing asserts.
//============================================================================

class UCk_AutoTest_CkJolt_StaticBake_CollisionToggle_SyncsScene : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AStaticMeshActor _CubeActor;
    private FVector _CubeCenter = FVector(0.0, -17000.0, 300.0);
    private int32 _BaselineBodies = 0;

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
        _CubeActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _CubeActor.StaticMeshComponent.SetStaticMesh(Cube);
        _CubeActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        WaitOneFrame(n"OnSettled");
    }

    private bool DownRayHits()
    {
        auto DownStart = _CubeCenter + FVector(0.0, 0.0, 500.0);
        auto DownEnd = _CubeCenter - FVector(0.0, 0.0, 500.0);
        return utils_jolt_static_world::Get_RayCastStaticWorld(DownStart, DownEnd).Get_HasHit();
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _BaselineBodies = utils_jolt_static_world::Get_NumStaticBodies();

        auto NumBaked = utils_jolt_static_world::Request_BakeActor(_CubeActor);
        Assert_Equals_Int(NumBaked, 1, "Cube should bake exactly one body");
        if (NumBaked != 1)
        {
            _CubeActor.DestroyActor();
            FinishFailure("Cube did not reach the Jolt static world — collision-sync assertions cannot run");
            return;
        }

        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies + 1,
            "Body count should rise by one after bake");
        Assert_True(DownRayHits(), "Down-ray should hit while the cube is baked");

        // ---- Actor-level toggle: SetActorEnableCollision drives the Jolt scene, no Jolt call ----
        _CubeActor.SetActorEnableCollision(false);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies,
            "Disabling ACTOR collision should flip the body out of the scene");
        Assert_True(!DownRayHits(), "Down-ray should MISS while actor collision is disabled");

        _CubeActor.SetActorEnableCollision(true);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies + 1,
            "Re-enabling ACTOR collision should flip the body back into the scene");
        Assert_True(DownRayHits(), "Down-ray should hit again after actor collision is re-enabled");

        // ---- Component-level toggle: SetCollisionEnabled routes through the same event ----------
        _CubeActor.StaticMeshComponent.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies,
            "Disabling COMPONENT collision should flip the body out of the scene");
        Assert_True(!DownRayHits(), "Down-ray should MISS while component collision is disabled");

        _CubeActor.StaticMeshComponent.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies + 1,
            "Re-enabling COMPONENT collision should flip the body back into the scene");
        Assert_True(DownRayHits(), "Down-ray should hit again after component collision is re-enabled");

        // ---- Removal while flipped OUT: the funnel destroys without double-removing --------------
        _CubeActor.StaticMeshComponent.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies,
            "Body should be out of the scene before the flipped-out removal");

        utils_jolt_static_world::Request_RemoveActor(_CubeActor);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies,
            "Removing a flipped-out actor should leave the count at baseline (no double-decrement)");
        Assert_True(!DownRayHits(), "Down-ray should still MISS after the flipped-out removal");

        _CubeActor.DestroyActor();

        FinishSuccess();
    }
}
