// Language=angelscript

//============================================================================
// CK RAY SENSE — AUTOMATION TEST: LINE TRACE HIT FIRES SIGNAL
//============================================================================
//
// First behavioral coverage of the RaySense trace pipeline (the existing
// tests only pin composition):
//   1. An ACk_Gym_ObstacleWall (engine cube, BlockAll) stands at X=600,
//      scaled to a 100-thick wall spanning the entity's +X path.
//   2. A line-trace RaySense entity steps +X each tick; the per-tick trace
//      runs prev->curr, so a segment crossing the wall must fire
//      OnRaySenseTraceHit with the wall actor resolved in the payload and an
//      impact point on the traced path.
//
// The asserts deliberately pin only what RaySense owns (signal, payload
// actor, impact on the path) — NOT the exact face coordinate, which belongs
// to the engine cube's pivot/collision convention.
//============================================================================

class UCk_AutoTest_RaySense_LineTrace_HitFiresSignal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _SenseTransform;
    private AActor _WallActor;

    private bool _HitObserved = false;
    private int32 _StepsTaken = 0;
    private int32 _MaxSteps = 40;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Blocking wall: engine cube, blocks all channels ----
        _WallActor = SpawnActor(ACk_Gym_ObstacleWall, FVector(600.0, 0.0, 300.0), FRotator::ZeroRotator);
        if (ck::Is_NOT_Valid(_WallActor))
        {
            FinishFailure("Failed to spawn ACk_Gym_ObstacleWall");
            return;
        }
        _WallActor.SetActorScale3D(FVector(1.0, 8.0, 8.0));

        // ---- RaySense entity: line trace (no shape fragment), Visibility channel ----
        auto SenseEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        SenseEntity.Request_OverrideToSelf();
        _SenseTransform = utils_transform::Add(
            SenseEntity, FTransform(FRotator::ZeroRotator, FVector(0.0, 0.0, 300.0)), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_RaySense_ParamsData(
            ECk_RaySense_CollisionQuality::Sweep, ECollisionChannel::ECC_Visibility);
        auto RaySense = utils_ray_sense::Add(SenseEntity, Params);
        if (ck::Is_NOT_Valid(RaySense))
        {
            FinishFailure("utils_ray_sense::Add returned an invalid handle");
            return;
        }

        utils_ray_sense::BindTo_OnTraceHit(RaySense,
            FCk_Delegate_RaySense_LineTrace(this, n"OnTraceHit"));

        // Let setup settle, then step the entity toward the wall each tick.
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

        auto Impact = InHitResult.Get_ImpactPoint();

        // The wall slab occupies ~100uu of the +X path around X=600; the impact must land on
        // the traced path inside/on that slab (exact face X depends on the cube's pivot).
        Assert_True(Impact.X > 400.0 && Impact.X < 750.0,
            f"Impact point should land on the wall along the traced path (got impact={Impact}, step={_StepsTaken})");
        Assert_True(Math::Abs(Impact.Y) < 5.0 && Math::Abs(Impact.Z - 300.0) < 5.0,
            f"Impact point should lie on the trace line Y=0 Z=300 (got impact={Impact})");
        Assert_True(InHitResult.Get_MaybeHitActor() == _WallActor,
            "Hit payload should resolve the wall actor");

        FinishSuccess();
    }
}
