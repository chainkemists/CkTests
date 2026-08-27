// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: UNREALCOMPONENT AUTOMATIC BAKE + MOVE RE-BAKE
//============================================================================
//
// The DEFAULT path every collision-bearing hosted component now takes:
//   1. Archetype-complete static mesh, NO policy set -> Automatic bakes it at
//      setup and the static-world ray hits.
//   2. Moving the owning entity re-bakes the bodies at the new pose - the old
//      location misses, the new one hits (teleports and store rearrangement
//      stay query-correct without any caller involvement).
//   3. Destroying the owner removes the bodies.
//============================================================================

class UCk_AutoTest_CkJolt_UnrealComponent_AutoBake_MoveRebakes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_UnrealComponent _CompHandle;
    private FVector _Origin = FVector(0.0, 75000.0, 300.0);
    private FVector _MovedTo = FVector(900.0, 75000.0, 300.0);

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

        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform(FRotator::ZeroRotator, _Origin), ECk_Replication::DoesNotReplicate);

        auto Archetype = NewObject(this, UStaticMeshComponent);
        Archetype.SetStaticMesh(Cube);
        Archetype.SetMobility(EComponentMobility::Movable);
        Archetype.SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
        Archetype.SetCollisionProfileName(n"BlockAll");

        // Deliberately NO Set_StaticWorldBakePolicy - Automatic is the default under test.
        auto Params = utils_unreal_component::Make_Params_FromArchetype(
            Archetype, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_AutoBakedMesh");
        _CompHandle = utils_unreal_component::Add(_Owner, Params);

        WaitUntil(n"Check_ComponentInstantiated", n"OnComponentReady");
    }

    UFUNCTION()
    private void Check_ComponentInstantiated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(utils_unreal_component::Get_Component(_CompHandle)));
    }

    private FCk_Jolt_StaticWorldRayHit_Result Do_RayOver(FVector InPoint)
    {
        return utils_jolt_static_world::Get_RayCastStaticWorld(
            InPoint + FVector(0.0, 0.0, 500.0), InPoint - FVector(0.0, 0.0, 500.0));
    }

    UFUNCTION()
    private void OnComponentReady(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(Do_RayOver(_Origin).Get_HasHit(),
            "Automatic (the default, no policy set) baked the collision-bearing mesh - the ray hits");

        utils_transform::Request_SetTransform(_Owner.As_Transform(),
            FTransform(FRotator::ZeroRotator, _MovedTo));
        WaitOneFrame(n"OnMoved");
    }

    UFUNCTION()
    private void OnMoved(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(Do_RayOver(_Origin).Get_HasHit() == false,
            "moving the owner re-baked the bodies - the OLD location misses (no stale blocker)");
        Assert_True(Do_RayOver(_MovedTo).Get_HasHit(),
            "moving the owner re-baked the bodies - the NEW location hits");

        utils_entity_lifetime::Request_DestroyEntity(_Owner);
        WaitOneFrame(n"OnTornDown");
    }

    UFUNCTION()
    private void OnTornDown(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(Do_RayOver(_MovedTo).Get_HasHit() == false,
            "entity teardown removed the auto-baked bodies");

        FinishSuccess();
    }
}
