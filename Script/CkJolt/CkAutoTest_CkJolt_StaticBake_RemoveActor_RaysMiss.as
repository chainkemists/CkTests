// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: STATIC BAKE ADD/REMOVE LIFECYCLE
//============================================================================
//
// Pins the add/remove lockstep the level-streaming path relies on (streaming a
// real sublevel needs authored content — this runtime proxy exercises the same
// body-container bookkeeping):
//   1. Bake a cube -> body count rises, down-ray hits.
//   2. Request_RemoveActor -> body count returns to baseline, down-ray misses.
//============================================================================

class UCk_AutoTest_CkJolt_StaticBake_RemoveActor_RaysMiss : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AStaticMeshActor _CubeActor;
    private FVector _CubeCenter = FVector(0.0, 0.0, 5300.0);
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

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _BaselineBodies = utils_jolt_static_world::Get_NumStaticBodies();

        auto NumBaked = utils_jolt_static_world::Request_BakeActor(_CubeActor);
        Assert_Equals_Int(NumBaked, 1, "Cube should bake exactly one body");
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies + 1,
            "Body count should rise by one after bake");

        auto DownStart = _CubeCenter + FVector(0.0, 0.0, 500.0);
        auto DownEnd = _CubeCenter - FVector(0.0, 0.0, 500.0);

        auto HitWhileBaked = utils_jolt_static_world::Get_RayCastStaticWorld(DownStart, DownEnd);
        Assert_True(HitWhileBaked.Get_HasHit(), "Down-ray should hit while the cube is baked");

        // Attribution now flows through the hit's entity: resolve it to the JoltStaticActor surface.
        auto HitEntity = HitWhileBaked.Get_Entity();
        Assert_True(ck::IsValid(HitEntity), "Static hit should resolve to a live JoltStaticActor entity");
        auto HitStaticActor = utils_jolt_static_actor::DoCastChecked(HitEntity);
        Assert_True(utils_jolt_static_actor::Get_SourceActorName(HitStaticActor) == _CubeActor.GetName(),
            "Hit attribution should name the source actor");

        utils_jolt_static_world::Request_RemoveActor(_CubeActor);

        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies,
            "Body count should return to baseline after removal");

        auto HitAfterRemove = utils_jolt_static_world::Get_RayCastStaticWorld(DownStart, DownEnd);
        Assert_True(!HitAfterRemove.Get_HasHit(), "Down-ray should MISS after the actor's bodies are removed");

        FinishSuccess();
    }
}
