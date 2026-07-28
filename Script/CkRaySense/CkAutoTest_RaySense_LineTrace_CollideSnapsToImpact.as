// Language=angelscript

//============================================================================
// CK RAY SENSE — AUTOMATION TEST: LINE TRACE COLLIDE SNAPS TO IMPACT
//============================================================================
//
// Pins the CollisionResponse=Collide contract on the LINE-TRACE path: on hit,
// the entity is snapped to the impact point (previously the params field was
// silently ignored for line traces — only sweeps honored it; this test gates
// the unification through ck_raysense::Request_ProcessTraceHit).
//
// Flow: same wall + stepping setup as the HitFiresSignal test, with
// CollisionResponse=Collide. On the first hit the test stops stepping AND
// disables the RaySense (so the post-snap transform change doesn't re-trace
// from inside the wall), waits for the deferred snap request to land, then
// asserts the entity rests on the impact point.
//============================================================================

class UCk_AutoTest_RaySense_LineTrace_CollideSnapsToImpact : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _SenseTransform;
    private FCk_Handle_RaySense _RaySense;

    private bool _HitObserved = false;
    private FVector _ImpactPoint;
    private int32 _StepsTaken = 0;
    private int32 _MaxSteps = 40;

    // Own Y-lane: the HitFiresSignal test runs in the same level at Y=0 and spawned actors
    // outlive their test — keep this test's ray clear of leftover walls.
    private float _LaneY = 2000.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto WallActor = SpawnActor(ACk_Gym_ObstacleWall, FVector(600.0, _LaneY, 300.0), FRotator::ZeroRotator);
        if (ck::Is_NOT_Valid(WallActor))
        {
            FinishFailure("Failed to spawn ACk_Gym_ObstacleWall");
            return;
        }
        WallActor.SetActorScale3D(FVector(1.0, 8.0, 8.0));

        auto SenseEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        SenseEntity.Request_OverrideToSelf();
        _SenseTransform = utils_transform::Add(
            SenseEntity, FTransform(FRotator::ZeroRotator, FVector(0.0, _LaneY, 300.0)), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_RaySense_ParamsData(
            ECk_RaySense_CollisionQuality::Sweep, ECollisionChannel::ECC_Visibility);
        Params.Set_CollisionResponse(ECk_RaySense_CollisionResponse_Policy::Collide);
        _RaySense = utils_ray_sense::Add(SenseEntity, Params);
        if (ck::Is_NOT_Valid(_RaySense))
        {
            FinishFailure("utils_ray_sense::Add returned an invalid handle");
            return;
        }

        utils_ray_sense::BindTo_OnTraceHit(_RaySense,
            FCk_Delegate_RaySense_LineTrace(this, n"OnTraceHit"));

        // Deliberately a settle, not a condition: RaySense exposes no "setup complete"
        // query to wait on, and this window is what keeps the wall's collision
        // registration ahead of the first step. WaitOneFrame is 0.05s (~3 frames at
        // 60fps) — a WaitFrames(1) here would SHORTEN it and eat into the six steps
        // the entity takes to reach the wall.
        WaitOneFrame(n"OnSetupSettled");
    }

    UFUNCTION()
    private void OnSetupSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnStep"));
    }

    UFUNCTION()
    private void OnStep(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished() || _HitObserved) { return; }

        _StepsTaken++;
        if (_StepsTaken > _MaxSteps)
        {
            FinishFailure(f"RaySense entity stepped {_MaxSteps} times without OnRaySenseTraceHit firing");
            return;
        }

        utils_transform::Request_AddLocationOffset(
            _SenseTransform, FVector(100.0, 0.0, 0.0), ECk_LocalWorld::World);
    }

    UFUNCTION()
    private void OnTraceHit(FCk_Handle_RaySense InHandle, FCk_RaySense_HitResult InHitResult)
    {
        if (IsFinished() || _HitObserved) { return; }
        _HitObserved = true;
        _ImpactPoint = InHitResult.Get_ImpactPoint();

        // Stop tracing: the Collide snap (enqueued before this broadcast) moves the entity to
        // the impact point next frame; a further trace from the pre-snap location (inside the
        // wall) would re-fire with a start-penetrating hit and fight the snap.
        utils_ray_sense::Request_EnableDisable(_RaySense,
            FCk_Request_RaySense_EnableDisable(ECk_EnableDisable::Disable));

        // Snap request is handled by Transform_HandleRequests on a later tick. Wait on
        // the snapped position itself rather than on a frame, so a slow pass extends the
        // wait instead of failing the test.
        //
        // Residual exposure, unchanged from the frame settle this replaces: if a step
        // happened to land the entity within tolerance of the impact BEFORE the snap,
        // this releases immediately. Asserting that it did not is not safe either — the
        // step stride and the wall's face position could legitimately coincide.
        WaitUntil(n"Check_SnappedToImpact", n"OnSnapSettled");
    }

    UFUNCTION()
    private void Check_SnappedToImpact(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Location = utils_transform::Get_EntityCurrentLocation(_SenseTransform);
        auto Res = OutResult;
        Res.Set(Math::Abs(Location.X - _ImpactPoint.X) < 5.0);
    }

    UFUNCTION()
    private void OnSnapSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto FinalLocation = utils_transform::Get_EntityCurrentLocation(_SenseTransform);

        Assert_True(Math::Abs(FinalLocation.X - _ImpactPoint.X) < 5.0,
            f"Collide response should snap the entity to the impact point (impact X={_ImpactPoint.X}, final X={FinalLocation.X})");
        Assert_True(_ImpactPoint.X > 400.0 && _ImpactPoint.X < 750.0,
            f"Impact should land on the wall along the traced path (got impact={_ImpactPoint}, final={FinalLocation}, steps={_StepsTaken})");

        FinishSuccess();
    }
}
