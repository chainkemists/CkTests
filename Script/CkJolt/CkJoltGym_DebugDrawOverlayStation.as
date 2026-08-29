// Language=angelscript

//============================================================================
// CK JOLT GYM - DEBUG DRAW OVERLAY
//
// One body of every JoltBody motion type, built so the CkJolt debug-draw CVars
// have something to draw:
//   Static   - floor.
//   Kinematic- a box sliding back and forth (Request_SetLocation each tick;
//              KinematicPush is what drives the physics body to match).
//   Dynamic  - a "sleeper" box dropped once and left alone (settles -> sleeps).
//   Dynamic  - a "bouncer" sphere periodically re-impulsed so it never sleeps,
//              giving a permanent awake/asleep color contrast.
//
// Two control-panel toggles drive the debug draw:
//   [J] - draw ALL bodies, colored by motion type.
//   [K] - sleep coloring: awake dynamics = yellow, asleep = red.
//
// Content is built in world -X from the station anchor (house rule: stations
// face -X).
//============================================================================

class ACk_JoltGym_DebugDrawOverlay_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_DebugDrawOverlay_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_DebugDrawOverlay_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;

    private FCk_Handle_Transform _KinematicTransform;
    private float _KinematicBaseLocalX = -300.0;
    private float _KinematicRangeX = 200.0;
    private float _KinematicElapsed = 0.0;
    private float _KinematicPeriod = 4.0;

    private FCk_Handle_JoltBody _SleeperBody;

    private FCk_Handle_JoltBody _BouncerBody;
    private FVector _BouncerStart = FVector::ZeroVector;
    private float _BouncerElapsed = 0.0;
    private float _BouncerPeriod = 1.5;

    // Mirrors of ck.Jolt.DebugDraw.Enabled / .SleepColoring - mirrored in members because the
    // module exposes no AS readback for them; EndPlay writes each back to its default (off) only
    // if this gym touched it.
    private bool _JoltDrawEnabled = false;
    private bool _JoltDrawTouched = false;
    private bool _JoltSleepColoringEnabled = false;
    private bool _JoltSleepColoringTouched = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.DebugDrawOverlay");
        Station.Title = FText::FromString("JOLT DEBUG DRAW OVERLAY");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("[J] draws every Jolt body, colored by motion type."));
        Description.Add(FText::FromString("[K] adds sleep coloring:\nAwake=yellow, Asleep=red."));
        Description.Add(FText::FromString("Static floor, Kinematic slider,\nsleeping box, bouncing sphere."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.DebugDrawOverlay", ECk_GymStation_Anchor::FootprintCenter);

        DoAddStaticFloor();
        DoAddKinematicSlider();
        DoAddSleeperBox();
        DoAddBouncerSphere();

        utils_timer::Create_Tick(ck::ToEntity(this), FCk_Delegate_Timer(this, n"OnTick"));

        ck::Trace("JoltDebugDrawOverlayGym: started - toggle [J] to see every motion type");
    }

    private void DoAddStaticFloor()
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"DebugDrawOverlay.Floor");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + FVector(-250.0, 0.0, -25.0)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(450.0, 300.0, 25.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);
    }

    private void DoAddKinematicSlider()
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"DebugDrawOverlay.KinematicSlider");
        _KinematicTransform = utils_transform::Add(Entity,
            FTransform(FRotator::ZeroRotator, _Origin + FVector(_KinematicBaseLocalX, -200.0, 40.0)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(60.0, 40.0, 40.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Kinematic);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(1.0);
        utils_jolt_body::Add(Entity, Params);
    }

    private void DoAddSleeperBox()
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"DebugDrawOverlay.Sleeper");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + FVector(-250.0, 0.0, 150.0)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(45.0, 45.0, 45.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.5);
        Params.Set_Restitution(0.0);
        _SleeperBody = utils_jolt_body::Add(Entity, Params);

        utils_jolt_body::BindTo_OnJoltBodySleepStateChanged(_SleeperBody,
            FCk_Delegate_JoltBody_OnSleepStateChanged(this, n"OnSleeperSleepStateChanged"));
    }

    private void DoAddBouncerSphere()
    {
        _BouncerStart = _Origin + FVector(-250.0, 200.0, 300.0);

        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"DebugDrawOverlay.Bouncer");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _BouncerStart), ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(35.0);
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.3);
        Params.Set_Restitution(0.6);
        _BouncerBody = utils_jolt_body::Add(Entity, Params);
    }

    UFUNCTION()
    private void OnSleeperSleepStateChanged(FCk_Handle_JoltBody InHandle, ECk_Jolt_SleepState InSleepState)
    {
        ck::Trace(f"JoltDebugDrawOverlayGym: sleeper box -> {InSleepState}");
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Delta = float(InDeltaT.Get_Seconds());

        // ---- Kinematic slider: ping-pong along local X via Request_SetLocation ----------------
        _KinematicElapsed += Delta;
        if (_KinematicElapsed >= _KinematicPeriod)
        {
            _KinematicElapsed = 0.0;
        }

        auto HalfPeriod = _KinematicPeriod * 0.5;
        auto IntoHalf = (_KinematicElapsed < HalfPeriod) ? _KinematicElapsed : (_KinematicPeriod - _KinematicElapsed);
        auto SlideFraction = IntoHalf / HalfPeriod;   // divides by a fixed constant, never by delta-time
        auto SlideX = _KinematicBaseLocalX + SlideFraction * _KinematicRangeX;
        utils_transform::Request_SetLocation(_KinematicTransform, _Origin + FVector(SlideX, -200.0, 40.0));

        // ---- Bouncer: periodic upward impulse so it never settles into Asleep -----------------
        _BouncerElapsed += Delta;
        if (_BouncerElapsed >= _BouncerPeriod)
        {
            utils_jolt_body::Request_AddImpulse(_BouncerBody, FCk_Request_JoltBody_AddImpulse(FVector(0.0, 0.0, 6000.0)));
            _BouncerElapsed = 0.0;
        }
    }

    // ---- Control panel ------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("DEBUG DRAW OVERLAY"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Wake the sleeper box"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J, "J", "Jolt debug draw", _JoltDrawEnabled));
        Rows.Add(CkGym_Control::Toggle(EKeys::K, "K", "Sleep coloring", _JoltSleepColoringEnabled));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        { DoWakeSleeper(); }
        else if (InRowIndex == 2)
        {
            _JoltDrawEnabled = !_JoltDrawEnabled;
            _JoltDrawTouched = true;
            System::ExecuteConsoleCommand(f"ck.Jolt.DebugDraw.Enabled {(_JoltDrawEnabled ? 1 : 0)}");
        }
        else if (InRowIndex == 3)
        {
            _JoltSleepColoringEnabled = !_JoltSleepColoringEnabled;
            _JoltSleepColoringTouched = true;
            System::ExecuteConsoleCommand(f"ck.Jolt.DebugDraw.SleepColoring {(_JoltSleepColoringEnabled ? 1 : 0)}");
        }
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason EndPlayReason)
    {
        // No AS readback exists for either cvar, so a faithful capture/restore is impossible - put
        // each back to its module default only if this gym flipped it, so a value the USER set
        // outside the gym is never stomped by a gym they never touched the toggle in.
        if (_JoltDrawTouched)
        { System::ExecuteConsoleCommand("ck.Jolt.DebugDraw.Enabled 0"); }

        if (_JoltSleepColoringTouched)
        { System::ExecuteConsoleCommand("ck.Jolt.DebugDraw.SleepColoring 0"); }
    }

    private void DoWakeSleeper()
    {
        utils_jolt_body::Request_SetSleepState(_SleeperBody, FCk_Request_JoltBody_SetSleepState(ECk_Jolt_SleepState::Awake));
        utils_jolt_body::Request_AddImpulse(_SleeperBody, FCk_Request_JoltBody_AddImpulse(FVector(0.0, 0.0, 3500.0)));
        ck::Trace("JoltDebugDrawOverlayGym: sleeper nudged awake - watch it settle and sleep again");
    }
}
