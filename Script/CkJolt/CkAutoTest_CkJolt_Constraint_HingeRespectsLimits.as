// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: HINGE CONSTRAINT RESPECTS ITS ANGLE LIMITS
//============================================================================
//
// A Dynamic "door" slab is hinged to the WORLD about a vertical axis with
// +/-30 degree limits and friction torque. An impulse at the free edge slams
// it open; the hinge must stop the swing inside the limits and the friction
// settles it. Asserts a real swing happened, the settled angle is inside the
// limits (+ tolerance), and Get_Hinge_CurrentAngleDegrees reports it.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_Constraint_HingeRespectsLimits : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_JoltConstraint _Hinge;

    private FVector _Pivot = FVector(0.0, 81000.0, 300.0);
    private float _LimitDegrees = 30.0;

    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private float _LastAngle = 0.0;
    private float _MaxAbsAngle = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // Door slab extends +Y from the pivot edge; hinge axis is world +Z.
        auto DoorCenter = _Pivot + FVector(0.0, 60.0, 0.0);
        auto DoorEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        DoorEntity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(DoorEntity, n"HingeTest.Door");
        utils_transform::Add(DoorEntity, FTransform(FRotator::ZeroRotator, DoorCenter),
            ECk_Replication::DoesNotReplicate);

        auto DoorShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        DoorShape.Set_HalfExtents(FVector(4.0, 60.0, 90.0));
        auto DoorParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        DoorParams.Set_ShapeDimensions(DoorShape);
        DoorParams.Set_MotionType(ECk_MotionType::Dynamic);
        // A door hinged about Z is gravity-neutral; heavy ANGULAR damping (exponential, unit-free)
        // is what settles it — friction torque would need absurd values at FromShape mass scale.
        DoorParams.Set_GravityFactor(0.0);
        DoorParams.Set_AngularDamping(1.0);
        auto DoorBody = utils_jolt_body::Add(DoorEntity, DoorParams);

        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Hinge);
        ConstraintParams.Set_WorldAnchorA(_Pivot);
        ConstraintParams.Set_HingeAxis(FVector(0.0, 0.0, 1.0));
        ConstraintParams.Set_LimitsMinDegrees(-_LimitDegrees);
        ConstraintParams.Set_LimitsMaxDegrees(_LimitDegrees);
        _Hinge = utils_jolt_constraint::Create(DoorBody, ConstraintParams);

        // Slam the free edge — way harder than the limits allow, so the stop is what ends the swing.
        // 4e10 at a 55cm arm on this ~1.7e8-mass-unit slab spins it ~150 deg/s into the stop.
        utils_jolt_body::Request_AddImpulseAtLocation(DoorBody,
            FCk_Request_JoltBody_AddImpulseAtLocation(FVector(40000000000.0, 0.0, 0.0), _Pivot + FVector(0.0, 115.0, 0.0)));

        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        auto Angle = utils_jolt_constraint::Get_Hinge_CurrentAngleDegrees(_Hinge);
        _MaxAbsAngle = Math::Max(_MaxAbsAngle, Math::Abs(Angle));

        if (Math::Abs(Angle - _LastAngle) < 0.05)
        { _StableTime += float(InDeltaT.Get_Seconds()); }
        else
        { _StableTime = 0.0; }

        _LastAngle = Angle;

        if (_StableTime >= 0.25)
        {
            Assert_True(_MaxAbsAngle > 5.0,
                f"The impulse should have produced a real swing (max angle {_MaxAbsAngle})");
            Assert_True(Math::Abs(Angle) <= _LimitDegrees + 5.0,
                f"Hinge must settle INSIDE its +/-{_LimitDegrees} deg limits (got {Angle})");
            FinishSuccess();
            return;
        }

        if (_Elapsed > 15.0)
        {
            FinishFailure(f"Door never settled after {_Elapsed} seconds (angle {_LastAngle}, max {_MaxAbsAngle})");
        }
    }
}
