// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: STATIC BAKE, DENSE HISM -> ONE COMPOUND BODY
//============================================================================
//
// At/above the compound threshold (default 32), a dense instanced cluster
// bakes as ONE StaticCompoundShape body instead of flooding the broadphase:
//   1. HISM with 40 cube instances in a grid.
//   2. Bake -> exactly ONE body.
//   3. Down-rays over the first and last instances still hit (children intact).
//============================================================================

class UCk_AutoTest_CkJolt_StaticBake_Hism_CompoundCluster_SingleBody : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AActor _HismActor;
    private FVector _Origin = FVector(0.0, 6000.0, 300.0);
    private float _Spacing = 250.0;
    private int32 _GridSize = 8;
    private int32 _NumInstances = 40;

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
            auto Row = Math::IntegerDivisionTrunc(Index, _GridSize);
            auto Col = Index % _GridSize;
            auto InstanceTransform = FTransform(
                FRotator::ZeroRotator, FVector(Col * _Spacing, Row * _Spacing, 0.0), FVector::OneVector);
            Hism.AddInstance(InstanceTransform, false);
        }

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto NumBaked = utils_jolt_static_world::Request_BakeActor(_HismActor);
        Assert_Equals_Int(NumBaked, 1,
            "Dense HISM (at/above compound threshold) should bake ONE StaticCompoundShape body");

        // First instance (0,0) and last instance (row 4, col 7).
        auto FirstCenter = _Origin;
        auto LastCenter = _Origin + FVector(7 * _Spacing, 4 * _Spacing, 0.0);

        auto FirstHit = utils_jolt_static_world::Get_RayCastStaticWorld(
            FirstCenter + FVector(0.0, 0.0, 500.0), FirstCenter - FVector(0.0, 0.0, 500.0));
        Assert_True(FirstHit.Get_HasHit(), "Down-ray over the FIRST compound child should hit");

        auto LastHit = utils_jolt_static_world::Get_RayCastStaticWorld(
            LastCenter + FVector(0.0, 0.0, 500.0), LastCenter - FVector(0.0, 0.0, 500.0));
        Assert_True(LastHit.Get_HasHit(), "Down-ray over the LAST compound child should hit");

        // A ray BETWEEN instances (gap in the grid) must miss - the compound isn't a blob.
        auto GapCenter = _Origin + FVector(0.5 * _Spacing, 0.5 * _Spacing, 0.0);
        auto GapHit = utils_jolt_static_world::Get_RayCastStaticWorld(
            GapCenter + FVector(0.0, 0.0, 500.0), GapCenter - FVector(0.0, 0.0, 500.0));
        Assert_True(!GapHit.Get_HasHit(), "Down-ray in the grid gap should MISS (children are exact, not merged)");

        FinishSuccess();
    }
}
