// Language=angelscript

//============================================================================
// CK JOLT - AUTOMATION TEST: KINEMATIC PLATFORM CARRIES A DYNAMIC BOX
//============================================================================
//
// A Kinematic JoltBody driven from its ECS transform must carry a resting
// Dynamic JoltBody via contact friction (KinematicFromECS is automatic for
// MotionType Kinematic; the KinematicPush processor MoveKinematic's the body
// to the ECS transform each stepping frame, imparting velocity).
//
//   1. Kinematic platform (wide thin box) + a Dynamic box resting on it.
//   2. Let the box settle onto the platform.
//   3. Drive the platform ~200uu in +X over ~2s via the standard Transform
//      Request_SetLocation, then hold.
//   4. Assert the box's X tracked the platform (within +/-30uu) and it never
//      fell below the platform top.
//
// Placed at an isolated Y so it never touches other autotests' physics bodies.
//
// The drive clock accumulates the tick delta CLAMPED to 1/30. The Jolt pump is
// fixed-timestep (60Hz, max 4 sub-steps/frame, excess DROPPED - ComputeStepPlan,
// CkJoltWorld.cpp), so under frame hitches sim time lags game time; a game-clock
// ramp then moves the kinematic target faster in SIM time than authored and
// friction drops the box (see the Chaos twin's header for the full mechanism).
// With the clamp the drive never outruns what the sim integrates (max sim
// advance 4/60 = 0.0667 >= the 0.0333 clamp), so the ramp holds at any frame
// rate. The +/-30 assertion is unchanged.
//============================================================================

class UCk_AutoTest_CkJolt_KinematicPlatformCarriesDynamicBox : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Transform _PlatformTransform;
    private FCk_Handle_Transform _BoxTransform;

    private float _PlatformY = 38000.0;
    private float _PlatformTopZ = 25.0;   // platform center Z 0 + half-height 25

    private int _Phase = 0;   // 0 = settling, 1 = driving + holding
    private float _Elapsed = 0.0;
    private float _StableTime = 0.0;
    private float _LastBoxZ = 0.0;
    private float _DriveTime = 0.0;

    private float _MaxDriveX = 200.0;
    private float _DriveDuration = 2.5;   // gentle ramp so friction can hold the box
    private float _HoldDuration = 1.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _SelfHandle = InHandle;

        // ---- Kinematic platform ---------------------------------------------------------------
        auto PlatformCenter = FVector(0.0, _PlatformY, 0.0);
        auto PlatformEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PlatformEntity.Request_OverrideToSelf();
        _PlatformTransform = utils_transform::Add(PlatformEntity,
            FTransform(FRotator::ZeroRotator, PlatformCenter), ECk_Replication::DoesNotReplicate);

        auto PlatformShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        PlatformShape.Set_HalfExtents(FVector(300.0, 300.0, 25.0));
        auto PlatformParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        PlatformParams.Set_ShapeDimensions(PlatformShape);
        PlatformParams.Set_MotionType(ECk_MotionType::Kinematic);
        // A carry test needs grip: default friction (0.2) lets the box slide instead of tracking.
        PlatformParams.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        PlatformParams.Set_Friction(1.0);
        utils_jolt_body::Add(PlatformEntity, PlatformParams);

        // ---- Dynamic box resting on the platform ----------------------------------------------
        auto BoxStart = FVector(0.0, _PlatformY, 80.0);   // just above platform top + box half-extent (75)
        auto BoxEntity = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        BoxEntity.Request_OverrideToSelf();
        _BoxTransform = utils_transform::Add(BoxEntity, FTransform(FRotator::ZeroRotator, BoxStart),
            ECk_Replication::DoesNotReplicate);

        auto BoxShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        BoxShape.Set_HalfExtents(FVector(50.0, 50.0, 50.0));
        auto BoxParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        BoxParams.Set_ShapeDimensions(BoxShape);
        BoxParams.Set_MotionType(ECk_MotionType::Dynamic);
        BoxParams.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        BoxParams.Set_Friction(1.0);
        utils_jolt_body::Add(BoxEntity, BoxParams);

        _LastBoxZ = BoxStart.Z;
        utils_timer::Create_Tick(_SelfHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto SimDt = Math::Min(float(InDeltaT.Get_Seconds()), 0.0333f);

        if (_Phase == 0)
        {
            _Elapsed += SimDt;

            // Wait for the box to settle onto the stationary platform.
            auto BoxZ = utils_transform::Get_EntityCurrentLocation(_BoxTransform).Z;
            if (Math::Abs(BoxZ - _LastBoxZ) < 0.1)
            { _StableTime += SimDt; }
            else
            { _StableTime = 0.0; }
            _LastBoxZ = BoxZ;

            if (_StableTime >= 0.25)
            { _Phase = 1; }

            if (_Elapsed > 10.0)
            { FinishFailure(f"Box never settled on the platform (last Z={BoxZ})"); }

            return;
        }

        // Phase 1 - drive the platform in +X, then hold.
        _DriveTime += SimDt;

        float TargetX = _MaxDriveX;
        if (_DriveTime < _DriveDuration)
        { TargetX = (_DriveTime / _DriveDuration) * _MaxDriveX; }

        auto PlatformLoc = FVector(TargetX, _PlatformY, 0.0);
        utils_transform::Request_SetLocation(_PlatformTransform, PlatformLoc);

        auto BoxLoc = utils_transform::Get_EntityCurrentLocation(_BoxTransform);
        Assert_True(BoxLoc.Z > _PlatformTopZ,
            f"Box must stay on the platform, never below its top (Z={BoxLoc.Z}, top={_PlatformTopZ})");

        if (_DriveTime >= _DriveDuration + _HoldDuration)
        {
            auto PlatformX = utils_transform::Get_EntityCurrentLocation(_PlatformTransform).X;
            Assert_True(Math::Abs(BoxLoc.X - PlatformX) <= 30.0,
                f"Box X should track the carried platform (box {BoxLoc.X} vs platform {PlatformX})");
            FinishSuccess();
        }
    }
}
