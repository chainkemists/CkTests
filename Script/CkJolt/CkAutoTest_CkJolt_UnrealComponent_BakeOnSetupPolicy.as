// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: UNREALCOMPONENT BakeOnSetup POLICY
//============================================================================
//
// The ARCHETYPE-COMPLETE composition path (the shape BusterBlock's rental
// return bin uses): collision is fully authored on the archetype before Add,
// so the params-level BakeOnSetup policy bakes inside the Setup processor —
// no explicit Request_BakeIntoJoltStaticWorld, no OnAdded bind:
//   1. Archetype (mesh + BlockAll) + BakeOnSetup -> the static-world ray hits
//      as soon as the component exists.
//   2. Destroying the owning entity removes the baked bodies via the same
//      teardown funnel the explicit opt-in uses.
//============================================================================

class UCk_AutoTest_CkJolt_UnrealComponent_BakeOnSetupPolicy : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _Owner;
    private FCk_Handle_UnrealComponent _CompHandle;
    private FVector _Origin = FVector(0.0, 72000.0, 300.0);

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

        auto Params = utils_unreal_component::Make_Params_FromArchetype(
            Archetype, ECk_UnrealComponent_TickPolicy::DoNotTick, n"AutoTest_BakeOnSetupMesh");
        Params.Set_StaticWorldBakePolicy(ECk_UnrealComponent_StaticWorldBakePolicy::BakeOnSetup);

        _CompHandle = utils_unreal_component::Add(_Owner, Params);

        WaitUntil(n"Check_ComponentInstantiated", n"OnComponentReady");
    }

    UFUNCTION()
    private void Check_ComponentInstantiated(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(utils_unreal_component::Get_Component(_CompHandle)));
    }

    private FCk_Jolt_StaticWorldRayHit_Result Do_RayOverOrigin()
    {
        return utils_jolt_static_world::Get_RayCastStaticWorld(
            _Origin + FVector(0.0, 0.0, 500.0), _Origin - FVector(0.0, 0.0, 500.0));
    }

    UFUNCTION()
    private void OnComponentReady(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(Do_RayOverOrigin().Get_HasHit(),
            "BakeOnSetup baked the archetype-complete mesh with NO explicit request — the ray hits");

        utils_entity_lifetime::Request_DestroyEntity(_Owner);
        WaitOneFrame(n"OnTornDown");
    }

    UFUNCTION()
    private void OnTornDown(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto _CkPerfScope = ck::ScopedStat();
        if (IsFinished()) { return; }

        Assert_True(Do_RayOverOrigin().Get_HasHit() == false,
            "entity teardown removed the policy-baked bodies — the ray misses");

        FinishSuccess();
    }
}
