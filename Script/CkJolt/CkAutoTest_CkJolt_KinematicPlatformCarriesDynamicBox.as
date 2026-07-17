// Language=angelscript

//============================================================================
// CK JOLT — AUTOMATION TEST: KINEMATIC PLATFORM CARRIES A DYNAMIC BOX
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
    private int _FramesWaited = 0;
    private int _StableFrames = 0;
    private float _LastBoxZ = 0.0;
    private int _DriveFrame = 0;

    private float _MaxDriveX = 200.0;
    private int _DriveFrames = 150;   // ~2.5s at 60fps — gentle so friction can hold the box
    private int _HoldFrames = 60;

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

        _FramesWaited++;

        if (_Phase == 0)
        {
            // Wait for the box to settle onto the stationary platform.
            auto BoxZ = utils_transform::Get_EntityCurrentLocation(_BoxTransform).Z;
            if (Math::Abs(BoxZ - _LastBoxZ) < 0.1)
            { _StableFrames++; }
            else
            { _StableFrames = 0; }
            _LastBoxZ = BoxZ;

            if (_StableFrames >= 15)
            { _Phase = 1; }

            if (_FramesWaited > 600)
            { FinishFailure(f"Box never settled on the platform (last Z={BoxZ})"); }

            return;
        }

        // Phase 1 — drive the platform in +X, then hold.
        _DriveFrame++;

        float TargetX = _MaxDriveX;
        if (_DriveFrame < _DriveFrames)
        { TargetX = float(_DriveFrame) / float(_DriveFrames) * _MaxDriveX; }

        auto PlatformLoc = FVector(TargetX, _PlatformY, 0.0);
        utils_transform::Request_SetLocation(_PlatformTransform, PlatformLoc);

        auto BoxLoc = utils_transform::Get_EntityCurrentLocation(_BoxTransform);
        Assert_True(BoxLoc.Z > _PlatformTopZ,
            f"Box must stay on the platform, never below its top (Z={BoxLoc.Z}, top={_PlatformTopZ})");

        if (_DriveFrame >= _DriveFrames + _HoldFrames)
        {
            auto PlatformX = utils_transform::Get_EntityCurrentLocation(_PlatformTransform).X;
            Assert_True(Math::Abs(BoxLoc.X - PlatformX) <= 30.0,
                f"Box X should track the carried platform (box {BoxLoc.X} vs platform {PlatformX})");
            FinishSuccess();
        }
    }
}
