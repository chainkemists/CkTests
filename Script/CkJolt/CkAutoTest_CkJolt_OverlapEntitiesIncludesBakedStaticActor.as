// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: OVERLAP ENTITIES INCLUDES BAKED STATIC ACTOR
//============================================================================
//
// Get_OverlapEntities resolves EVERY hit body's user-data to a live entity —
// baked static-world bodies carry their source actor's JoltStaticActor
// attribution entity id, so a baked cube overlapping the query region comes
// back as a real entity alongside dynamic JoltBodies (ECS-first: all Jolt
// bodies have an entity). Only user-data 0 is dropped (never resolved to the
// registry's transient root — the raw-id-0 regression this still pins).
//
//   1. Bake a static cube (Request_BakeActor) AND add a Kinematic JoltBody box
//      overlapping the same region (both BlockAll so the Visibility query sees them).
//   2. Get_OverlapEntities over the overlap region -> EXACTLY TWO entities:
//      the JoltBody entity AND the cube's JoltStaticActor entity (which names
//      its source actor).
//   3. Get_RayCastMulti through both -> >= 2 hits, sorted near-to-far.
//   4. Clean up: un-bake + destroy the actor (the ECS box entity auto-cleans).
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_OverlapEntitiesIncludesBakedStaticActor : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _BoxEntity;
    private AStaticMeshActor _CubeActor;

    private float _ParkY = 60000.0;
    private FVector _CubeCenter = FVector(0.0, 60000.0, 300.0);   // baked cube, half-extent 100 (scale 2)
    private FVector _BoxCenter = FVector(100.0, 60000.0, 300.0);  // JoltBody box, half-extent 100 (overlaps cube)

    private float _Elapsed = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

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
        _CubeActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _CubeActor.StaticMeshComponent.SetStaticMesh(Cube);
        _CubeActor.SetActorScale3D(FVector(2.0, 2.0, 2.0));
        _CubeActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        // ---- Kinematic JoltBody box overlapping the same region -------------------------------
        _BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _BoxEntity.Request_OverrideToSelf();
        utils_transform::Add(_BoxEntity, FTransform(FRotator::ZeroRotator, _BoxCenter),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(100.0, 100.0, 100.0));
        auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Kinematic);   // stays put, overlapping the baked cube
        BoxParams.Set_CollisionProfileName(n"BlockAll");
        utils_jolt_body::Add(_BoxEntity, BoxParams);

        // Let the actor's physics state settle before baking (Chaos body creation).
        WaitOneFrame(n"OnSettled");
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_CubeActor), 1,
            "The static cube should bake exactly one Jolt body");

        // Wait for the JoltBody setup to add the body to the Jolt world before querying.
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        if (_Elapsed < 0.2)
        { return; }

        // ---- Overlap over the shared region: BOTH entities come back --------------------------
        auto OverlapFilter = FCk_Jolt_QueryFilter();
        OverlapFilter.Set_Channel(ECollisionChannel::ECC_Visibility);
        OverlapFilter.Set_MinResponse(ECk_Jolt_PairInteraction::Overlap);

        auto QueryShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        QueryShape.Set_HalfExtents(FVector(20.0, 20.0, 20.0));

        auto Overlapped = utils_jolt_query::Get_OverlapEntities(
            FVector(50.0, _ParkY, 300.0), FRotator::ZeroRotator, QueryShape, OverlapFilter);

        Assert_Equals_Int(Overlapped.Num(), 2,
            f"Overlap should return the JoltBody entity AND the baked cube's JoltStaticActor entity (got {Overlapped.Num()})");

        auto FoundBoxEntity = false;
        auto StaticSide = FCk_Handle();
        for (int32 i = 0; i < Overlapped.Num(); i++)
        {
            if (Overlapped[i] == _BoxEntity)
            { FoundBoxEntity = true; }
            else
            { StaticSide = Overlapped[i]; }
        }

        Assert_True(FoundBoxEntity, "Overlap results must include the live JoltBody entity");
        Assert_True(ck::IsValid(StaticSide),
            "Overlap results must include a second, valid entity for the baked cube (never the transient root)");

        if (ck::IsValid(StaticSide))
        {
            auto StaticActor = utils_jolt_static_actor::DoCastChecked(StaticSide);
            Assert_True(utils_jolt_static_actor::Get_SourceActorName(StaticActor) == _CubeActor.GetName(),
                "The second overlap entity must be the baked cube's JoltStaticActor attribution entity");
        }

        // ---- Multi-raycast through both: both are query targets, sorted near-to-far -----------
        auto BlockFilter = FCk_Jolt_QueryFilter();
        BlockFilter.Set_Channel(ECollisionChannel::ECC_Visibility);
        BlockFilter.Set_MinResponse(ECk_Jolt_PairInteraction::Block);

        auto Hits = utils_jolt_query::Get_RayCastMulti(
            FVector(-400.0, _ParkY, 300.0), FVector(400.0, _ParkY, 300.0), BlockFilter);

        Assert_True(Hits.Num() >= 2,
            f"A ray through the baked cube AND the JoltBody should return >= 2 hits (got {Hits.Num()})");
        if (Hits.Num() >= 2)
        {
            Assert_True(Hits[0].Get_Fraction() <= Hits[1].Get_Fraction(),
                f"Multi-raycast hits must be sorted near-to-far (frac0={Hits[0].Get_Fraction()}, frac1={Hits[1].Get_Fraction()})");
        }

        // ---- Shared-session cleanup: un-bake + destroy the actor ------------------------------
        utils_jolt_static_world::Request_RemoveActor(_CubeActor);
        _CubeActor.DestroyActor();

        FinishSuccess();
    }
}
