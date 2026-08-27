// Language=angelscript

//============================================================================
// CK PROBE TRACE - AUTOMATION TEST: _IgnoredEntities DROPS PROBE AND WORLD
//============================================================================
//
// The caller-controlled exclusion list, and the reason it exists: a weapon trace
// starts inside its own collision pill. Self-skip only covers the tracing entity
// itself, so anything else the caller owns has to be named.
//
//   1. A baseline trace reports probe + wall, and hands us the wall's own
//      attribution entity (the only way to name a baked body).
//   2. Re-tracing with BOTH entities listed returns nothing at all - the
//      exclusion applies to probe hits and world hits alike, and it happens
//      BEFORE blocking, so the wall does not merely truncate the probe away.
//============================================================================

namespace ck_probetrace_ignored_test
{
    asset Asset_ProbeTraceIgnored_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.Ignored.Target");
    }
}

class UCk_AutoTest_ProbeTrace_IgnoredEntities_SkipsListedProbeAndWorld : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _ProbeEntity;
    private AStaticMeshActor _Wall;

    // Y-band 39000.
    private float _Band = 39000.0;
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

        _Wall = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(900.0, _Band, _TraceZ)));
        _Wall.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _Wall.StaticMeshComponent.SetStaticMesh(Cube);
        _Wall.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        _ProbeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _ProbeEntity.Request_OverrideToSelf();

        auto ProbeTransform = utils_transform::Add(_ProbeEntity,
            FTransform(FRotator::ZeroRotator, FVector(500.0, _Band, _TraceZ)), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Ignored.Target"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        utils_probe::Add_Box(ProbeTransform, FVector(50.0, 50.0, 50.0), ProbeParams, FCk_Probe_DebugInfo());

        WaitUntil(n"Check_ProbeIsTraceable", n"OnSettled");
    }

    private FCk_Probe_RayCast_Settings Make_BlockingSettings() const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Ignored.Target"));

        auto Settings = FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1200.0, _Band, _TraceZ), Filter);
        Settings.Set_WorldHitPolicy(ECk_ProbeTrace_WorldHitPolicy::Blocking);
        return Settings;
    }

    UFUNCTION()
    private void Check_ProbeIsTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Ignored.Target"));
        auto ProbeOnly = FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1200.0, _Band, _TraceZ), Filter);
        Res.Set(utils_probe_trace::Request_MultiLineTrace(_SelfHandle, ProbeOnly).Num() == 1);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_Wall), 1, "Wall cube bakes one body");

        auto Baseline = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Make_BlockingSettings());

        Assert_Equals_Int(Baseline.Num(), 2, "Baseline should report the probe and then the wall");
        if (Baseline.Num() != 2)
        {
            Do_Cleanup();
            FinishFailure("Cannot exercise _IgnoredEntities without a baseline probe+world pair");
            return;
        }

        auto WallEntity = Baseline[1].Get_HitEntity();
        Assert_Valid(WallEntity, "The baked wall should expose an attribution entity to exclude");

        auto Ignored = TArray<FCk_Handle>();
        Ignored.Add(_ProbeEntity);
        Ignored.Add(WallEntity);

        auto Settings = Make_BlockingSettings();
        Settings.Set_IgnoredEntities(Ignored);

        auto Hits = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Settings);

        Assert_Equals_Int(Hits.Num(), 0,
            "With both the probe entity and the wall's attribution entity excluded, the trace reports nothing");

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
