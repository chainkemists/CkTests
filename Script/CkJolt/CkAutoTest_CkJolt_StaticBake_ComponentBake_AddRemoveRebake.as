// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: STATIC BAKE, SINGLE COMPONENT ADD/REMOVE/REBAKE
//============================================================================
//
// Request_BakeComponent is the runtime surface for component-granular geometry
// (runtime-composed ISMs and friends). Contract under test:
//   1. Baking an 8-instance HISM COMPONENT adds one body per instance and a
//      down-ray over an instance hits.
//   2. Request_RemoveComponent frees exactly those bodies — the ray misses.
//   3. Re-baking after adding instances REPLACES the population (10 bodies,
//      a ray over the new instance hits, total body count reflects 10, not 18).
//============================================================================

class UCk_AutoTest_CkJolt_StaticBake_ComponentBake_AddRemoveRebake : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AActor _HismActor;
    private UHierarchicalInstancedStaticMeshComponent _Hism;
    private FVector _Origin = FVector(0.0, 66000.0, 300.0);
    private float _Spacing = 300.0;
    private int32 _NumInstances = 8;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!IsValid(Cube))
        {
            FinishFailure("Failed to load /Engine/BasicShapes/Cube.Cube");
            return;
        }

        _HismActor = SpawnActor(AActor, _Origin);

        _Hism = UHierarchicalInstancedStaticMeshComponent::Create(_HismActor);
        _Hism.SetWorldLocation(_Origin);
        _Hism.SetStaticMesh(Cube);
        _Hism.SetCollisionProfileName(n"BlockAll");

        for (int32 Index = 0; Index < _NumInstances; ++Index)
        {
            auto InstanceTransform = FTransform(
                FRotator::ZeroRotator, FVector(Index * _Spacing, 0.0, 0.0), FVector(1.0, 1.0, 1.0));
            _Hism.AddInstance(InstanceTransform, false);
        }

        WaitOneFrame(n"OnBakeAndRemove");
    }

    private FCk_Jolt_StaticWorldRayHit_Result Do_RayOverInstance(int32 InIndex)
    {
        auto InstanceCenter = _Origin + FVector(InIndex * _Spacing, 0.0, 0.0);
        return utils_jolt_static_world::Get_RayCastStaticWorld(
            InstanceCenter + FVector(0.0, 0.0, 500.0), InstanceCenter - FVector(0.0, 0.0, 500.0));
    }

    UFUNCTION()
    private void OnBakeAndRemove(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        // 1. Bake the component: one body per instance, ray hits.
        auto NumBaked = utils_jolt_static_world::Request_BakeComponent(_Hism);
        Assert_Equals_Int(NumBaked, _NumInstances, "component bake adds one body per HISM instance");
        Assert_True(Do_RayOverInstance(0).Get_HasHit(), "down-ray over instance 0 hits after the bake");

        // 2. Remove: the ray misses again.
        utils_jolt_static_world::Request_RemoveComponent(_Hism);
        Assert_True(Do_RayOverInstance(0).Get_HasHit() == false,
            "down-ray misses after Request_RemoveComponent");

        // 3. Re-bake with a larger population: REPLACES, not stacks.
        auto BodiesBeforeRebake = utils_jolt_static_world::Get_NumStaticBodies();

        for (int32 Index = _NumInstances; Index < _NumInstances + 2; ++Index)
        {
            auto InstanceTransform = FTransform(
                FRotator::ZeroRotator, FVector(Index * _Spacing, 0.0, 0.0), FVector(1.0, 1.0, 1.0));
            _Hism.AddInstance(InstanceTransform, false);
        }

        auto NumRebaked = utils_jolt_static_world::Request_BakeComponent(_Hism);
        Assert_Equals_Int(NumRebaked, _NumInstances + 2, "re-bake reflects the new instance population");

        auto BodiesAfterRebake = utils_jolt_static_world::Get_NumStaticBodies();
        Assert_Equals_Int(BodiesAfterRebake - BodiesBeforeRebake, _NumInstances + 2,
            "re-bake REPLACES the previous bodies — the total grows by the new population only");

        Assert_True(Do_RayOverInstance(_NumInstances + 1).Get_HasHit(),
            "down-ray over the newly-added instance hits after the re-bake");

        // Shared-session hygiene: free the bodies and the actor.
        utils_jolt_static_world::Request_RemoveComponent(_Hism);
        _HismActor.DestroyActor();

        FinishSuccess();
    }
}
