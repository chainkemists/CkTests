// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: DISTANCE-SPRING CONSTRAINT SETTLES AT REST LENGTH
//============================================================================
//
// A Dynamic sphere hangs from a WORLD anchor on a Distance constraint with
// soft (spring) limits. The rest length is auto-derived from the creation
// separation (200uu). The sphere must fall into the spring, oscillate, and
// settle with its center ~200uu below the anchor (a small static sag from
// gravity is expected and covered by the tolerance).
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_Constraint_SpringSettlesAtRestLength : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _BallTransform;

    private FVector _Anchor = FVector(0.0, 75000.0, 400.0);
    private float _RestLength = 200.0;

    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private float _LastZ = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        auto BallStart = _Anchor - FVector(0.0, 0.0, _RestLength);
        auto BallEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BallEntity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(BallEntity, n"SpringTest.Ball");
        _BallTransform = utils_transform::Add(BallEntity, FTransform(FRotator::ZeroRotator, BallStart),
            ECk_Replication::DoesNotReplicate);

        auto BallShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        BallShape.Set_Radius(20.0);
        auto BallParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BallParams.Set_ShapeDimensions(BallShape);
        BallParams.Set_MotionType(ECk_MotionType::Dynamic);
        auto BallBody = utils_jolt_body::Add(BallEntity, BallParams);

        // World-anchored spring: OtherBody left INVALID = the world. Auto range (min/max -1) derives
        // the 200uu rest length from the creation separation.
        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Distance);
        ConstraintParams.Set_WorldAnchorA(BallStart);
        ConstraintParams.Set_WorldAnchorB(_Anchor);
        ConstraintParams.Set_UseSpring(ECk_EnableDisable::Enable);
        ConstraintParams.Set_SpringFrequencyOrStiffness(2.0);
        ConstraintParams.Set_SpringDamping(0.9);
        utils_jolt_constraint::Create(BallBody, ConstraintParams);

        _LastZ = BallStart.Z;
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        auto Current = utils_transform::Get_EntityCurrentLocation(_BallTransform);

        if (Math::Abs(Current.Z - _LastZ) < 0.1)
        { _StableTime += float(InDeltaT.Get_Seconds()); }
        else
        { _StableTime = 0.0; }

        _LastZ = Current.Z;

        if (_StableTime >= 0.25)
        {
            auto Separation = (_Anchor - Current).Size();
            Assert_True(Math::Abs(Separation - _RestLength) <= 30.0,
                f"Spring should settle ~{_RestLength}uu from the anchor (got {Separation})");
            Assert_True(Math::Abs(Current.X - _Anchor.X) <= 10.0,
                f"Ball should hang straight below the anchor (X drift {Current.X - _Anchor.X})");
            FinishSuccess();
            return;
        }

        if (_Elapsed > 15.0)
        {
            FinishFailure(f"Spring never settled after {_Elapsed} seconds (last Z={_LastZ})");
        }
    }
}
