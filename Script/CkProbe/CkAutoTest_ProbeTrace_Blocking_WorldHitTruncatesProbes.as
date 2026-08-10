// Language=angelscript

//============================================================================
// CK PROBE TRACE — AUTOMATION TEST: BLOCKING TRUNCATES AT THE WORLD HIT
//============================================================================
//
// Layout along +X: start -> probe A -> baked BlockAll cube -> probe B.
//
//   1. Blocking returns A and the wall, in that order, and STOPS: probe B is
//      absent even though the cast reached it.
//   2. Truncation covers side-effects too — B receives zero BeginOverlap pings
//      while A receives exactly one. A result list that hid B but still pinged
//      it would be a wallhack with extra steps.
//   3. The World element carries an INVALID _Probe and a VALID _HitEntity that
//      resolves to the cube's JoltStaticActor (the claw-machine guard contract).
//============================================================================

namespace ck_probetrace_blocking_test
{
    asset Asset_ProbeTraceBlocking_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.Blocking.Target");
    }
}

class UCk_AutoTest_ProbeTrace_Blocking_WorldHitTruncatesProbes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle _ProbeNearEntity;
    private FCk_Handle _ProbeFarEntity;
    private AStaticMeshActor _Wall;

    private int32 _NearBeginCount = 0;
    private int32 _FarBeginCount = 0;

    // Y-band 27000.
    private float _Band = 27000.0;
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
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Blocking.Target"));
        ProbeParams.Set_MotionType(ECk_MotionType::Static);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);
        utils_probe::Add_Box(ProbeTransform, FVector(50.0, 50.0, 50.0), ProbeParams, FCk_Probe_DebugInfo());

        return Entity;
    }

    private FGameplayTagContainer Make_Filter() const
    {
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Blocking.Target"));
        return Filter;
    }

    private FCk_Probe_RayCast_Settings Make_ProbeOnlySettings() const
    {
        return FCk_Probe_RayCast_Settings(
            FVector(0.0, _Band, _TraceZ), FVector(1500.0, _Band, _TraceZ), Make_Filter());
    }

    private FCk_Probe_RayCast_Settings Make_BlockingSettings() const
    {
        auto Settings = Make_ProbeOnlySettings();
        Settings.Set_WorldHitPolicy(ECk_ProbeTrace_WorldHitPolicy::Blocking);
        return Settings;
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

        // Counters bind only NOW: the settle traces above run with the default Notify policy and
        // would otherwise be counted as overlaps of the measured cast.
        utils_probe::BindTo_OnBeginOverlap(utils_probe::DoCastChecked(_ProbeNearEntity),
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnNearBeginOverlap"));
        utils_probe::BindTo_OnBeginOverlap(utils_probe::DoCastChecked(_ProbeFarEntity),
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnFarBeginOverlap"));

        auto Hits = utils_probe_trace::Request_MultiLineTrace(_SelfHandle, Make_BlockingSettings());

        Assert_Equals_Int(Hits.Num(), 2, "Blocking should return the near probe and the wall, and stop there");

        if (Hits.Num() == 2)
        {
            Assert_True(Hits[0].Get_HitKind() == ECk_ProbeTrace_HitKind::Probe, "[0] should be the near PROBE");
            Assert_True(Hits[0].Get_HitEntity() == _ProbeNearEntity, "[0] should be probe A specifically");

            Assert_True(Hits[1].Get_HitKind() == ECk_ProbeTrace_HitKind::World, "[1] should be the WORLD blocker");
            Assert_Invalid(FCk_Handle(Hits[1].Get_Probe()),
                "A World hit must carry an INVALID _Probe — the claw-machine guard depends on it");
            Assert_Valid(Hits[1].Get_HitEntity(), "The wall's hit should resolve to a JoltStaticActor entity");

            Assert_True(Hits[0].Get_Fraction() < Hits[1].Get_Fraction(),
                "Results stay in near-to-far fraction order across kinds");

            if (ck::IsValid(Hits[1].Get_HitEntity()))
            {
                auto StaticActor = utils_jolt_static_actor::DoCastChecked(Hits[1].Get_HitEntity());
                Assert_True(utils_jolt_static_actor::Get_SourceActorName(StaticActor) == _Wall.GetName(),
                    "World-hit attribution should name the wall actor");
            }
        }

        WaitUntil(n"Check_NearProbeWasPinged", n"OnOverlapsDrained");
    }

    UFUNCTION()
    private void Check_NearProbeWasPinged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_NearBeginCount > 0);
    }

    UFUNCTION()
    private void OnOverlapsDrained(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_NearBeginCount, 1, "The pre-blocker probe should receive exactly one BeginOverlap");
        Assert_Equals_Int(_FarBeginCount, 0,
            "The probe BEHIND the blocker must receive no overlap ping — truncation covers side-effects too");

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
