// Language=angelscript

//============================================================================
// CK JOLT GYM - DOORS (HINGE CONSTRAINTS)
//
// Three Dynamic door slabs in static frames, each hinged about the vertical
// axis with a different personality:
//   lane 0 - FREE:         +/-110 deg limits, light friction - push it open
//   lane 1 - SELF-CLOSING: +/-110 deg limits, Position motor driving to 0
//   lane 2 - TURNSTILE:    no limits, Velocity motor spinning at 90 deg/s
// Shoot balls at them (Ck_GymJoltDoors_Shoot) and watch each react. Enable
// ck.Jolt.DebugDraw.Enabled 1 to see the hinge axes and limits.
//============================================================================

class ACk_JoltGym_Doors_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_Doors_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_Doors_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;
    private TArray<FCk_Handle> _SpawnedRoots;
    private TArray<FCk_Handle> _Hinges;   // generic constraint handles; index = lane

    private float _LaneSpacingY = 300.0;
    private float _DoorHalfWidth = 60.0;
    private float _DoorHalfHeight = 95.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.Doors");
        Station.Title = FText::FromString("JOLT DOORS");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("3 hinged doors:\nFREE / SELF-CLOSING (position motor) / TURNSTILE (velocity motor)."));
        Description.Add(FText::FromString("Ck_GymJoltDoors_Shoot\nCk_GymJoltDoors_Slam\nCk_GymJoltDoors_Spin [degPerSec]\nCk_GymJoltDoors_Reset"));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.Doors", ECk_GymStation_Anchor::FootprintCenter);

        DoBuildContent();

        ck::Trace("JoltDoorsGym: started - shoot the doors with Ck_GymJoltDoors_Shoot");
    }

    private void DoBuildContent()
    {
        DoAddDoorLane(0);
        DoAddDoorLane(1);
        DoAddDoorLane(2);

        // Lane 1: self-closing - position motor drives back to the closed pose.
        auto ClosingMotor = FCk_Request_JoltConstraint_Hinge_SetMotor(ECk_JoltConstraint_MotorState::Position);
        ClosingMotor.Set_TargetAngleDegrees(0.0);
        auto ClosingHinge = utils_jolt_constraint::DoCastChecked(_Hinges[1]);
        utils_jolt_constraint::Request_Hinge_SetMotor(ClosingHinge, ClosingMotor);

        // Lane 2: turnstile - constant angular velocity.
        DoSetSpin(90.0);
    }

    private float DoLaneY(int32 InLaneIndex)
    {
        return (float(InLaneIndex) - 1.0) * _LaneSpacingY;
    }

    private void DoAddDoorLane(int32 InLaneIndex)
    {
        auto LaneY = DoLaneY(InLaneIndex);
        auto FrameX = -350.0;
        auto HingeEdge = _Origin + FVector(FrameX, LaneY - _DoorHalfWidth, _DoorHalfHeight);

        // Frame posts either side of the doorway (the turnstile lane gets none - it spins full-circle).
        if (InLaneIndex != 2)
        {
            DoAddStaticBox(FVector(FrameX, LaneY - _DoorHalfWidth - 12.0, 100.0), FVector(10.0, 10.0, 100.0), n"Doors.PostL");
            DoAddStaticBox(FVector(FrameX, LaneY + _DoorHalfWidth + 12.0, 100.0), FVector(10.0, 10.0, 100.0), n"Doors.PostR");
        }

        // The door slab extends +Y from its hinge edge.
        auto DoorCenter = HingeEdge + FVector(0.0, _DoorHalfWidth, 0.0);
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, f"Doors.Door{InLaneIndex}");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, DoorCenter),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(5.0, _DoorHalfWidth, _DoorHalfHeight));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        // A vertical-axis hinge is gravity-neutral; keep the slab from sagging against the constraint.
        Params.Set_GravityFactor(0.0);
        Params.Set_AngularDamping(0.2);
        auto Body = utils_jolt_body::Add(Entity, Params);

        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Hinge);
        ConstraintParams.Set_WorldAnchorA(HingeEdge);
        ConstraintParams.Set_HingeAxis(FVector(0.0, 0.0, 1.0));
        if (InLaneIndex != 2)
        {
            ConstraintParams.Set_LimitsMinDegrees(-110.0);
            ConstraintParams.Set_LimitsMaxDegrees(110.0);
        }
        auto Hinge = utils_jolt_constraint::Create(Body, ConstraintParams);

        FCk_Handle DoorGeneric = Entity;
        _SpawnedRoots.Add(DoorGeneric);
        FCk_Handle HingeGeneric = Hinge;
        _Hinges.Add(HingeGeneric);
    }

    private void DoAddStaticBox(FVector InLocalOffset, FVector InHalfExtents, FName InDebugName)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(InDebugName);
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + InLocalOffset),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);

        FCk_Handle Generic = Entity;
        _SpawnedRoots.Add(Generic);
    }

    UFUNCTION(Exec, DisplayName="Jolt Doors - Shoot Ball")
    void Ck_GymJoltDoors_Shoot()
    {
        auto ViewPawn = GetControlledPawn();
        if (!IsValid(ViewPawn))
        { return; }

        auto ViewRot = GetControlRotation();
        auto Forward = ViewRot.GetForwardVector();
        auto Start = ViewPawn.GetActorLocation() + Forward * 120.0;

        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, n"Doors.ShotBall");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, Start),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(18.0);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_MotionQuality(ECk_MotionQuality::LinearCast);
        auto Body = utils_jolt_body::Add(Entity, Params);

        utils_jolt_body::Request_SetLinearVelocity(Body,
            FCk_Request_JoltBody_SetLinearVelocity(Forward * 2200.0));

        FCk_Handle Generic = Entity;
        _SpawnedRoots.Add(Generic);
    }

    UFUNCTION(Exec, DisplayName="Jolt Doors - Slam All Shut")
    void Ck_GymJoltDoors_Slam()
    {
        for (int32 i = 0; i < _Hinges.Num(); i++)
        {
            if (i == 2)
            { continue; }   // the turnstile keeps spinning

            auto Motor = FCk_Request_JoltConstraint_Hinge_SetMotor(ECk_JoltConstraint_MotorState::Position);
            Motor.Set_TargetAngleDegrees(0.0);
            auto Hinge = utils_jolt_constraint::DoCastChecked(_Hinges[i]);
            utils_jolt_constraint::Request_Hinge_SetMotor(Hinge, Motor);
        }

        ck::Trace("JoltDoorsGym: slammed shut");
    }

    UFUNCTION(Exec, DisplayName="Jolt Doors - Set Turnstile Spin")
    void Ck_GymJoltDoors_Spin(float InDegPerSec = 90.0)
    {
        DoSetSpin(InDegPerSec);
        ck::Trace(f"JoltDoorsGym: turnstile spin set to {InDegPerSec} deg/s");
    }

    private void DoSetSpin(float InDegPerSec)
    {
        if (_Hinges.Num() < 3)
        { return; }

        auto Motor = FCk_Request_JoltConstraint_Hinge_SetMotor(ECk_JoltConstraint_MotorState::Velocity);
        Motor.Set_TargetAngularVelocityDegS(InDegPerSec);
        auto Hinge = utils_jolt_constraint::DoCastChecked(_Hinges[2]);
        utils_jolt_constraint::Request_Hinge_SetMotor(Hinge, Motor);
    }

    UFUNCTION(Exec, DisplayName="Jolt Doors - Reset")
    void Ck_GymJoltDoors_Reset()
    {
        for (auto Root : _SpawnedRoots)
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
        _SpawnedRoots.Empty();
        _Hinges.Empty();

        DoBuildContent();
        ck::Trace("JoltDoorsGym: reset");
    }
}
