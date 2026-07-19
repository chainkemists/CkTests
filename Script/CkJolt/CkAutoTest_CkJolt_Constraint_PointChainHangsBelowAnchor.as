// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: POINT CONSTRAINT PENDULUM HANGS BELOW ITS ANCHOR
//============================================================================
//
// A Dynamic sphere is pinned to a WORLD point 50uu above its center (a Point
// constraint — the rope/chain link primitive). A sideways impulse swings it;
// damping settles it. At rest the center must hang straight below the anchor
// at the creation separation — the pendulum length is preserved and rotation
// stayed free.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_Constraint_PointChainHangsBelowAnchor : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _BallTransform;

    private FVector _Anchor = FVector(0.0, 78000.0, 500.0);
    private float _PendulumLength = 50.0;

    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private FVector _Last = FVector::ZeroVector;
    private float _MaxDriftX = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto BallStart = _Anchor - FVector(0.0, 0.0, _PendulumLength);
        auto BallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BallEntity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(BallEntity, n"PointTest.Ball");
        _BallTransform = utils_transform::Add(BallEntity, FTransform(FRotator::ZeroRotator, BallStart),
            ECk_Replication::DoesNotReplicate);

        auto BallShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        BallShape.Set_Radius(15.0);
        auto BallParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BallParams.Set_ShapeDimensions(BallShape);
        BallParams.Set_MotionType(ECk_MotionType::Dynamic);
        // Extra damping so the swing settles well inside the test window.
        BallParams.Set_LinearDamping(0.8);
        BallParams.Set_AngularDamping(0.8);
        auto BallBody = utils_jolt_body::Add(BallEntity, BallParams);

        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Point);
        ConstraintParams.Set_WorldAnchorA(_Anchor);
        ConstraintParams.Set_WorldAnchorB(_Anchor);
        utils_jolt_constraint::Create(BallBody, ConstraintParams);

        // Kick it sideways so the test proves a real swing happened before the rest-pose assert.
        // FromShape masses are enormous in this cm-scale world (see ImpulseChangesVelocity's 4e11):
        // a r=15 sphere weighs ~1.4e7 mass units, so 5e9 imparts a ~350 cm/s swing.
        utils_jolt_body::Request_AddImpulse(BallBody, FCk_Request_JoltBody_AddImpulse(FVector(5000000000.0, 0.0, 0.0)));

        _Last = BallStart;
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        auto Current = utils_transform::Get_EntityCurrentLocation(_BallTransform);
        _MaxDriftX = Math::Max(_MaxDriftX, Math::Abs(Current.X - _Anchor.X));

        if ((Current - _Last).Size() < 0.1)
        { _StableTime += float(InDeltaT.Get_Seconds()); }
        else
        { _StableTime = 0.0; }

        _Last = Current;

        if (_StableTime >= 0.25)
        {
            Assert_True(_MaxDriftX > 5.0,
                f"The impulse should have produced a real swing (max X drift {_MaxDriftX})");

            auto Separation = (_Anchor - Current).Size();
            Assert_True(Math::Abs(Separation - _PendulumLength) <= 10.0,
                f"Pendulum length should be preserved at ~{_PendulumLength}uu (got {Separation})");
            Assert_True(Current.Z < _Anchor.Z,
                f"Ball must hang BELOW the anchor (Z={Current.Z}, anchor Z={_Anchor.Z})");
            FinishSuccess();
            return;
        }

        if (_Elapsed > 15.0)
        {
            FinishFailure(f"Pendulum never settled after {_Elapsed} seconds");
        }
    }
}
