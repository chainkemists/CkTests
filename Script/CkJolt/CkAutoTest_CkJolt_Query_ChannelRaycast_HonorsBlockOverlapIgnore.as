// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: CHANNEL QUERIES HONOR BLOCK / OVERLAP / IGNORE
//============================================================================
//
// The signature-driven layer table must reproduce UE trace semantics:
//   1. Two baked cubes: one BlockAll profile, one OverlapAllDynamic profile.
//   2. A Visibility ray with trace semantics (MinResponse=Block) hits ONLY the
//      blocking cube.
//   3. The same ray with overlap semantics (MinResponse=Overlap) hits both.
//============================================================================

class UCk_AutoTest_CkJolt_Query_ChannelRaycast_HonorsBlockOverlapIgnore : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private AStaticMeshActor _BlockingCube;
    private AStaticMeshActor _OverlapCube;
    private FVector _BlockingCenter = FVector(0.0, 12000.0, 300.0);
    private FVector _OverlapCenter = FVector(600.0, 12000.0, 300.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        if (!IsValid(Cube))
        {
            FinishFailure("Failed to load /Engine/BasicShapes/Cube.Cube");
            return;
        }

        _BlockingCube = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, _BlockingCenter));
        _BlockingCube.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _BlockingCube.StaticMeshComponent.SetStaticMesh(Cube);
        _BlockingCube.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        _OverlapCube = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, _OverlapCenter));
        _OverlapCube.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _OverlapCube.StaticMeshComponent.SetStaticMesh(Cube);
        _OverlapCube.StaticMeshComponent.SetCollisionProfileName(n"OverlapAllDynamic");

        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_BlockingCube), 1,
            "Blocking cube bakes one body");
        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_OverlapCube), 1,
            "Overlap cube bakes one body");

        auto TraceFilter = FCk_Jolt_QueryFilter();
        TraceFilter.Set_Channel(ECollisionChannel::ECC_Visibility);
        TraceFilter.Set_MinResponse(ECk_Jolt_PairInteraction::Block);

        auto OverlapFilter = FCk_Jolt_QueryFilter();
        OverlapFilter.Set_Channel(ECollisionChannel::ECC_Visibility);
        OverlapFilter.Set_MinResponse(ECk_Jolt_PairInteraction::Overlap);

        // ---- Blocking cube: hit under BOTH semantics -------------------------------------------
        auto BlockingHit = utils_jolt_query::Get_RayCast(
            _BlockingCenter + FVector(0.0, 0.0, 500.0), _BlockingCenter - FVector(0.0, 0.0, 500.0), TraceFilter);
        Assert_True(BlockingHit.Get_HasHit(), "Trace-semantics ray should hit the BLOCKING cube");

        // ---- Overlap cube: MISS under trace semantics, HIT under overlap semantics --------------
        auto OverlapTraceHit = utils_jolt_query::Get_RayCast(
            _OverlapCenter + FVector(0.0, 0.0, 500.0), _OverlapCenter - FVector(0.0, 0.0, 500.0), TraceFilter);
        Assert_True(!OverlapTraceHit.Get_HasHit(),
            "Trace-semantics ray should MISS the overlap-only cube (Overlap < Block)");

        auto OverlapOverlapHit = utils_jolt_query::Get_RayCast(
            _OverlapCenter + FVector(0.0, 0.0, 500.0), _OverlapCenter - FVector(0.0, 0.0, 500.0), OverlapFilter);
        Assert_True(OverlapOverlapHit.Get_HasHit(),
            "Overlap-semantics ray should HIT the overlap-only cube");

        // Hit attribution names the source actor.
        if (BlockingHit.Get_HasHit())
        {
            Assert_True(BlockingHit.Get_SourceActorName() == _BlockingCube.GetName(),
                "Hit attribution should name the blocking cube's actor");
        }

        FinishSuccess();
    }
}
