// Language=angelscript

//============================================================================
// CK JOLT GYM - SLEEP / WAKE
//
// A 3x3 grid of Dynamic boxes dropped onto a Static floor. Each box is bound
// to OnJoltBodySleepStateChanged - watch the log as every box settles and
// falls Asleep, then fire the wake trigger to snap them all back Awake (they
// will re-settle and sleep again on their own, so the edge repeats).
//
// With the [J] and [K] toggles on, the grid visibly flips yellow (awake) ->
// red (asleep).
//
// Content is built in world -X from the station anchor (house rule: stations
// face -X).
//============================================================================

class ACk_JoltGym_SleepWake_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_SleepWake_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_SleepWake_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;
    private TArray<FCk_Handle_JoltBody> _GridBodies;
    private int32 _GridSize = 3;
    private float _GridSpacing = 130.0;
    private float _DropHeight = 260.0;

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
        Station.Tags.Add(n"Gym.Jolt.SleepWake");
        Station.Title = FText::FromString("JOLT SLEEP / WAKE");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("3x3 grid settles then sleeps.\nWatch the log for OnJoltBodySleepStateChanged."));
        Description.Add(FText::FromString("Every control is on the panel:\n[B] wake all · [R] reset · [J]+[K] draw with sleep coloring."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.SleepWake", ECk_GymStation_Anchor::FootprintCenter);

        DoAddFloor();
        DoDropGrid();

        ck::Trace("JoltSleepWakeGym: started - 9 boxes dropped, watch them settle and sleep");
    }

    private void DoAddFloor()
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"SleepWake.Floor");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + FVector(-150.0, 0.0, -25.0)),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(320.0, 320.0, 25.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);
    }

    private void DoDropGrid()
    {
        auto HalfGrid = (float(_GridSize) - 1.0) * 0.5;

        for (int32 Row = 0; Row < _GridSize; Row++)
        {
            for (int32 Col = 0; Col < _GridSize; Col++)
            {
                auto LocalX = -150.0 + (float(Row) - HalfGrid) * _GridSpacing;
                auto LocalY = (float(Col) - HalfGrid) * _GridSpacing;
                DoDropBoxAt(FVector(LocalX, LocalY, _DropHeight));
            }
        }
    }

    private void DoDropBoxAt(FVector InLocalOffset)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"SleepWake.Box");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + InLocalOffset),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(40.0, 40.0, 40.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.5);
        Params.Set_Restitution(0.0);
        auto Body = utils_jolt_body::Add(Entity, Params);

        utils_jolt_body::BindTo_OnJoltBodySleepStateChanged(Body,
            FCk_Delegate_JoltBody_OnSleepStateChanged(this, n"OnGridBodySleepStateChanged"));

        _GridBodies.Add(Body);
    }

    UFUNCTION()
    private void OnGridBodySleepStateChanged(FCk_Handle_JoltBody InHandle, ECk_Jolt_SleepState InSleepState)
    {
        auto Index = -1;
        for (int32 i = 0; i < _GridBodies.Num(); i++)
        {
            if (_GridBodies[i] == InHandle)
            {
                Index = i;
                break;
            }
        }
        ck::Trace(f"JoltSleepWakeGym: box [{Index}] -> {InSleepState}");
    }

    // ---- Control panel ------------------------------------------------------------------------

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("SLEEP / WAKE"));
        Rows.Add(CkGym_Control::Action(EKeys::B, "B", "Wake every box"));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset - re-drop the grid"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J, "J", "Jolt debug draw", _JoltDrawEnabled));
        Rows.Add(CkGym_Control::Toggle(EKeys::K, "K", "Sleep coloring", _JoltSleepColoringEnabled));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 1)
        { DoWakeAll(); }
        else if (InRowIndex == 2)
        { DoReset(); }
        else if (InRowIndex == 3)
        {
            _JoltDrawEnabled = !_JoltDrawEnabled;
            _JoltDrawTouched = true;
            System::ExecuteConsoleCommand(f"ck.Jolt.DebugDraw.Enabled {(_JoltDrawEnabled ? 1 : 0)}");
        }
        else if (InRowIndex == 4)
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

    private void DoWakeAll()
    {
        for (auto Body : _GridBodies)
        {
            utils_jolt_body::Request_SetSleepState(Body, FCk_Request_JoltBody_SetSleepState(ECk_Jolt_SleepState::Awake));
            // Tiny upward nudge so a woken box visibly resettles instead of instantly re-sleeping.
            utils_jolt_body::Request_AddImpulse(Body, FCk_Request_JoltBody_AddImpulse(FVector(0.0, 0.0, 4000.0)));
        }
        ck::Trace("JoltSleepWakeGym: wake-all fired - every box nudged awake");
    }

    private void DoReset()
    {
        for (auto Body : _GridBodies)
        {
            utils_entity_lifetime::Request_DestroyEntity(Body);
        }
        _GridBodies.Empty();

        DoDropGrid();
        ck::Trace("JoltSleepWakeGym: reset - grid cleared and re-dropped");
    }
}
