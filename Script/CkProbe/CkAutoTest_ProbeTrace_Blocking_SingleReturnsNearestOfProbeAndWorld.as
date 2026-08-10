// Language=angelscript

//============================================================================
// CK PROBE TRACE — AUTOMATION TEST: SINGLE = NEAREST OF (PROBE, WORLD BLOCKER)
//============================================================================
//
// One geometry, traced from both ends, so the two arrangements cannot drift
// apart: probe at X=300, baked BlockAll cube at X=750.
//
//   (a) +X sweep: the probe is nearer -> Single reports kind Probe.
//   (b) -X sweep: the cube is nearer  -> Single reports kind World, with a
//       valid attribution entity and a REAL surface normal (+X face, since we
//       approach the cube from +X). _NormalDirLen is not that normal and never
//       was — it is (StartPos - HitLocation).
//
// This is the "did the bullet land or hit the wall" contract.
//============================================================================

namespace ck_probetrace_single_test
{
    asset Asset_ProbeTraceSingle_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.Single.Target");
    }
}

class UCk_AutoTest_ProbeTrace_Blocking_SingleReturnsNearestOfProbeAndWorld : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _ProbeEntity;
    private AStaticMeshActor _Wall;

    // Y-band 30000.
    private float _Band = 30000.0;
    private float _TraceZ = 300.0;

    // cos(5 degrees) — the normal tolerance PHASE_3 specifies.
    private float32 _NormalDotTolerance = 0.9961f;

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

        _Wall = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(750.0, _Band, _TraceZ)));
        _Wall.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _Wall.StaticMeshComponent.SetStaticMesh(Cube);
        _Wall.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        _ProbeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ProbeEntity.Request_OverrideToSelf();

        auto ProbeTransform = utils_transform::Add(_ProbeEntity,
            FTransform(FRotator::ZeroRotator, FVector(300.0, _Band, _TraceZ)), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Single.Target"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        utils_probe::Add_Box(ProbeTransform, FVector(50.0, 50.0, 50.0), ProbeParams, FCk_Probe_DebugInfo());

        WaitUntil(n"Check_ProbeIsTraceable", n"OnSettled");
    }

    private FCk_Probe_RayCast_Settings Make_Settings(FVector InStart, FVector InEnd) const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Single.Target"));

        auto Settings = FCk_Probe_RayCast_Settings(InStart, InEnd, Filter);
        Settings.Set_WorldHitPolicy(ECk_ProbeTrace_WorldHitPolicy::Blocking);
        return Settings;
    }

    UFUNCTION()
    private void Check_ProbeIsTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Single.Target"));
        auto ProbeOnly = FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1500.0, _Band, _TraceZ), Filter);
        Res.Set(utils_probe_trace::Request_MultiLineTrace(_SelfHandle, ProbeOnly).Num() == 1);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_Wall), 1, "Wall cube bakes one body");

        // ---- (a) probe nearer ------------------------------------------------------------------
        auto Forward = utils_probe_trace::Request_SingleLineTrace(_SelfHandle,
            Make_Settings(FVector(0.0, _Band, _TraceZ), FVector(1500.0, _Band, _TraceZ)));

        Assert_True(Forward.Get_HitKind() == ECk_ProbeTrace_HitKind::Probe,
            "Sweeping +X, the probe is nearer than the wall — Single should report Probe");
        Assert_True(Forward.Get_HitEntity() == _ProbeEntity, "Forward Single should name the probe entity");

        // ---- (b) wall nearer -------------------------------------------------------------------
        auto Backward = utils_probe_trace::Request_SingleLineTrace(_SelfHandle,
            Make_Settings(FVector(1500.0, _Band, _TraceZ), FVector(0.0, _Band, _TraceZ)));

        Assert_True(Backward.Get_HitKind() == ECk_ProbeTrace_HitKind::World,
            "Sweeping -X, the wall is nearer than the probe — Single should report World");
        Assert_Invalid(FCk_Handle(Backward.Get_Probe()), "A World hit must carry an INVALID _Probe");
        Assert_Valid(Backward.Get_HitEntity(), "A baked-world hit should resolve to its attribution entity");

        auto Normal = Backward.Get_SurfaceNormal();
        Assert_Equals_Float(float(Normal.DotProduct(FVector(1.0, 0.0, 0.0))), 1.0f, 1.0f - _NormalDotTolerance,
            "Approaching the cube from +X, the surface normal should point back along +X");

        Assert_True(Backward.Get_HitLocation().X > 750.0,
            "The -X sweep should stop on the cube's NEAR (+X) face, not pass through it");

        Do_Cleanup();
        FinishSuccess();
    }

    private void Do_Cleanup()
    {
        if (IsValid(_Wall))
        {
            utils_jolt_static_world::Request_RemoveActor(_Wall);
            _Wall.DestroyActor();
        }
    }
}
