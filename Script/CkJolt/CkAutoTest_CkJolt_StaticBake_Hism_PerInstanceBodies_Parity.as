// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: STATIC BAKE, SPARSE HISM -> PER-INSTANCE BODIES
//============================================================================
//
// Below the compound threshold (default 32), instanced meshes bake one Jolt
// body PER INSTANCE, all sharing a single cached shape:
//   1. HISM with 8 cube instances in a row.
//   2. Bake -> exactly 8 bodies, exactly 1 unique shape in the cache.
//   3. Down-rays over instance 0 and instance 7 both hit at cube-top height.
//============================================================================

class UCk_AutoTest_CkJolt_StaticBake_Hism_PerInstanceBodies_Parity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AActor _HismActor;
    private FVector _Origin = FVector(0.0, 3000.0, 300.0);
    private float _Spacing = 300.0;
    private int32 _NumInstances = 8;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!IsValid(Cube))
        {
            FinishFailure("Failed to load /Engine/BasicShapes/Cube.Cube");
            return;
        }

        _HismActor = SpawnActor(AActor, _Origin);

        auto Hism = UHierarchicalInstancedStaticMeshComponent::Create(_HismActor);
        // A plain AActor has no root component - place the created component explicitly.
        Hism.SetWorldLocation(_Origin);
        Hism.SetStaticMesh(Cube);
        Hism.SetCollisionProfileName(n"BlockAll");

        for (int32 Index = 0; Index < _NumInstances; ++Index)
        {
            // Unique per-test scale (1.5) => a fresh shape-cache key regardless of which tests
            // baked scale-1 cubes earlier in this PIE session (the cache is subsystem-lifetime).
            auto InstanceTransform = FTransform(
                FRotator::ZeroRotator, FVector(Index * _Spacing, 0.0, 0.0), FVector(1.5, 1.5, 1.5));
            Hism.AddInstance(InstanceTransform, false);
        }

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto ShapesBefore = utils_jolt_static_world::Get_NumUniqueShapes();

        auto NumBaked = utils_jolt_static_world::Request_BakeActor(_HismActor);
        Assert_Equals_Int(NumBaked, _NumInstances,
            "Sparse HISM (below compound threshold) should bake one body per instance");

        auto ShapesAfter = utils_jolt_static_world::Get_NumUniqueShapes();
        Assert_Equals_Int(ShapesAfter - ShapesBefore, 1,
            "All instances share ONE cached Jolt shape");

        // Instances live at _Origin + local offsets (component at actor origin, identity rotation).
        for (int32 Index = 0; Index < _NumInstances; Index += _NumInstances - 1)
        {
            auto InstanceCenter = _Origin + FVector(Index * _Spacing, 0.0, 0.0);
            auto Hit = utils_jolt_static_world::Get_RayCastStaticWorld(
                InstanceCenter + FVector(0.0, 0.0, 500.0), InstanceCenter - FVector(0.0, 0.0, 500.0));

            Assert_True(Hit.Get_HasHit(), f"Down-ray over instance {Index} should hit");
            if (Hit.Get_HasHit())
            {
                // Engine cube is 100uu; instance scale 1.5 -> top at center Z + 75.
                Assert_True(Math::Abs(Hit.Get_Position().Z - (_Origin.Z + 75.0)) <= 1.0,
                    f"Instance {Index} hit at Z={Hit.Get_Position().Z}, expected ~{_Origin.Z + 75.0}");
            }
        }

        FinishSuccess();
    }
}
