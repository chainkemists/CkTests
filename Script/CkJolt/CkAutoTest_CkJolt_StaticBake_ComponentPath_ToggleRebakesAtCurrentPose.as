// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: COMPONENT-PATH COLLISION-SYNC RE-BAKES AT POSE
//============================================================================
//
// A COMPONENT-path attribution entity (Request_BakeComponent — the surface
// CkUnrealComponent auto-bakes route through) must RE-BAKE on collision
// re-enable rather than re-adding its preserved bodies: a transform change
// while collision is off extracts nothing, so the preserved bodies' pose can
// be stale. Contract under test:
//   1. Bake a mesh component -> ray at pose A hits.
//   2. SetCollisionEnabled(NoCollision) -> body leaves the scene, ray misses.
//   3. Move the component to pose B WHILE disabled (nothing re-bakes).
//   4. SetCollisionEnabled(QueryAndPhysics) -> the sync re-bakes at pose B:
//      ray at B hits, ray at A misses, count is back up by exactly one.
//   5. Request_RemoveComponent -> baseline restored.
//============================================================================

class UCk_AutoTest_CkJolt_StaticBake_ComponentPath_ToggleRebakesAtCurrentPose : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AActor _MeshActor;
    private UStaticMeshComponent _MeshComp;
    private FVector _PoseA = FVector(0.0, -19000.0, 300.0);
    private FVector _PoseB = FVector(600.0, -19000.0, 300.0);
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

        _MeshActor = SpawnActor(AActor, _PoseA);

        _MeshComp = UStaticMeshComponent::Create(_MeshActor);
        _MeshComp.SetWorldLocation(_PoseA);
        _MeshComp.SetStaticMesh(Cube);
        _MeshComp.SetCollisionProfileName(n"BlockAll");

        WaitOneFrame(n"OnToggle");
    }

    private bool DownRayHitsAt(FVector InCenter)
    {
        return utils_jolt_static_world::Get_RayCastStaticWorld(
            InCenter + FVector(0.0, 0.0, 500.0), InCenter - FVector(0.0, 0.0, 500.0)).Get_HasHit();
    }

    UFUNCTION()
    private void OnToggle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _BaselineBodies = utils_jolt_static_world::Get_NumStaticBodies();

        auto NumBaked = utils_jolt_static_world::Request_BakeComponent(_MeshComp);
        Assert_Equals_Int(NumBaked, 1, "Mesh component should bake exactly one body");
        if (NumBaked != 1)
        {
            _MeshActor.DestroyActor();
            FinishFailure("Component did not reach the Jolt static world — re-bake assertions cannot run");
            return;
        }

        Assert_True(DownRayHitsAt(_PoseA), "Down-ray at pose A should hit after the bake");

        // ---- Flip out on component collision-disable --------------------------------------------
        _MeshComp.SetCollisionEnabled(ECollisionEnabled::NoCollision);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies,
            "Disabling component collision should flip the body out of the scene");
        Assert_True(!DownRayHitsAt(_PoseA), "Down-ray at pose A should MISS while collision is disabled");

        // ---- Move WHILE disabled: nothing may re-bake here --------------------------------------
        _MeshComp.SetWorldLocation(_PoseB);
        Assert_True(!DownRayHitsAt(_PoseB), "Nothing should be at pose B while collision is disabled");

        // ---- Re-enable: the sync must re-bake at the CURRENT pose, not re-add the stale bodies --
        _MeshComp.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies + 1,
            "Re-enabling should put exactly one body back into the scene");
        Assert_True(DownRayHitsAt(_PoseB), "Down-ray at pose B should hit — the re-bake used the current pose");
        Assert_True(!DownRayHitsAt(_PoseA), "Down-ray at pose A should MISS — the stale-pose body must not return");

        // ---- Removal still routes through the (replaced) attribution ----------------------------
        utils_jolt_static_world::Request_RemoveComponent(_MeshComp);
        Assert_Equals_Int(utils_jolt_static_world::Get_NumStaticBodies(), _BaselineBodies,
            "Request_RemoveComponent should restore the baseline body count");
        Assert_True(!DownRayHitsAt(_PoseB), "Down-ray at pose B should MISS after removal");

        _MeshActor.DestroyActor();

        FinishSuccess();
    }
}
