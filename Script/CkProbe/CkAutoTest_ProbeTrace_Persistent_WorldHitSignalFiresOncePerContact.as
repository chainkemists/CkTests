// Language=angelscript

//============================================================================
// CK PROBE TRACE — AUTOMATION TEST: PERSISTENT WORLD-HIT SIGNAL DEDUPS
//============================================================================
//
// The melee clang. A persistent shape trace sweeps into a baked cube and back
// out; OnProbeTraceWorldHit is a BEGIN-equivalent, so:
//
//   1. No contact -> no signal.
//   2. Entering contact fires EXACTLY once, and keeps firing nothing while the
//      same body stays hit (the per-episode dedup — a per-tick re-fire would
//      make it useless for a one-shot impact cue).
//   3. Leaving and re-entering fires exactly once more. There is deliberately
//      no end signal.
//   4. The probe-side overlap signals stay silent throughout: a world body is
//      not a probe, and the probe bookkeeping must never see it.
//============================================================================

namespace ck_probetrace_persistent_test
{
    asset Asset_ProbeTracePersistent_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"CkTests.ProbeTrace.Persistent.Target");
    }
}

class UCk_AutoTest_ProbeTrace_Persistent_WorldHitSignalFiresOncePerContact : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _StartTransform;
    private FCk_Handle_ProbeTrace _Trace;
    private AStaticMeshActor _Wall;

    private int32 _WorldHitCount = 0;
    private int32 _ProbeOverlapCount = 0;
    private FCk_Handle _LastWorldEntity;

    // Y-band 42000.
    private float _Band = 42000.0;
    private float _TraceZ = 300.0;

    // Sweep reach: the trace covers [StartX, StartX + 300]. The cube spans 750..850, so the
    // trace only reaches it once the start has moved to X=600.
    private float _SweepLength = 300.0;
    private float _ApproachOffset = 600.0;

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

        _Wall = Cast<AStaticMeshActor>(SpawnActor(AStaticMeshActor, FVector(800.0, _Band, _TraceZ)));
        _Wall.StaticMeshComponent.SetMobility(EComponentMobility::Movable);
        _Wall.StaticMeshComponent.SetStaticMesh(Cube);
        _Wall.StaticMeshComponent.SetCollisionProfileName(n"BlockAll");

        Assert_Equals_Int(utils_jolt_static_world::Request_BakeActor(_Wall), 1, "Wall cube bakes one body");

        auto StartEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        StartEntity.Request_OverrideToSelf();
        _StartTransform = utils_transform::Add(StartEntity,
            FTransform(FRotator::ZeroRotator, FVector(0.0, _Band, _TraceZ)), ECk_Replication::DoesNotReplicate);

        // A tag no probe in this band carries: the trace is about world bodies only, and a
        // non-empty filter keeps it off the empty-filter early-return path.
        auto Filter = FGameplayTagContainer();
        Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"CkTests.ProbeTrace.Persistent.Target"));

        auto Settings = FCk_Probe_ShapeCastPersistent_Settings(
            _StartTransform,
            FVector(_SweepLength, 0.0, 0.0),
            utils_shapes::Make_Sphere(FCk_ShapeSphere_Dimensions(25.0f)),
            Filter);
        Settings.Set_WorldHitPolicy(ECk_ProbeTrace_WorldHitPolicy::Blocking);

        _Trace = utils_probe_trace::Create_ShapeTrace_Persistent(Settings);

        utils_probe_trace::BindTo_OnProbeTraceWorldHit(_Trace,
            FCk_Delegate_ProbeTrace_OnWorldHit(this, n"OnWorldHit"));
        utils_probe_trace::BindTo_OnBeginOverlap(_Trace,
            FCk_Delegate_ProbeTrace_OnBeginOverlap(this, n"OnProbeBeginOverlap"));

        // Nothing to wait FOR here — the assertion is that nothing happens.
        WaitFrames(5, n"OnBeforeContact");
    }

    UFUNCTION()
    private void OnBeforeContact(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 0, "A trace that reaches nothing should not report a world hit");

        Do_MoveStart(_ApproachOffset);
        WaitUntil(n"Check_WorldHitFired", n"OnFirstContact");
    }

    UFUNCTION()
    private void OnFirstContact(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 1, "Entering contact fires the world-hit signal once");
        Assert_Valid(_LastWorldEntity, "The payload should name the wall's attribution entity");

        if (ck::IsValid(_LastWorldEntity))
        {
            auto StaticActor = utils_jolt_static_actor::DoCastChecked(_LastWorldEntity);
            Assert_True(utils_jolt_static_actor::Get_SourceActorName(StaticActor) == _Wall.GetName(),
                "The payload's world entity should be the wall actor");
        }

        WaitFrames(6, n"OnContactHeld");
    }

    UFUNCTION()
    private void OnContactHeld(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 1,
            "Holding the same contact must NOT re-fire — the signal is begin-equivalent, not per-tick");

        Do_MoveStart(-_ApproachOffset);
        WaitFrames(6, n"OnContactLost");
    }

    UFUNCTION()
    private void OnContactLost(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 1, "Losing contact fires nothing — there is no end signal by design");

        Do_MoveStart(_ApproachOffset);
        WaitUntil(n"Check_WorldHitFiredTwice", n"OnSecondContact");
    }

    UFUNCTION()
    private void OnSecondContact(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 2, "Re-entering contact fires exactly once more");
        Assert_Equals_Int(_ProbeOverlapCount, 0,
            "A world body must never enter the probe overlap bookkeeping");

        Do_Cleanup();
        FinishSuccess();
    }

    UFUNCTION()
    private void Check_WorldHitFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_WorldHitCount >= 1);
    }

    UFUNCTION()
    private void Check_WorldHitFiredTwice(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_WorldHitCount >= 2);
    }

    UFUNCTION()
    private void OnWorldHit(FCk_Handle_ProbeTrace InTrace, FCk_ProbeTrace_Payload_OnWorldHit InPayload)
    {
        _WorldHitCount++;
        _LastWorldEntity = InPayload.Get_WorldEntity();
    }

    UFUNCTION()
    private void OnProbeBeginOverlap(FCk_Handle_ProbeTrace InTrace, FCk_Probe_Payload_OnBeginOverlap InPayload)
    {
        _ProbeOverlapCount++;
    }

    private void Do_MoveStart(float InDeltaX)
    {
        utils_transform::Request_AddLocationOffset(
            _StartTransform, FVector(InDeltaX, 0.0, 0.0), ECk_LocalWorld::World);
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
