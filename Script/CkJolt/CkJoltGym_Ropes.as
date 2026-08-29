// Language=angelscript

//============================================================================
// CK JOLT GYM - ROPES
//
// Three ropes hang from a gantry, built by utils_jolt_rope::Create_Rope:
//   lane 0 - Rigid chain, 10 segments
//   lane 1 - Springy (stretchy) rope, 10 segments
//   lane 2 - Rigid chain, 14 segments with a heavy pendulum ball pinned to
//            the tail, released swinging
// Yank the tails, or CUT a rope (destroys its middle link - the lower half
// drops). Toggle [J] to see segments + links.
//============================================================================

class ACk_JoltGym_Ropes_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_Ropes_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_Ropes_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;
    private TArray<FCk_Handle> _RopeRoots;                  // one root entity per rope - cascade cleanup
    private TArray<FCk_JoltRope_Result> _Ropes;             // index = lane

    private float _LaneSpacingY = 240.0;
    private float _GantryZ = 620.0;

    // Mirror of ck.Jolt.DebugDraw.Enabled - mirrored in a member because the module exposes no
    // AS readback for it; EndPlay writes it back to its default (off) only if this gym touched it.
    private bool _JoltDrawEnabled = false;
    private bool _JoltDrawTouched = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.Ropes");
        Station.Title = FText::FromString("JOLT ROPES");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Rigid chain / stretchy rope / pendulum.\nBuilt by utils_jolt_rope::Create_Rope."));
        Description.Add(FText::FromString("Every control is on the panel:\n[B] yank all · [1/2/3] cut one rope · [R] reset · [J] Jolt debug draw."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.Ropes", ECk_GymStation_Anchor::FootprintCenter);

        DoBuildContent();

        ck::Trace("JoltRopesGym: started - 3 ropes hung; yank or cut them");
    }

    private void DoBuildContent()
    {
        // Gantry bar all three ropes hang from.
        DoAddStaticBox(FVector(-350.0, 0.0, _GantryZ + 20.0), FVector(40.0, 400.0, 10.0));

        DoAddRope(0, 10, ECk_JoltRope_LinkMode::Rigid);
        DoAddRope(1, 10, ECk_JoltRope_LinkMode::Springy);
        auto PendulumRope = DoAddRope(2, 14, ECk_JoltRope_LinkMode::Rigid);
        DoAddPendulumBall(PendulumRope);
    }

    private float DoLaneY(int32 InLaneIndex)
    {
        return (float(InLaneIndex) - 1.0) * _LaneSpacingY;
    }

    private FCk_JoltRope_Result DoAddRope(int32 InLaneIndex, int32 InSegmentCount, ECk_JoltRope_LinkMode InLinkMode)
    {
        auto Root = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Root.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Root, f"Ropes.Root{InLaneIndex}");

        auto RopeParams = FCk_JoltRope_ParamsData(_Origin + FVector(-350.0, DoLaneY(InLaneIndex), _GantryZ));
        RopeParams.Set_SegmentCount(InSegmentCount);
        RopeParams.Set_SegmentLength(40.0);
        RopeParams.Set_SegmentRadius(7.0);
        RopeParams.Set_SegmentMassKg(2.0);
        RopeParams.Set_LinkMode(InLinkMode);

        auto Rope = utils_jolt_rope::Create_Rope(Root, RopeParams);

        _RopeRoots.Add(Root);
        _Ropes.Add(Rope);
        return Rope;
    }

    private void DoAddPendulumBall(FCk_JoltRope_Result InRope)
    {
        if (InRope.Get_Segments().Num() == 0)
        { return; }

        auto TailBody = InRope.Get_Segments()[InRope.Get_Segments().Num() - 1];
        auto TailLocation = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(TailBody));
        auto BallCenter = TailLocation - FVector(0.0, 0.0, 70.0);

        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, n"Ropes.PendulumBall");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, BallCenter),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(40.0);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_MassSource(ECk_JoltBody_MassSource::Explicit);
        Params.Set_MassKg(30.0);
        auto BallBody = utils_jolt_body::Add(Entity, Params);

        // Pin the ball to the rope tail, then start it swinging.
        FCk_Handle TailGeneric = TailBody;
        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Point);
        ConstraintParams.Set_OtherBody(TailGeneric);
        ConstraintParams.Set_WorldAnchorA(TailLocation);
        ConstraintParams.Set_WorldAnchorB(TailLocation);
        utils_jolt_constraint::Create(BallBody, ConstraintParams);

        utils_jolt_body::Request_AddImpulse(BallBody, FCk_Request_JoltBody_AddImpulse(FVector(-45000.0, 0.0, 0.0)));

        FCk_Handle Generic = Entity;
        _RopeRoots.Add(Generic);
    }

    private void DoAddStaticBox(FVector InLocalOffset, FVector InHalfExtents)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"Ropes.Gantry");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + InLocalOffset),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);

        FCk_Handle Generic = Entity;
        _RopeRoots.Add(Generic);
    }

    // ---- Control panel ------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("ROPES"));
        Rows.Add(CkGym_Control::Action(EKeys::B,     "B", "Yank all three tails"));
        Rows.Add(CkGym_Control::Action(EKeys::One,   "1", "Cut rope 1 (rigid chain)"));
        Rows.Add(CkGym_Control::Action(EKeys::Two,   "2", "Cut rope 2 (springy)"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "Cut rope 3 (pendulum)"));
        Rows.Add(CkGym_Control::Action(EKeys::R,     "R", "Reset - rebuild all ropes"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J,     "J", "Jolt debug draw", _JoltDrawEnabled));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        { DoYank(-1); }
        else if (InRowIndex >= 2 && InRowIndex <= 4)
        { DoCut(InRowIndex - 2); }
        else if (InRowIndex == 5)
        { DoReset(); }
        else if (InRowIndex == 6)
        {
            _JoltDrawEnabled = !_JoltDrawEnabled;
            _JoltDrawTouched = true;
            System::ExecuteConsoleCommand(f"ck.Jolt.DebugDraw.Enabled {(_JoltDrawEnabled ? 1 : 0)}");
        }
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        // No AS readback exists for the cvar, so a faithful capture/restore is impossible - put it
        // back to its module default only if this gym flipped it, so a value the USER set outside
        // the gym is never stomped by a gym they never touched the toggle in.
        if (_JoltDrawTouched)
        { System::ExecuteConsoleCommand("ck.Jolt.DebugDraw.Enabled 0"); }
    }

    // InLaneIndex 0/1/2 yanks one rope's tail; anything else yanks all.
    private void DoYank(int32 InLaneIndex)
    {
        for (int32 i = 0; i < _Ropes.Num(); i++)
        {
            if (InLaneIndex >= 0 && i != InLaneIndex)
            { continue; }

            auto Segments = _Ropes[i].Get_Segments();
            if (Segments.Num() == 0)
            { continue; }

            auto Tail = Segments[Segments.Num() - 1];
            utils_jolt_body::Request_AddImpulse(Tail, FCk_Request_JoltBody_AddImpulse(FVector(-8000.0, 3000.0, 0.0)));
        }

        ck::Trace("JoltRopesGym: yanked");
    }

    // Destroys the middle link of the given rope - the lower half drops free.
    private void DoCut(int32 InLaneIndex)
    {
        if (InLaneIndex < 0 || InLaneIndex >= _Ropes.Num())
        {
            ck::Trace("JoltRopesGym: no such rope to cut");
            return;
        }

        auto Links = _Ropes[InLaneIndex].Get_Links();
        if (Links.Num() < 2)
        {
            ck::Trace("JoltRopesGym: rope too short to cut");
            return;
        }

        FCk_Handle MiddleLink = Links[Math::IntegerDivisionTrunc(Links.Num(), 2)];
        if (ck::Is_NOT_Valid(MiddleLink))
        {
            ck::Trace("JoltRopesGym: that rope is already cut");
            return;
        }

        utils_entity_lifetime::Request_DestroyEntity(MiddleLink);
        ck::Trace(f"JoltRopesGym: cut rope {InLaneIndex}");
    }

    private void DoReset()
    {
        for (auto Root : _RopeRoots)
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
        _RopeRoots.Empty();
        _Ropes.Empty();

        DoBuildContent();
        ck::Trace("JoltRopesGym: reset");
    }
}
