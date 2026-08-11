// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: UNREALCOMPONENT BAKE OPT-IN + TEARDOWN REMOVAL
//============================================================================
//
// The CkUnrealComponent opt-in path end-to-end — the exact scenario the
// feature exists for (an entity-hosted runtime ISM had NO Jolt body at all):
//   1. Entity + Transform + UnrealComponent(ISM) via the normal Add flow.
//   2. AFTER configuring the ISM (mesh, profile, instances), the caller opts
//      in via Request_BakeIntoJoltStaticWorld — a static-world ray now hits.
//   3. Destroying the OWNING ENTITY tears the component down, and teardown
//      removes the baked bodies with it — the ray misses again with no
//      explicit removal call.
//============================================================================

class UCk_AutoTest_CkJolt_UnrealComponent_BakeOptIn_TeardownRemoves : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_UnrealComponent _CompHandle;
    private FVector _Origin = FVector(0.0, 69000.0, 300.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _Owner = utils_entity_lifetime::Request_CreateEntity(InHandle);
        utils_transform::Add(_Owner, FTransform(FRotator::ZeroRotator, _Origin), ECk_Replication::DoesNotReplicate);

        const auto Params = utils_unreal_component::Make_Params(
            UInstancedStaticMeshComponent, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_BakedIsm");
        _CompHandle = utils_unreal_component::Add(_Owner, Params);

        // Component instantiation is deferred to the Setup processor.
        WaitUntil(n"Check_ComponentInstantiated", n"OnComponentReady");
    }

    UFUNCTION()
    private void Check_ComponentInstantiated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(utils_unreal_component::Get_Component(_CompHandle)));
    }

    UFUNCTION()
    private void OnComponentReady(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        auto Cube = Cast<UStaticMesh>(LoadObject(UStaticMesh, "/Engine/BasicShapes/Cube.Cube"));
        auto Ism = Cast<UInstancedStaticMeshComponent>(utils_unreal_component::Get_Component(_CompHandle));

        if (!IsValid(Cube) || !IsValid(Ism))
        {
            FinishFailure("cube mesh or hosted ISM unavailable");
            return;
        }

        // Configure FIRST, then opt in — baking before the instances exist would bake nothing.
        Ism.SetStaticMesh(Cube);
        Ism.SetCollisionProfileName(n"BlockAll");
        Ism.AddInstance(FTransform::Identity, false);

        utils_unreal_component::Request_BakeIntoJoltStaticWorld(_CompHandle);

        auto Hit = Do_RayOverOrigin();
        Assert_True(Hit.Get_HasHit(), "static-world ray hits the entity-hosted ISM after the bake opt-in");

        // Destroying the OWNER cascades the UnrealComponent teardown, which must remove the bodies.
        utils_entity_lifetime::Request_DestroyEntity(_Owner);
        WaitOneFrame(n"OnTornDown");
    }

    private FCk_Jolt_StaticWorldRayHit_Result Do_RayOverOrigin()
    {
        return utils_jolt_static_world::Get_RayCastStaticWorld(
            _Origin + FVector(0.0, 0.0, 500.0), _Origin - FVector(0.0, 0.0, 500.0));
    }

    UFUNCTION()
    private void OnTornDown(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(Do_RayOverOrigin().Get_HasHit() == false,
            "teardown removed the baked bodies — the ray misses with no explicit removal call");

        FinishSuccess();
    }
}
