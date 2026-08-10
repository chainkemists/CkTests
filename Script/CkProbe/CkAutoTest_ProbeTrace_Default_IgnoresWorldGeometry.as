// Language=angelscript

//============================================================================
// CK PROBE TRACE — AUTOMATION TEST: DEFAULT SETTINGS IGNORE WORLD GEOMETRY
//============================================================================
//
// Pins the DEFAULT of the world-hit policy, which is load-bearing rather than a
// courtesy: EQS line-of-sight reads `Hits.IsEmpty()` as "clear", the crowd test
// counts hits, and the claw machine guards on `Get_Probe()` validity. If world
// bodies ever became visible by default, all three invert silently.
//
//   1. A baked BlockAll cube sits BETWEEN the trace start and a matching probe.
//   2. A trace with untouched settings still reports the probe behind the wall.
//   3. Exactly one hit, of kind Probe — the wall is invisible to this trace.
//============================================================================

namespace ck_probetrace_default_test
{
    asset Asset_ProbeTraceDefault_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.Default.Target");
    }
}

class UCk_AutoTest_ProbeTrace_Default_IgnoresWorldGeometry : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _ProbeEntity;
    private AStaticMeshActor _Wall;

    // Y-band 24000 — this map's tests share one PIE world, so every test parks its
    // geometry in its own band.
    private float _Band = 24000.0;
    private float _TraceZ = 300.0;

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

        _Wall = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(500.0, _Band, _TraceZ)));
        _Wall.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _Wall.StaticMeshComponent.SetStaticMesh(Cube);
        _Wall.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        _ProbeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ProbeEntity.Request_OverrideToSelf();

        auto ProbeTransform = utils_transform::Add(_ProbeEntity,
            FTransform(FRotator::ZeroRotator, FVector(1000.0, _Band, _TraceZ)), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Default.Target"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        utils_probe::Add_Box(ProbeTransform, FVector(50.0, 50.0, 50.0), ProbeParams, FCk_Probe_DebugInfo());

        WaitUntil(n"Check_ProbeIsTraceable", n"OnSettled");
    }

    private FCk_Probe_RayCast_Settings Make_DefaultSettings() const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Default.Target"));

        // Deliberately NOTHING else is set — this test is about the untouched defaults.
        return FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1500.0, _Band, _TraceZ), Filter);
    }

    UFUNCTION()
    private void Check_ProbeIsTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Make_DefaultSettings()).Num() > 0);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_Wall), 1, "Wall cube bakes one body");

        auto Hits = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Make_DefaultSettings());

        Assert_Equals_Int(Hits.Num(), 1, "Default settings should report the probe and NOTHING else");

        if (Hits.Num() > 0)
        {
            Assert_True(Hits[0].Get_HitKind() == ECk_ProbeTrace_HitKind::Probe,
                "The only hit should be of kind Probe");
            Assert_Valid(FCk_Handle(Hits[0].Get_Probe()), "A Probe-kind hit carries a valid probe handle");
            Assert_True(Hits[0].Get_HitEntity() == _ProbeEntity,
                "HitEntity on a Probe hit should be the probe's own entity");
            Assert_True(Hits[0].Get_HitLocation().X > 500.0,
                "The reported hit is BEYOND the wall — the wall is invisible to a default trace");
        }

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
