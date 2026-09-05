// Language=angelscript

//============================================================================
// CK PROBE TRACE - AUTOMATION TEST: PERSISTENT WORLD-HIT SIGNAL DEDUPS
//============================================================================
//
// The melee clang. Each policy's persistent shape trace sweeps into a baked cube
// and back out; OnProbeTraceWorldHit is a BEGIN-equivalent, so:
//
//   1. No contact -> no signal.
//   2. Entering contact fires EXACTLY once, and keeps firing nothing while the
//      same body stays hit (the per-episode dedup - a per-tick re-fire would
//      make it useless for a one-shot impact cue).
//   3. Leaving and re-entering fires exactly once more. There is deliberately
//      no end signal.
//   4. The probe-side overlap signals stay silent throughout: a world body is
//      not a probe, and the probe bookkeeping must never see it.
//
// The same episode runs first with the untouched default (CurrentSolved), then
// with explicit LatestCompleted. The test deliberately asserts semantic parity,
// not a particular scheduler-frame of delivery: that ordering is the policy's
// implementation detail and depends on the live fixed-step cadence.
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
    private int32 _EpisodeIndex = 0;
    private ECk_ProbeTrace_PhysicsStatePolicy _EpisodePolicy = ECk_ProbeTrace_PhysicsStatePolicy::CurrentSolved;

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

        Do_StartEpisode(ECk_ProbeTrace_PhysicsStatePolicy::CurrentSolved);
    }

    private void Do_StartEpisode(ECk_ProbeTrace_PhysicsStatePolicy InPolicy)
    {
        _EpisodePolicy = InPolicy;
        _WorldHitCount = 0;
        _ProbeOverlapCount = 0;
        _LastWorldEntity = FCk_Handle();

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
        // Do not write CurrentSolved: this episode pins the public default. LatestCompleted is
        // explicitly selected so changing the default cannot silently erase that coverage.
        if (InPolicy == ECk_ProbeTrace_PhysicsStatePolicy::CurrentSolved)
        {
            Assert_True(Settings.Get_PhysicsStatePolicy() == ECk_ProbeTrace_PhysicsStatePolicy::CurrentSolved,
                "Persistent ProbeTrace must default to CurrentSolved");
        }
        if (InPolicy == ECk_ProbeTrace_PhysicsStatePolicy::LatestCompleted)
        {
            Settings.Set_PhysicsStatePolicy(ECk_ProbeTrace_PhysicsStatePolicy::LatestCompleted);
        }

        _Trace = utils_probe_trace::Create_ShapeTrace_Persistent(Settings);

        utils_probe_trace::BindTo_OnProbeTraceWorldHit(_Trace,
            FCk_Delegate_ProbeTrace_OnWorldHit(this, n"OnWorldHit"));
        utils_probe_trace::BindTo_OnBeginOverlap(_Trace,
            FCk_Delegate_ProbeTrace_OnBeginOverlap(this, n"OnProbeBeginOverlap"));

        // Nothing to wait FOR here - the assertion is that nothing happens.
        WaitFrames(5, n"OnBeforeContact");
    }

    UFUNCTION()
    private void OnBeforeContact(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 0,
            Get_EpisodeLabel() + ": a trace that reaches nothing should not report a world hit");

        Do_MoveStart(_ApproachOffset);
        WaitUntil(n"Check_WorldHitFired", n"OnFirstContact");
    }

    UFUNCTION()
    private void OnFirstContact(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 1,
            Get_EpisodeLabel() + ": entering contact fires the world-hit signal once");
        Assert_Valid(_LastWorldEntity, Get_EpisodeLabel() + ": the payload should name the wall's attribution entity");

        if (ck::IsValid(_LastWorldEntity))
        {
            auto StaticActor = utils_jolt_static_actor::DoCastChecked(_LastWorldEntity);
            Assert_True(utils_jolt_static_actor::Get_SourceActorName(StaticActor) == _Wall.GetName(),
                Get_EpisodeLabel() + ": the payload's world entity should be the wall actor");
        }

        WaitFrames(6, n"OnContactHeld");
    }

    UFUNCTION()
    private void OnContactHeld(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 1,
            Get_EpisodeLabel() + ": holding contact must NOT re-fire - the signal is begin-equivalent, not per-tick");

        Do_MoveStart(-_ApproachOffset);
        WaitFrames(6, n"OnContactLost");
    }

    UFUNCTION()
    private void OnContactLost(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 1,
            Get_EpisodeLabel() + ": losing contact fires nothing - there is no end signal by design");

        Do_MoveStart(_ApproachOffset);
        WaitUntil(n"Check_WorldHitFiredTwice", n"OnSecondContact");
    }

    UFUNCTION()
    private void OnSecondContact(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_WorldHitCount, 2,
            Get_EpisodeLabel() + ": re-entering contact fires exactly once more");
        Assert_Equals_Int(_ProbeOverlapCount, 0,
            Get_EpisodeLabel() + ": a world body must never enter the probe overlap bookkeeping");

        // Stop the prior persistent entity before starting the next policy episode. That removes
        // its dedup set from the scheduler and prevents its bound callbacks contributing to the
        // next episode's counters.
        utils_probe_trace::Request_EnableDisable(_Trace,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Disable));
        WaitUntil(n"Check_TraceDisabled", n"OnTraceDisabled");
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
    private void Check_TraceDisabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_probe_trace::Get_IsEnabledDisabled(_Trace) == ECk_EnableDisable::Disable);
    }

    UFUNCTION()
    private void OnTraceDisabled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_EpisodeIndex == 0)
        {
            _EpisodeIndex = 1;
            // The preceding episode ends in contact at +ApproachOffset. Move its shared source
            // back while the old trace is disabled; the named settle avoids starting the next
            // policy from stale transform state.
            Do_MoveStart(-_ApproachOffset);
            WaitUntil(n"Check_StartReturned", n"OnStartReturnedForLatestCompleted");
            return;
        }

        Do_Cleanup();
        FinishSuccess();
    }

    UFUNCTION()
    private void Check_StartReturned(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_transform::Get_EntityCurrentLocation(_StartTransform).Equals(
            FVector(0.0, _Band, _TraceZ), 1.0f));
    }

    UFUNCTION()
    private void OnStartReturnedForLatestCompleted(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        Do_StartEpisode(ECk_ProbeTrace_PhysicsStatePolicy::LatestCompleted);
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

    private FString Get_EpisodeLabel() const
    {
        if (_EpisodePolicy == ECk_ProbeTrace_PhysicsStatePolicy::LatestCompleted)
        { return "LatestCompleted"; }
        return "CurrentSolved default";
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
