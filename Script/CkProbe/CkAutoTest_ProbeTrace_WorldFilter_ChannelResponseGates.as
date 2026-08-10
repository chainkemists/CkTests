// Language=angelscript

//============================================================================
// CK PROBE TRACE — AUTOMATION TEST: WORLD FILTER HONORS CHANNEL RESPONSE
//============================================================================
//
// World-ness is decided per hit against the layer table, NOT by handing the
// channel filter to the cast (that would channel-filter probes too). This pins
// that the per-hit decision reproduces UE trace semantics.
//
// Layout along +X: OverlapAllDynamic cube (nearer) -> BlockAll cube -> probe.
//
//   1. MinResponse=Block  -> the overlap-only cube is invisible; the trace
//      blocks on the BlockAll cube.
//   2. MinResponse=Overlap -> the overlap-only cube now blocks first.
//   3. Under both, the probe behind everything is truncated away, so the two
//      runs differ ONLY in which cube answered.
//============================================================================

namespace ck_probetrace_worldfilter_test
{
    asset Asset_ProbeTraceWorldFilter_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.WorldFilter.Target");
    }
}

class UCk_AutoTest_ProbeTrace_WorldFilter_ChannelResponseGates : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _SelfHandle;
    private AStaticMeshActor _OverlapCube;
    private AStaticMeshActor _BlockingCube;

    // Y-band 36000.
    private float _Band = 36000.0;
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

        _OverlapCube = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(500.0, _Band, _TraceZ)));
        _OverlapCube.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _OverlapCube.StaticMeshComponent.SetStaticMesh(Cube);
        _OverlapCube.StaticMeshComponent.SetCollisionProfileName(n"OverlapAllDynamic");

        _BlockingCube = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(900.0, _Band, _TraceZ)));
        _BlockingCube.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _BlockingCube.StaticMeshComponent.SetStaticMesh(Cube);
        _BlockingCube.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        auto ProbeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        ProbeEntity.Request_OverrideToSelf();

        auto ProbeTransform = utils_transform::Add(ProbeEntity,
            FTransform(FRotator::ZeroRotator, FVector(1300.0, _Band, _TraceZ)), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.WorldFilter.Target"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        utils_probe::Add_Box(ProbeTransform, FVector(50.0, 50.0, 50.0), ProbeParams, FCk_Probe_DebugInfo());

        WaitUntil(n"Check_ProbeIsTraceable", n"OnSettled");
    }

    private FCk_Probe_RayCast_Settings Make_Settings(ECk_Jolt_PairInteraction InMinResponse) const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.WorldFilter.Target"));

        auto WorldFilter = FCk_Jolt_QueryFilter();
        WorldFilter.Set_Channel(ECollisionChannel::ECC_Visibility);
        WorldFilter.Set_MinResponse(InMinResponse);

        auto Settings = FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1600.0, _Band, _TraceZ), Filter);
        Settings.Set_WorldHitPolicy(ECk_ProbeTrace_WorldHitPolicy::Blocking);
        Settings.Set_WorldFilter(WorldFilter);
        return Settings;
    }

    UFUNCTION()
    private void Check_ProbeIsTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.WorldFilter.Target"));
        auto ProbeOnly = FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1600.0, _Band, _TraceZ), Filter);
        Res.Set(utils_probe_trace::Request_MultiLineTrace(_SelfHandle, ProbeOnly).Num() == 1);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_OverlapCube), 1, "Overlap cube bakes one body");
        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_BlockingCube), 1, "Blocking cube bakes one body");

        // ---- Trace semantics: the overlap-only cube does not answer ----------------------------
        auto BlockHits = utils_probe_trace::Request_MultiLineTrace(_SelfHandle,
            Make_Settings(ECk_Jolt_PairInteraction::Block));

        Assert_Equals_Int(BlockHits.Num(), 1, "MinResponse=Block should block on exactly one cube");

        if (BlockHits.Num() > 0)
        {
            Assert_True(BlockHits[0].Get_HitKind() == ECk_ProbeTrace_HitKind::World, "The blocker is a World hit");
            Do_AssertSourceActorIs(BlockHits[0].Get_HitEntity(), _BlockingCube,
                "MinResponse=Block should skip the OverlapAllDynamic cube and block on the BlockAll cube");
        }

        // ---- Overlap semantics: the nearer overlap-only cube now answers first -----------------
        auto OverlapHits = utils_probe_trace::Request_MultiLineTrace(_SelfHandle,
            Make_Settings(ECk_Jolt_PairInteraction::Overlap));

        Assert_Equals_Int(OverlapHits.Num(), 1, "MinResponse=Overlap should block on exactly one cube");

        if (OverlapHits.Num() > 0)
        {
            Assert_True(OverlapHits[0].Get_HitKind() == ECk_ProbeTrace_HitKind::World, "The blocker is a World hit");
            Do_AssertSourceActorIs(OverlapHits[0].Get_HitEntity(), _OverlapCube,
                "MinResponse=Overlap should now see the nearer OverlapAllDynamic cube");
        }

        Do_Cleanup();
        FinishSuccess();
    }

    private void Do_AssertSourceActorIs(FCk_Handle InHitEntity, AStaticMeshActor InExpected, const FString& InMessage)
    {
        Assert_Valid(InHitEntity, f"{InMessage} (hit did not resolve to an attribution entity)");
        if (ck::Is_NOT_Valid(InHitEntity)) { return; }

        auto StaticActor = utils_jolt_static_actor::DoCastChecked(InHitEntity);
        Assert_True(utils_jolt_static_actor::Get_SourceActorName(StaticActor) == InExpected.GetName(), InMessage);
    }

    private void Do_Cleanup()
    {
        if (IsValid(_OverlapCube))
        {
            utils_jolt_static_world::Request_RemoveActor(_OverlapCube);
            _OverlapCube.DestroyActor();
        }
        if (IsValid(_BlockingCube))
        {
            utils_jolt_static_world::Request_RemoveActor(_BlockingCube);
            _BlockingCube.DestroyActor();
        }
    }
}
