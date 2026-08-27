// Language=angelscript

//============================================================================
// CK PROBE TRACE - AUTOMATION TEST: REPORTED INTERLEAVES WITHOUT TRUNCATING
//============================================================================
//
// Same layout as the Blocking test (probe A -> baked cube -> probe B) under the
// Reported policy. This is the melee-swing case: the swing sparks on the wall
// AND still cuts the enemy standing behind it.
//
//   1. Three results, ordered by fraction: A(Probe), cube(World), B(Probe).
//   2. Nothing is hidden - probe B is present AND received its overlap ping,
//      which is exactly what Blocking suppresses.
//============================================================================

namespace ck_probetrace_reported_test
{
    asset Asset_ProbeTraceReported_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.Reported.Target");
    }
}

class UCk_AutoTest_ProbeTrace_Reported_WorldAndProbesInterleaveUntruncated : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _ProbeNearEntity;
    private FCk_Handle _ProbeFarEntity;
    private AStaticMeshActor _Wall;

    private int32 _NearBeginCount = 0;
    private int32 _FarBeginCount = 0;

    // Y-band 33000.
    private float _Band = 33000.0;
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

        _Wall = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(750.0, _Band, _TraceZ)));
        _Wall.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _Wall.StaticMeshComponent.SetStaticMesh(Cube);
        _Wall.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        _ProbeNearEntity = Do_MakeProbe(300.0);
        _ProbeFarEntity = Do_MakeProbe(1200.0);

        WaitUntil(n"Check_BothProbesTraceable", n"OnSettled");
    }

    private FCk_Handle Do_MakeProbe(float InX)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Entity.Request_OverrideToSelf();

        auto ProbeTransform = utils_transform::Add(Entity,
            FTransform(FRotator::ZeroRotator, FVector(InX, _Band, _TraceZ)), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Reported.Target"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        utils_probe::Add_Box(ProbeTransform, FVector(50.0, 50.0, 50.0), ProbeParams, FCk_Probe_DebugInfo());

        return Entity;
    }

    private FCk_Probe_RayCast_Settings Make_ProbeOnlySettings() const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Reported.Target"));

        return FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1500.0, _Band, _TraceZ), Filter);
    }

    UFUNCTION()
    private void Check_BothProbesTraceable(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        // Silent, because this predicate re-traces EVERY poll: a Notify settle-trace enqueues a
        // deferred BeginOverlap that drains a tick later, landing after the bind below and
        // inflating the measured count.
        auto Settings = Make_ProbeOnlySettings();
        Settings.Set_OverlapNotifyPolicy(ECk_ProbeResponse_Policy::Silent);

        auto Res = OutResult;
        Res.Set(utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Settings).Num() == 2);
    }

    UFUNCTION()
    private void OnSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_Wall), 1, "Wall cube bakes one body");

        utils_probe::BindTo_OnBeginOverlap(utils_probe::DoCastChecked(_ProbeNearEntity),
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnNearBeginOverlap"));
        utils_probe::BindTo_OnBeginOverlap(utils_probe::DoCastChecked(_ProbeFarEntity),
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnFarBeginOverlap"));

        auto Settings = Make_ProbeOnlySettings();
        Settings.Set_WorldHitPolicy(ECk_ProbeTrace_WorldHitPolicy::Reported);

        auto Hits = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Settings);

        Assert_Equals_Int(Hits.Num(), 3, "Reported should return both probes AND the wall - nothing truncated");

        if (Hits.Num() == 3)
        {
            Assert_True(Hits[0].Get_HitKind() == ECk_ProbeTrace_HitKind::Probe, "[0] is the near probe");
            Assert_True(Hits[0].Get_HitEntity() == _ProbeNearEntity, "[0] is probe A specifically");

            Assert_True(Hits[1].Get_HitKind() == ECk_ProbeTrace_HitKind::World, "[1] is the wall, interleaved");

            Assert_True(Hits[2].Get_HitKind() == ECk_ProbeTrace_HitKind::Probe, "[2] is the far probe");
            Assert_True(Hits[2].Get_HitEntity() == _ProbeFarEntity, "[2] is probe B specifically");

            Assert_True(Hits[0].Get_Fraction() < Hits[1].Get_Fraction() &&
                        Hits[1].Get_Fraction() < Hits[2].Get_Fraction(),
                "Fractions ascend across the interleaved kinds");
        }

        WaitUntil(n"Check_BothProbesPinged", n"OnOverlapsDrained");
    }

    UFUNCTION()
    private void Check_BothProbesPinged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_NearBeginCount > 0 && _FarBeginCount > 0);
    }

    UFUNCTION()
    private void OnOverlapsDrained(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_NearBeginCount, 1, "The near probe receives exactly one BeginOverlap");
        Assert_Equals_Int(_FarBeginCount, 1,
            "The probe behind the wall STILL receives its ping under Reported - this is what Blocking suppresses");

        Do_Cleanup();
        FinishSuccess();
    }

    UFUNCTION()
    private void OnNearBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        _NearBeginCount++;
    }

    UFUNCTION()
    private void OnFarBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        _FarBeginCount++;
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
