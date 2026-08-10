// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: PROBES NEVER OVERLAP THE STATIC WORLD
//============================================================================
//
// The probe layer's signature (and the broadphase-level guard) must keep baked
// static bodies invisible to probe overlap semantics — pre-table behavior:
//   1. Bake a large BlockAll floor cube.
//   2. Create a Notify sphere probe INSIDE it.
//   3. No OnBeginOverlap fires within the settle window; the probe stays
//      overlap-free. (A Jolt trace-semantics ray still HITS the floor — it is
//      a query target, just not an overlap participant for probes.)
//
// Probe OVERLAP semantics and the ProbeTrace world-hit policy are separate
// contracts and deliberately coexist. ProbeTrace can be told to report world
// bodies (see CkAutoTest_ProbeTrace_*), but that is a per-call QUERY opt-in
// decided per hit inside the trace's collector — it changes no layer pairing.
// This test stays green precisely because nothing about it is query-side: if it
// ever goes red because of a trace change, the layer table was touched and the
// change is wrong.
//============================================================================

class UCk_AutoTest_CkJolt_Probe_DefaultSignature_IgnoresStaticWorld : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private AStaticMeshActor _FloorActor;
    private FVector _FloorCenter = FVector(0.0, 18000.0, 300.0);
    private int32 _BeginOverlapCount = 0;
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

        _FloorActor = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, _FloorCenter));
        _FloorActor.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _FloorActor.StaticMeshComponent.SetStaticMesh(Cube);
        _FloorActor.SetActorScale3D(FVector(6.0, 6.0, 6.0));
        _FloorActor.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_FloorActor), 1,
            "Floor bakes one body");

        // Probe dead-center INSIDE the baked floor — maximum overlap opportunity.
        auto ProbeEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        ProbeEntity.Request_OverrideToSelf();
        auto ProbeTransform = utils_transform::Add(
            ProbeEntity, FTransform(FRotator::ZeroRotator, _FloorCenter), ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"CkTests.Probe.LinearCast.Wall"));
        ProbeParams.Set_MotionType(ECk_MotionType::Kinematic);
        ProbeParams.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Notify);

        auto Probe = utils_probe::Add_Sphere(ProbeTransform, 100.0, ProbeParams, FCk_Probe_DebugInfo());
        utils_probe::BindTo_OnBeginOverlap(Probe,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnProbeBeginOverlap"));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnProbeBeginOverlap(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        if (IsFinished()) { return; }
        _BeginOverlapCount++;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());
        if (_Elapsed < 0.333)
        { return; }

        Assert_Equals_Int(_BeginOverlapCount, 0,
            "A probe inside a baked static body must NEVER receive overlap events (probe layer ignores the static world)");

        // The floor is still a query target: a trace-semantics Jolt ray hits it.
        auto Filter = FCk_Jolt_QueryFilter();
        Filter.Set_Channel(ECollisionChannel::ECC_Visibility);
        Filter.Set_MinResponse(ECk_Jolt_PairInteraction::Block);

        auto Hit = utils_jolt_query::Get_RayCast(
            _FloorCenter + FVector(0.0, 0.0, 800.0), _FloorCenter - FVector(0.0, 0.0, 800.0), Filter);
        Assert_True(Hit.Get_HasHit(), "The baked floor remains a query target for channel raycasts");

        FinishSuccess();
    }
}
