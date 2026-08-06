// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: TELEPORT MOVES BODY, VELOCITY POLICY HONORED
//============================================================================
//
// Request_Teleport snaps a body to a pose with no interpolation across the jump,
// and its VelocityPolicy decides whether momentum survives:
//
//   1. Dynamic box in free fall; once it has gained speed, Teleport(ResetVelocity)
//      to the exact rest pose on the floor -> it arrives at the target (+/-5uu) and
//      STAYS there (no residual velocity carrying it off).
//   2. Lift it back up (ResetVelocity) and let it fall again to build momentum;
//      then Teleport(KeepVelocity) to a high mid-air pose -> it arrives AND keeps
//      moving (the preserved downward momentum carries it below the target).
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_TeleportMovesBodyAndResetsVelocity : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltBody _Body;
    private FCk_Handle_Transform _BoxTransform;

    private FVector _FloorCenter = FVector(0.0, 48000.0, 0.0);
    private float _FloorTopZ = 25.0;
    private float _BoxHalfExtent = 50.0;
    private float _RestZ = 75.0;   // floorTop 25 + halfExtent 50

    // 0 = free fall (gain speed); 1 = reset-teleport landed, verify it stays;
    // 2 = lifted, falling again to gain speed; 3 = keep-teleport, verify it keeps moving.
    //
    // Fall detection reads the body's REAL simulation velocity (Get_LinearVelocity), never a
    // per-tick position delta: tick deltas alias against the fixed-step writeback cadence, and
    // InDeltaT can be 0.0 on real ticks (dividing by it throws script Divide-by-zero).
    private int _Phase = 0;
    private float _ElapsedInPhase = 0.0;
    private float _StableTime = 0.0;
    private bool _PhaseJustEntered = false;
    private float _KeepTeleportZ = 0.0;
    private bool _KeepVelWitnessed = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor ---------------------------------------------------------------------
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, _FloorCenter),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Dynamic box dropped from high up so it is clearly in free fall -------------------
        auto BoxStart = _FloorCenter + FVector(0.0, 0.0, 700.0);
        auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BoxEntity.Request_OverrideToSelf();
        _BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxStart),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(_BoxHalfExtent, _BoxHalfExtent, _BoxHalfExtent));
        auto BoxParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        _Body = utils_jolt_body::Add(BoxEntity, BoxParams);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private void DoTeleport(FVector InTarget, ECk_Jolt_TeleportVelocityPolicy InPolicy)
    {
        auto Request = FCk_Request_JoltBody_Teleport(InTarget, FRotator::ZeroRotator);
        Request.Set_VelocityPolicy(InPolicy);
        utils_jolt_body::Request_Teleport(_Body, Request);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _ElapsedInPhase += float(InDeltaT.Get_Seconds());
        auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BoxTransform).Z;
        auto VelZ = utils_jolt_body::Get_LinearVelocity(_Body).Z;

        // ---- Phase 0: free fall, then reset-teleport onto the floor ---------------------------
        if (_Phase == 0)
        {
            // Wait until the SIMULATION says it is clearly falling, then teleport.
            if (VelZ < -180.0)
            {
                DoTeleport(_FloorCenter + FVector(0.0, 0.0, _RestZ), ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
                _Phase = 1;
                _ElapsedInPhase = 0.0;
                _StableTime = 0.0;
                _PhaseJustEntered = true;
            }
            else if (_ElapsedInPhase > 2.0)
            { FinishFailure(f"Box never entered free fall (velZ={VelZ}, Z={CurrentZ})"); }

            return;
        }

        // ---- Phase 1: verify arrival at rest pose AND that it stays (velocity was reset) -------
        if (_Phase == 1)
        {
            // First poll after the teleport: must be at the target within tolerance.
            if (_PhaseJustEntered)
            {
                Assert_True(Math::Abs(CurrentZ - _RestZ) <= 5.0,
                    f"ResetVelocity teleport should land the box exactly at the target (Z={CurrentZ}, target={_RestZ})");
                _PhaseJustEntered = false;
            }

            // Over the next ~0.333s it must not drift (no residual velocity carrying it).
            if (Math::Abs(CurrentZ - _RestZ) <= 5.0)
            { _StableTime += float(InDeltaT.Get_Seconds()); }
            else
            { _StableTime = 0.0; }

            if (_StableTime >= 0.333)
            {
                // Lift the box high with a clean reset so it re-enters free fall.
                DoTeleport(_FloorCenter + FVector(0.0, 0.0, 800.0), ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
                _Phase = 2;
                _ElapsedInPhase = 0.0;
            }

            if (_ElapsedInPhase > 2.0)
            { FinishFailure(f"Box did not hold the reset-teleport rest pose (Z={CurrentZ}, target={_RestZ})"); }

            return;
        }

        // ---- Phase 2: fall again to build downward momentum -----------------------------------
        if (_Phase == 2)
        {
            // Wait until the SIMULATION says it is clearly falling fast, then keep-teleport mid-air.
            if (VelZ < -180.0)
            {
                _KeepTeleportZ = _FloorCenter.Z + 400.0;
                DoTeleport(FVector(_FloorCenter.X, _FloorCenter.Y, _KeepTeleportZ),
                    ECk_Jolt_TeleportVelocityPolicy::KeepVelocity);
                _Phase = 3;
                _ElapsedInPhase = 0.0;
                _PhaseJustEntered = true;
                return;
            }

            if (_ElapsedInPhase > 2.0)
            { FinishFailure(f"Box never regained fall speed before the keep-velocity teleport (velZ={VelZ}, Z={CurrentZ})"); }

            return;
        }

        // ---- Phase 3: keep-velocity teleport must arrive AND keep moving downward --------------
        if (_PhaseJustEntered)
        {
            Assert_True(Math::Abs(CurrentZ - _KeepTeleportZ) <= 30.0,
                f"KeepVelocity teleport should place the box near the target (Z={CurrentZ}, target={_KeepTeleportZ})");
            _PhaseJustEntered = false;
        }

        // Direct one-shot witness ~0.1s after the teleport: a KEPT body carries about -300uu/s here
        // (-180 trigger + gravity accrual); a wrongly-reset one has only rebuilt about -120uu/s.
        if (!_KeepVelWitnessed && _ElapsedInPhase >= 0.1)
        {
            _KeepVelWitnessed = true;
            Assert_True(VelZ < -200.0,
                f"KeepVelocity teleport must preserve downward velocity (velZ={VelZ} at 0.1s after arrival; a reset body would be ~-120)");
        }

        // Behavioral witness: the momentum carries it clearly below the teleport target.
        if (CurrentZ < _KeepTeleportZ - 30.0)
        {
            FinishSuccess();
            return;
        }

        if (_ElapsedInPhase > 2.0)
        { FinishFailure(f"Box did not keep moving after KeepVelocity teleport (Z={CurrentZ}, velZ={VelZ}, target={_KeepTeleportZ})"); }
    }
}
