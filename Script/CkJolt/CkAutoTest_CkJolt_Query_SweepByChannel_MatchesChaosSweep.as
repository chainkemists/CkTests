// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: SHAPE SWEEP PARITY VS CHAOS
//============================================================================
//
// A sphere swept down onto a baked cube must stop where Chaos's sphere sweep
// stops (both engines read the same authored box collision):
//   1. Baked BlockAll cube.
//   2. Jolt Get_ShapeCast (sphere r=50) vs Chaos SphereTraceSingle, same ray.
//   3. Contact positions agree within 2uu.
//============================================================================

class UCk_AutoTest_CkJolt_Query_SweepByChannel_MatchesChaosSweep : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AStaticMeshActor _CubeActor;
    private FVector _CubeCenter = FVector(0.0, 15000.0, 300.0);

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

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_CubeActor), 1,
            "Cube bakes one body");

        auto SweepStart = _CubeCenter + FVector(0.0, 0.0, 600.0);
        auto SweepEnd = _CubeCenter;

        // ---- Jolt sphere sweep ------------------------------------------------------------------
        auto SphereShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        SphereShape.Set_Radius(50.0f);

        auto Filter = FCk_Jolt_QueryFilter();
        Filter.Set_Channel(ECollisionChannel::ECC_Visibility);
        Filter.Set_MinResponse(ECk_Jolt_PairInteraction::Block);

        auto JoltHit = utils_jolt_query::Get_ShapeCast(
            SweepStart, SweepEnd, FRotator::ZeroRotator, SphereShape, Filter);
        Assert_True(JoltHit.Get_HasHit(), "Jolt sphere sweep should hit the baked cube");

        // ---- Chaos sphere sweep -----------------------------------------------------------------
        TArray<AActor> IgnoreActors;
        FHitResult ChaosHit;
        auto ChaosDidHit = System::SphereTraceSingle(
            SweepStart, SweepEnd, 50.0, ETraceTypeQuery::Visibility, false, IgnoreActors,
            EDrawDebugTrace::None, ChaosHit, true);
        Assert_True(ChaosDidHit, "Chaos sphere sweep should hit the cube actor");

        if (JoltHit.Get_HasHit() && ChaosDidHit)
        {
            // Both read the same authored box: contact points must agree tightly.
            Assert_True(JoltHit.Get_Position().Distance(ChaosHit.ImpactPoint) <= 2.0,
                f"Sweep parity: Jolt {JoltHit.Get_Position()} vs Chaos {ChaosHit.ImpactPoint}");
        }

        FinishSuccess();
    }
}
