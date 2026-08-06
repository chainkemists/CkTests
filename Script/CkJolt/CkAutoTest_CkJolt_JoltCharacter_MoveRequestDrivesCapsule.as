// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: CHARACTER MOVE REQUEST DRIVES THE CAPSULE
//============================================================================
//
// A grounded JoltCharacter must translate at the Move request's desired velocity
// while remaining supported:
//
//   1. Static JoltBody floor + a JoltCharacter (capsule radius 40, half-height 60)
//      resting on it (capsule is CENTERED at the entity position -> rest centre Z =
//      floorTop + halfHeight + radius = 25 + 60 + 40 = 125).
//   2. Request_Move a lateral 200uu/s (+X); let the velocity stabilise.
//   3. Assert X advances at ~200uu/s (+/-30%) over a 1s window and Get_GroundState
//      reports OnGround.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_JoltCharacter_MoveRequestDrivesCapsule : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltCharacter _Char;
    private FCk_Handle_Transform _CharTransform;

    private float _ParkY = 63000.0;
    private float _MoveSpeed = 200.0;

    private int _Phase = 0;   // 0 = setup/settle, 1 = let speed stabilise, 2 = measure window
    private float _StartX = 0.0;
    private float _Elapsed = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Static floor ---------------------------------------------------------------------
        auto FloorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        FloorEntity.Request_OverrideToSelf();
        utils_transform::Add(FloorEntity, FTransform(FRotator::ZeroRotator, FVector(0.0, _ParkY, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto FloorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        FloorShape.Set_HalfExtents(FVector(500.0, 500.0, 25.0));
        auto FloorParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        FloorParams.Set_ShapeDimensions(FloorShape);
        FloorParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(FloorEntity, FloorParams);

        // ---- Character resting on the floor (capsule centre at floorTop + 100) ----------------
        auto CharStart = FVector(0.0, _ParkY, 125.0);
        auto CharEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        CharEntity.Request_OverrideToSelf();
        _CharTransform = utils_transform::Add(CharEntity, FTransform(FRotator::ZeroRotator, CharStart),
            ECk_Replication::DoesNotReplicate);

        auto CharParams = FCk_JoltCharacter_Spec(40.0, 60.0);
        _Char = utils_jolt_character::Add(CharEntity, CharParams);

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // ---- Phase 0: let the character finish setup and settle, then request Move ------------
        if (_Phase == 0)
        {
            _Elapsed += float(InDeltaT.Get_Seconds());
            if (_Elapsed >= 0.5)
            {
                utils_jolt_character::Request_Move(_Char,
                    FCk_Request_JoltCharacter_Move(FVector(_MoveSpeed, 0.0, 0.0)));
                _Phase = 1;
                _Elapsed = 0.0;
            }
            return;
        }

        // ---- Phase 1: let the horizontal velocity reach steady state --------------------------
        if (_Phase == 1)
        {
            _Elapsed += float(InDeltaT.Get_Seconds());
            if (_Elapsed >= 0.167)
            {
                _StartX = utils_transform::Get_EntityCurrentLocation(_CharTransform).X;
                _Elapsed = 0.0;
                _Phase = 2;
            }
            return;
        }

        // ---- Phase 2: measure average X velocity over a 1s window -----------------------------
        _Elapsed += float(InDeltaT.Get_Seconds());

        if (_Elapsed >= 1.0)
        {
            auto CurrentX = utils_transform::Get_EntityCurrentLocation(_CharTransform).X;
            auto AvgVelX = (CurrentX - _StartX) / _Elapsed;

            Assert_True(AvgVelX >= _MoveSpeed * 0.7 && AvgVelX <= _MoveSpeed * 1.3,
                f"Character X should advance at ~{_MoveSpeed}uu/s (+/-30%), measured {AvgVelX}uu/s");
            Assert_True(utils_jolt_character::Get_GroundState(_Char) == ECk_JoltCharacter_GroundState::OnGround,
                "Character should report OnGround while walking after the move window");
            FinishSuccess();
        }
    }
}
