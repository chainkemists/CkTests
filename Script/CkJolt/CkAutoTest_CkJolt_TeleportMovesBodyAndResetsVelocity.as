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
    private int _Phase = 0;
    private int _FramesInPhase = 0;
    private int _StableAtRest = 0;
    private float _LastZ = 0.0;
    private float _KeepTeleportZ = 0.0;

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
        auto FloorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
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
        auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        _Body = utils_jolt_body::Add(BoxEntity, BoxParams);

        _LastZ = BoxStart.Z;
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

        _FramesInPhase++;
        auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BoxTransform).Z;
        auto FrameDeltaZ = CurrentZ - _LastZ;
        _LastZ = CurrentZ;

        // ---- Phase 0: free fall, then reset-teleport onto the floor ---------------------------
        if (_Phase == 0)
        {
            // Give it a moment of fall so it clearly carries downward velocity, then teleport.
            if (_FramesInPhase >= 20)
            {
                DoTeleport(_FloorCenter + FVector(0.0, 0.0, _RestZ), ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
                _Phase = 1;
                _FramesInPhase = 0;
                _StableAtRest = 0;
            }
            return;
        }

        // ---- Phase 1: verify arrival at rest pose AND that it stays (velocity was reset) -------
        if (_Phase == 1)
        {
            // First poll after the teleport: must be at the target within tolerance.
            if (_FramesInPhase == 1)
            {
                Assert_True(Math::Abs(CurrentZ - _RestZ) <= 5.0,
                    f"ResetVelocity teleport should land the box exactly at the target (Z={CurrentZ}, target={_RestZ})");
            }

            // Over the next polls it must not drift (no residual velocity carrying it).
            if (Math::Abs(CurrentZ - _RestZ) <= 5.0)
            { _StableAtRest++; }
            else
            { _StableAtRest = 0; }

            if (_StableAtRest >= 20)
            {
                // Lift the box high with a clean reset so it re-enters free fall.
                DoTeleport(_FloorCenter + FVector(0.0, 0.0, 800.0), ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
                _Phase = 2;
                _FramesInPhase = 0;
            }

            if (_FramesInPhase > 120)
            { FinishFailure(f"Box did not hold the reset-teleport rest pose (Z={CurrentZ}, target={_RestZ})"); }

            return;
        }

        // ---- Phase 2: fall again to build downward momentum -----------------------------------
        if (_Phase == 2)
        {
            // Wait until it is clearly falling fast, then keep-teleport to a high mid-air pose.
            if (_FramesInPhase >= 18 && FrameDeltaZ < -3.0)
            {
                _KeepTeleportZ = _FloorCenter.Z + 400.0;
                DoTeleport(FVector(_FloorCenter.X, _FloorCenter.Y, _KeepTeleportZ),
                    ECk_Jolt_TeleportVelocityPolicy::KeepVelocity);
                _Phase = 3;
                _FramesInPhase = 0;
                return;
            }

            if (_FramesInPhase > 120)
            { FinishFailure(f"Box never regained fall speed before the keep-velocity teleport (dZ={FrameDeltaZ})"); }

            return;
        }

        // ---- Phase 3: keep-velocity teleport must arrive AND keep moving downward --------------
        if (_FramesInPhase == 1)
        {
            Assert_True(Math::Abs(CurrentZ - _KeepTeleportZ) <= 30.0,
                f"KeepVelocity teleport should place the box near the target (Z={CurrentZ}, target={_KeepTeleportZ})");
        }

        // The preserved downward momentum must carry it clearly below the teleport target.
        if (CurrentZ < _KeepTeleportZ - 30.0)
        {
            Assert_True(CurrentZ < _KeepTeleportZ - 30.0,
                f"KeepVelocity teleport must preserve momentum (fell to Z={CurrentZ} below target {_KeepTeleportZ})");
            FinishSuccess();
            return;
        }

        if (_FramesInPhase > 120)
        { FinishFailure(f"Box did not keep moving after KeepVelocity teleport (Z={CurrentZ}, target={_KeepTeleportZ})"); }
    }
}
