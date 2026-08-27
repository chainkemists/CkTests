// Language=angelscript

//============================================================================
// CK JOLT GYM - PROJECTILE CCD
//
// Two lanes side by side, both firing a fast (12000uu/s) Dynamic sphere at a
// thin Static wall:
//   Lane A (CCD ON)  - MotionQuality LinearCast: stops dead at the wall.
//   Lane B (CCD OFF) - MotionQuality Discrete: may tunnel straight through
//                       (frame-timing dependent - that's the point of the demo).
//
// Auto-cycles every ~3.5s: reset both projectiles to the start line, fire,
// then log each lane's post-flight speed (utils_jolt_body::Get_LinearVelocity)
// so the CCD-caught-it vs CCD-missed-it outcome is visible in the log too.
//
// Content is built in world -X from the station anchor (house rule: stations
// face -X) - projectiles start near the anchor and fire further into -X.
//============================================================================

class ACk_JoltGym_ProjectileCcd_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_ProjectileCcd_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_ProjectileCcd_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;

    private FCk_Handle_JoltBody _CcdOnBody;
    private FCk_Handle_JoltBody _CcdOffBody;

    private float _LaneOnY = -150.0;
    private float _LaneOffY = 150.0;
    private float _StartLocalX = -50.0;
    private float _WallLocalX = -500.0;
    private float _LaunchSpeed = 12000.0;

    // Cycle timeline (seconds, accumulated tick delta - NEVER derived from a per-tick divide):
    //   0.00 -> teleport both back to the start line
    //   0.15 -> fire both at _LaunchSpeed toward -X
    //   0.85 -> log each lane's post-flight speed
    //   3.50 -> loop
    private float _CyclePeriod = 3.5;
    private float _CycleElapsed = 0.0;
    private bool _DidReset = false;
    private bool _DidFire = false;
    private bool _DidLog = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.ProjectileCcd");
        Station.Title = FText::FromString("JOLT PROJECTILE CCD");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Lane A (CCD ON) stops at the thin wall.\nLane B (CCD OFF) may tunnel through."));
        Description.Add(FText::FromString("Auto-fires every ~3.5s.\nCk_GymJoltProjectileCcd_Fire to fire now."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.ProjectileCcd", ECk_GymStation_Anchor::FootprintCenter);

        DoAddWall(_LaneOnY);
        DoAddWall(_LaneOffY);

        _CcdOnBody = DoAddProjectile(_LaneOnY, ECk_MotionQuality::LinearCast, n"ProjectileCcd.CcdOn");
        _CcdOffBody = DoAddProjectile(_LaneOffY, ECk_MotionQuality::Discrete, n"ProjectileCcd.CcdOff");

        utils_timer::Create_Tick(ck::ToEntity(this), FCk_Delegate_Timer(this, n"OnTick"));

        ck::Trace("JoltProjectileCcdGym: started - auto-firing every ~3.5s");
    }

    private void DoAddWall(float InLaneY)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"ProjectileCcd.Wall");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + FVector(_WallLocalX, InLaneY, 300.0)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(5.0, 150.0, 150.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);
    }

    private FCk_Handle_JoltBody DoAddProjectile(float InLaneY, ECk_MotionQuality InMotionQuality, FName InDebugName)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(InDebugName);
        utils_transform::Add(Entity,
            FTransform(FRotator::ZeroRotator, _Origin + FVector(_StartLocalX, InLaneY, 300.0)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(10.0);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_MotionQuality(InMotionQuality);
        Params.Set_GravityFactor(0.0);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.0);
        Params.Set_Restitution(0.0);
        return utils_jolt_body::Add(Entity, Params);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        _CycleElapsed += float(InDeltaT.Get_Seconds());

        if (!_DidReset && _CycleElapsed >= 0.0)
        {
            DoResetLane(_CcdOnBody, _LaneOnY);
            DoResetLane(_CcdOffBody, _LaneOffY);
            _DidReset = true;
        }

        if (!_DidFire && _CycleElapsed >= 0.15)
        {
            utils_jolt_body::Request_SetLinearVelocity(_CcdOnBody,
                FCk_Request_JoltBody_SetLinearVelocity(FVector(-_LaunchSpeed, 0.0, 0.0)));
            utils_jolt_body::Request_SetLinearVelocity(_CcdOffBody,
                FCk_Request_JoltBody_SetLinearVelocity(FVector(-_LaunchSpeed, 0.0, 0.0)));
            _DidFire = true;
        }

        if (!_DidLog && _CycleElapsed >= 0.85)
        {
            auto OnSpeed = utils_jolt_body::Get_LinearVelocity(_CcdOnBody).Size();
            auto OffSpeed = utils_jolt_body::Get_LinearVelocity(_CcdOffBody).Size();
            ck::Trace(f"JoltProjectileCcdGym: CCD ON speed={OnSpeed} (stopped if near 0) | CCD OFF speed={OffSpeed} (still moving if tunneled)");
            _DidLog = true;
        }

        if (_CycleElapsed >= _CyclePeriod)
        {
            _CycleElapsed = 0.0;
            _DidReset = false;
            _DidFire = false;
            _DidLog = false;
        }
    }

    private void DoResetLane(FCk_Handle_JoltBody InBody, float InLaneY)
    {
        auto Request = FCk_Request_JoltBody_Teleport(_Origin + FVector(_StartLocalX, InLaneY, 300.0), FRotator::ZeroRotator);
        Request.Set_VelocityPolicy(ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
        utils_jolt_body::Request_Teleport(InBody, Request);
    }

    UFUNCTION(Exec, DisplayName="Jolt ProjectileCcd - Fire Now")
    void Ck_GymJoltProjectileCcd_Fire()
    {
        _CycleElapsed = 0.0;
        _DidReset = false;
        _DidFire = false;
        _DidLog = false;
        ck::Trace("JoltProjectileCcdGym: manual fire requested - cycle restarting");
    }
}
