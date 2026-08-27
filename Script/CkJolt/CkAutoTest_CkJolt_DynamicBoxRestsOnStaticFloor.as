// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: DYNAMIC JOLTBODY RESTS ON A STATIC JOLTBODY FLOOR
//============================================================================
//
// The simplest end-to-end simulated-body check: a Static-motion JoltBody floor
// blocks a Dynamic JoltBody box dropped from above. The box must fall, land on
// the floor top, and settle at floor-top + box-half-extent, then stay put.
//
//   1. Static JoltBody floor (ExplicitShape box, half-extents 500x500x25).
//   2. Dynamic JoltBody box (half-extent 50) dropped ~200uu above the floor top.
//   3. Poll the box's Z until stable across consecutive frames.
//   4. Assert final Z ~= floor-top + 50 (within 5uu) and that it never fell
//      through the floor.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//============================================================================

class UCk_AutoTest_CkJolt_DynamicBoxRestsOnStaticFloor : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _BoxTransform;

    private FVector _FloorCenter = FVector(0.0, 30000.0, 0.0);
    private float _FloorTopZ = 25.0;      // FloorCenter.Z + half-extent.Z
    private float _BoxHalfExtent = 50.0;
    private float _ExpectedRestZ = 75.0;  // FloorTopZ + BoxHalfExtent

    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private float _LastZ = 0.0;

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

        // ---- Dynamic box dropped from above ---------------------------------------------------
        auto BoxStart = _FloorCenter + FVector(0.0, 0.0, 250.0);
        auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BoxEntity.Request_OverrideToSelf();
        _BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxStart),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(_BoxHalfExtent, _BoxHalfExtent, _BoxHalfExtent));
        auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        utils_jolt_body::Add(BoxEntity, BoxParams);

        _LastZ = BoxStart.Z;
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        auto CurrentZ = utils_transform::Get_EntityCurrentLocation(_BoxTransform).Z;

        if (Math::Abs(CurrentZ - _LastZ) < 0.1)
        { _StableTime += float(InDeltaT.Get_Seconds()); }
        else
        { _StableTime = 0.0; }

        _LastZ = CurrentZ;

        // Settled: stable for ~0.25s of continuous rest (15 frames at the original 60fps).
        if (_StableTime >= 0.25)
        {
            Assert_True(CurrentZ > _FloorTopZ,
                f"Box must rest ON the floor, not below it (Z={CurrentZ}, floorTop={_FloorTopZ})");
            Assert_True(Math::Abs(CurrentZ - _ExpectedRestZ) <= 5.0,
                f"Box should settle at ~{_ExpectedRestZ} (got {CurrentZ})");
            FinishSuccess();
            return;
        }

        if (_Elapsed > 15.0)
        {
            FinishFailure(f"Box never settled after {_Elapsed} seconds (last Z={CurrentZ})");
        }
    }
}
