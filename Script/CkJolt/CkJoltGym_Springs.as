// Language=angelscript

//============================================================================
// CK JOLT GYM - SPRINGS
//
// Three Dynamic plates hang from a gantry on Distance constraints with SOFT
// (spring) limits at different frequencies - floppy (1 Hz), medium (3 Hz),
// stiff (8 Hz) - plus a bungee ball on a long low-frequency spring. Poke them
// and compare the oscillation. Toggle [J] to see the bodies; the constraint
// anchors need ck.Jolt.DebugDraw.Constraints on top of it.
//
// Content is built in world -X from the station anchor (house rule: stations
// face -X).
//============================================================================

class ACk_JoltGym_Springs_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_Springs_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_Springs_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;
    private TArray<FCk_Handle> _SpawnedRoots;
    private TArray<FCk_Handle> _Plates;   // generic handles; index = lane

    private float _LaneSpacingY = 260.0;
    private float _GantryZ = 420.0;
    private float _HangLength = 220.0;

    // Mirror of ck.Jolt.DebugDraw.Enabled - mirrored in a member because the module exposes no
    // AS readback for it; EndPlay writes it back to its default (off) only if this gym touched it.
    private bool _JoltDrawEnabled = false;
    private bool _JoltDrawTouched = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.Springs");
        Station.Title = FText::FromString("JOLT SPRINGS");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("3 plates on soft distance springs:\n1 Hz floppy / 3 Hz medium / 8 Hz stiff\n+ a bungee ball."));
        Description.Add(FText::FromString("Every control is on the panel:\n[B] poke all · [1/2/3] one plate · [4] the bungee · [R] reset · [J] Jolt debug draw."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.Springs", ECk_GymStation_Anchor::FootprintCenter);

        DoBuildContent();

        ck::Trace("JoltSpringsGym: started - poke the plates with [B]");
    }

    private void DoBuildContent()
    {
        // Visual gantry bar the springs hang from.
        DoAddStaticBox(FVector(-300.0, 0.0, _GantryZ + 20.0), FVector(40.0, 420.0, 8.0), n"Springs.Gantry");

        DoAddSpringPlate(0, 1.0, 0.2);
        DoAddSpringPlate(1, 3.0, 0.4);
        DoAddSpringPlate(2, 8.0, 0.7);

        DoAddBungeeBall();
    }

    private float DoLaneY(int32 InLaneIndex)
    {
        return (float(InLaneIndex) - 1.0) * _LaneSpacingY;
    }

    private void DoAddSpringPlate(int32 InLaneIndex, float InFrequencyHz, float InDamping)
    {
        auto AnchorPoint = _Origin + FVector(-300.0, DoLaneY(InLaneIndex), _GantryZ);
        auto PlateCenter = AnchorPoint - FVector(0.0, 0.0, _HangLength);

        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, f"Springs.Plate{InLaneIndex}");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, PlateCenter),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(70.0, 70.0, 10.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_LinearDamping(0.05);
        auto Body = utils_jolt_body::Add(Entity, Params);

        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Distance);
        ConstraintParams.Set_WorldAnchorA(PlateCenter);
        ConstraintParams.Set_WorldAnchorB(AnchorPoint);
        ConstraintParams.Set_UseSpring(ECk_EnableDisable::Enable);
        ConstraintParams.Set_SpringFrequencyOrStiffness(InFrequencyHz);
        ConstraintParams.Set_SpringDamping(InDamping);
        utils_jolt_constraint::Create(Body, ConstraintParams);

        FCk_Handle Generic = Body;
        _Plates.Add(Generic);
        _SpawnedRoots.Add(Generic);
    }

    private void DoAddBungeeBall()
    {
        auto AnchorPoint = _Origin + FVector(-600.0, 0.0, _GantryZ + 150.0);
        auto BallCenter = AnchorPoint - FVector(0.0, 0.0, 120.0);

        DoAddStaticBox(AnchorPoint + FVector(0.0, 0.0, 20.0), FVector(25.0, 25.0, 8.0), n"Springs.BungeeMount");

        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, n"Springs.BungeeBall");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, BallCenter),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(35.0);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.5);
        Params.Set_Restitution(0.4);
        auto Body = utils_jolt_body::Add(Entity, Params);

        auto ConstraintParams = FCk_Fragment_JoltConstraint_ParamsData(ECk_JoltConstraint_Type::Distance);
        ConstraintParams.Set_WorldAnchorA(BallCenter);
        ConstraintParams.Set_WorldAnchorB(AnchorPoint);
        ConstraintParams.Set_UseSpring(ECk_EnableDisable::Enable);
        ConstraintParams.Set_SpringFrequencyOrStiffness(0.8);
        ConstraintParams.Set_SpringDamping(0.1);
        utils_jolt_constraint::Create(Body, ConstraintParams);

        FCk_Handle Generic = Body;
        _Plates.Add(Generic);          // poke index 3
        _SpawnedRoots.Add(Generic);
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

    // ---- Control panel ------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("SPRINGS"));
        Rows.Add(CkGym_Control::Action(EKeys::B,     "B", "Poke everything"));
        Rows.Add(CkGym_Control::Action(EKeys::One,   "1", "Poke the 1 Hz floppy plate"));
        Rows.Add(CkGym_Control::Action(EKeys::Two,   "2", "Poke the 3 Hz medium plate"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "Poke the 8 Hz stiff plate"));
        Rows.Add(CkGym_Control::Action(EKeys::Four,  "4", "Poke the bungee ball"));
        Rows.Add(CkGym_Control::Action(EKeys::R,     "R", "Reset - rebuild the rig"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J,     "J", "Jolt debug draw", _JoltDrawEnabled));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        { DoPoke(-1); }
        else if (InRowIndex >= 2 && InRowIndex <= 5)
        { DoPoke(InRowIndex - 2); }
        else if (InRowIndex == 6)
        { DoReset(); }
        else if (InRowIndex == 7)
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

    // InLaneIndex 0/1/2 pokes one plate, 3 the bungee ball; anything else pokes everything.
    private void DoPoke(int32 InLaneIndex)
    {
        for (int32 i = 0; i < _Plates.Num(); i++)
        {
            if (InLaneIndex >= 0 && i != InLaneIndex)
            { continue; }

            auto Body = utils_jolt_body::DoCastChecked(_Plates[i]);
            // FromShape masses are ~e8 units at these dimensions - impulses must scale to match.
            utils_jolt_body::Request_AddImpulse(Body, FCk_Request_JoltBody_AddImpulse(FVector(0.0, 0.0, -100000000000.0)));
        }

        ck::Trace("JoltSpringsGym: poked");
    }

    private void DoReset()
    {
        for (auto Root : _SpawnedRoots)
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
        _SpawnedRoots.Empty();
        _Plates.Empty();

        DoBuildContent();
        ck::Trace("JoltSpringsGym: reset");
    }
}
