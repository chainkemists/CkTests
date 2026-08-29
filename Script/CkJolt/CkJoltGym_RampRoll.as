// Language=angelscript

//============================================================================
// CK JOLT GYM - RAMP ROLL
//
// Three parallel lanes, each a Static ramp pitched at a different angle
// (15 / 30 / 45 degrees), with a Dynamic sphere released at the top of each.
// Walk up and compare how fast/far each sphere rolls before a catch wall
// stops it - a direct visual read on how ramp angle affects rolling speed.
//
// Content is built in world -X from the station anchor (house rule: stations
// face -X) - spheres start near the anchor and roll away from the camera.
//============================================================================

class ACk_JoltGym_RampRoll_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_RampRoll_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_RampRoll_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;
    private TArray<FCk_Handle> _Spheres;

    private float _LaneSpacingY = 320.0;
    private int32 _LaneCount = 3;   // pitches: DoLanePitch(0)=15, (1)=30, (2)=45 degrees

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.RampRoll");
        Station.Title = FText::FromString("JOLT RAMP ROLL");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("3 Static ramps at 15/30/45 deg.\nDynamic spheres roll down each lane."));
        Description.Add(FText::FromString("Every control is on the panel:\n[B] release all · [1/2/3] one lane · [R] reset."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.RampRoll", ECk_GymStation_Anchor::FootprintCenter);

        for (int32 i = 0; i < _LaneCount; i++)
        {
            DoAddRampLane(DoLaneY(i), DoLanePitch(i));
        }

        DoRelease(-1);

        ck::Trace("JoltRampRollGym: started - 3 ramps built, spheres released");
    }

    private float DoLaneY(int32 InLaneIndex)
    {
        // Centers the 3 lanes around the anchor: -1, 0, +1 lane spacing.
        return (float(InLaneIndex) - 1.0) * _LaneSpacingY;
    }

    private float DoLanePitch(int32 InLaneIndex)
    {
        if (InLaneIndex == 0) { return 15.0; }
        if (InLaneIndex == 1) { return 30.0; }
        return 45.0;
    }

    private void DoAddRampLane(float InLaneY, float InPitchDegrees)
    {
        // ---- Floor strip under the ramp + catch --------------------------------------------
        DoAddStaticBox(FVector(-170.0, InLaneY, -25.0), FRotator::ZeroRotator, FVector(700.0, 140.0, 25.0), n"RampRoll.Floor");

        // ---- Ramp pitched InPitchDegrees (high end toward the anchor, low end further -X) ----
        DoAddStaticBox(FVector(0.0, InLaneY, 150.0), FRotator(InPitchDegrees, 0.0, 0.0), FVector(300.0, 130.0, 15.0), n"RampRoll.Ramp");

        // ---- Catch wall at the low end ------------------------------------------------------
        DoAddStaticBox(FVector(-640.0, InLaneY, 100.0), FRotator::ZeroRotator, FVector(10.0, 140.0, 100.0), n"RampRoll.CatchWall");
    }

    private void DoAddStaticBox(FVector InLocalOffset, FRotator InRotation, FVector InHalfExtents, FName InDebugName)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(InDebugName);
        utils_transform::Add(Entity, FTransform(InRotation, _Origin + InLocalOffset), ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);
    }

    private void DoReleaseSphereAtLane(float InLaneY, int32 InLaneIndex)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, f"RampRoll.Sphere{InLaneIndex}");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + FVector(250.0, InLaneY, 330.0)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(30.0);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.4);
        Params.Set_Restitution(0.1);
        auto Body = utils_jolt_body::Add(Entity, Params);

        FCk_Handle Generic = Body;
        _Spheres.Add(Generic);
    }

    // ---- Control panel ------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("RAMP ROLL"));
        Rows.Add(CkGym_Control::Action(EKeys::B,     "B", "Release a sphere on every lane"));
        Rows.Add(CkGym_Control::Action(EKeys::One,   "1", "Release lane 1 (15 deg)"));
        Rows.Add(CkGym_Control::Action(EKeys::Two,   "2", "Release lane 2 (30 deg)"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "Release lane 3 (45 deg)"));
        Rows.Add(CkGym_Control::Action(EKeys::R,     "R", "Reset - clear and re-release"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        { DoRelease(-1); }
        else if (InRowIndex >= 2 && InRowIndex <= 4)
        { DoRelease(InRowIndex - 2); }
        else if (InRowIndex == 5)
        { DoReset(); }
    }

    // InLaneIndex: 0/1/2 releases just that lane's sphere; anything else releases all 3.
    private void DoRelease(int32 InLaneIndex)
    {
        if (InLaneIndex >= 0 && InLaneIndex < _LaneCount)
        {
            DoReleaseSphereAtLane(DoLaneY(InLaneIndex), InLaneIndex);
            ck::Trace(f"JoltRampRollGym: released sphere on lane {InLaneIndex}");
            return;
        }

        for (int32 i = 0; i < _LaneCount; i++)
        {
            DoReleaseSphereAtLane(DoLaneY(i), i);
        }
        ck::Trace("JoltRampRollGym: released a sphere on every lane");
    }

    private void DoReset()
    {
        for (auto Sphere : _Spheres)
        {
            utils_entity_lifetime::Request_DestroyEntity(Sphere);
        }
        _Spheres.Empty();

        DoRelease(-1);
        ck::Trace("JoltRampRollGym: reset - all spheres cleared and re-released");
    }
}
