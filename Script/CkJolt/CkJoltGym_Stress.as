// Language=angelscript

//============================================================================
// CK JOLT GYM - STRESS (landscape ball rain)
//
// Drops waves of Dynamic Jolt spheres onto the authored landscape
// (Ck.Gym.AuthorJoltStaticBakeContent) and keeps adding more - a load harness
// for the heightfield + dynamic-body pipeline. Every knob is a control-panel
// row (preset rings for the counts, actions for drop/reset, a toggle for the
// Jolt debug draw); measure with `stat CkJolt` / the CK Jolt Physics Debugger.
//
// The drop zone derives from the FOUND landscape's bounds (20% inset). With no
// landscape in the level a static fallback floor is spawned so the gym still
// functions - but the heightfield is the real target: author it first.
//
// Balls that roll off the landscape are reaped once they fall well below it
// (a fallen ball never sleeps - it would pollute the stress numbers forever).
//
// Station pinned at the Y=20000 band facing the authored landscape in -X;
// keep in sync with CkGymJoltStaticBakeAuthoring.cpp.
//============================================================================

class ACk_JoltGym_Stress_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_Stress_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_Stress_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;

    // Host entity for the wave/settle timers (mirrors the StaticBake gym's pattern).
    private FCk_Handle _GymEntity;

    // The stress knobs, panel-driven preset rings (the old ck.JoltStressGym.* CVars, deleted).
    private int32 _InitialBalls = 50;
    private int32 _BallsPerWave = 10;
    private float _WaveIntervalSeconds = 10.0;
    private int32 _MaxBalls = 2000;

    private FCk_Handle_Timer _WaveTimer;

    // Mirror of ck.Jolt.DebugDraw.Enabled - mirrored in a member because the module exposes no
    // AS readback for it; EndPlay writes it back to its default (off) only if this gym touched it.
    private bool _JoltDrawEnabled = false;
    private bool _JoltDrawTouched = false;

    private TArray<FCk_Handle> _Balls;
    private int32 _TotalSpawned = 0;
    private bool _CapReported = false;

    // Drop zone (resolved from the landscape's bounds - or the fallback floor - at gym start).
    private FVector _DropMin = FVector::ZeroVector;
    private FVector _DropMax = FVector::ZeroVector;
    private float _DropZ = 0.0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.Stress");
        Station.Title = FText::FromString("JOLT STRESS — BALL RAIN");

        // Pinned facing the authored landscape (see the header comment).
        Station.Transform = FTransform(FRotator(0.0, 180.0, 0.0), FVector(-1800.0, 20000.0, 0.0), FVector::OneVector);

        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Dynamic spheres rain onto the authored landscape heightfield in timed waves. All knobs are on the control panel; toggle [J] to see the bodies, stat CkJolt to measure."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.Stress", ECk_GymStation_Anchor::FootprintCenter);

        DoBringPlayerToStation();

        _GymEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        _GymEntity.Request_OverrideToSelf();
        _GymEntity.Set_DebugName(n"Stress.GymEntity");

        DoResolveDropZone();

        DoDropBalls(_InitialBalls);
        ck::Trace(f"JoltStressGym: started - {_InitialBalls} initial balls, +{_BallsPerWave} every {_WaveIntervalSeconds}s, cap {_MaxBalls}");

        DoArmWaveTimer();

        // One-frame settle: retry the teleport in case the pawn wasn't possessed yet.
        auto SettleParams = FCk_Fragment_Timer_ParamsData(FCk_Time(0.05));
        SettleParams.Set_StartingState(ECk_Timer_State::Running)
                    .Set_Behavior(ECk_Timer_Behavior::StopOnDone);
        auto SettleTimer = utils_timer::Add(_GymEntity, SettleParams);
        SettleTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnStartSettle"));
    }

    UFUNCTION()
    private void OnStartSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DoBringPlayerToStation();
    }

    UFUNCTION()
    private void OnWave(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        DoReapFallenBalls();
        DoDropBalls(_BallsPerWave);
    }

    // (Re)creates the repeating wave timer; cycling the interval row re-arms it immediately, so
    // the value is no longer restart-applied.
    private void DoArmWaveTimer()
    {
        if (ck::IsValid(_WaveTimer))
        {
            FCk_Handle Generic = _WaveTimer;
            utils_entity_lifetime::Request_DestroyEntity(Generic);
        }

        auto Params = FCk_Fragment_Timer_ParamsData(FCk_Time(_WaveIntervalSeconds));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        _WaveTimer = utils_timer::Add(_GymEntity, Params);
        _WaveTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnWave"));
    }

    // The station is pinned far from the level's PlayerStart - without this the player spawns
    // ~20k units from the gym. Traced so a stranded player is diagnosable from the log.
    private void DoBringPlayerToStation()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        {
            ck::Trace("JoltStressGym: no controlled pawn yet - teleport to the pinned station skipped");
            return;
        }

        ViewPawn.SetActorLocation(_Origin + FVector(900.0, 0.0, 600.0));
        SetControlRotation(FRotator(-20.0, 180.0, 0.0));
    }

    // ------------------------------------------------------------------------------------------
    // Drop zone
    // ------------------------------------------------------------------------------------------
    private void DoResolveDropZone()
    {
        auto Landscapes = TArray<ALandscapeProxy>();
        GetAllActorsOfClass(ALandscapeProxy, Landscapes);

        if (Landscapes.Num() > 0 && ck::IsValid(Landscapes[0]))
        {
            auto Landscape = Landscapes[0];

            FVector BoundsOrigin;
            FVector BoundsExtent;
            Landscape.GetActorBounds(false, BoundsOrigin, BoundsExtent);

            // 20% inset keeps every ball's first bounce on the heightfield.
            auto Inset = FVector(BoundsExtent.X * 0.8, BoundsExtent.Y * 0.8, 0.0);
            _DropMin = BoundsOrigin - Inset;
            _DropMax = BoundsOrigin + Inset;
            _DropZ = BoundsOrigin.Z + BoundsExtent.Z + 800.0;
            ck::Trace(f"JoltStressGym: dropping over landscape {Landscape.GetName()}");
            return;
        }

        // No landscape - a fallback floor keeps the gym functional (balls would otherwise fall
        // forever). The heightfield is the real stress target: author it.
        ck::Trace("JoltStressGym: NO landscape - run Ck.Gym.AuthorJoltStaticBakeContent in the editor (TestGyms level, then save). Using a fallback static floor");
        auto FloorCenter = _Origin + FVector(-2500.0, 0.0, 0.0);
        DoAddStaticFloor(FloorCenter);
        _DropMin = FloorCenter - FVector(1600.0, 1600.0, 0.0);
        _DropMax = FloorCenter + FVector(1600.0, 1600.0, 0.0);
        _DropZ = FloorCenter.Z + 1200.0;
    }

    private void DoAddStaticFloor(FVector InCenter)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"Stress.FallbackFloor");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, InCenter),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(2000.0, 2000.0, 25.0));
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);
    }

    // ------------------------------------------------------------------------------------------
    // Ball spawning
    // ------------------------------------------------------------------------------------------
    private void DoDropBalls(int32 InCount)
    {
        auto Budget = Math::Min(InCount, _MaxBalls - _Balls.Num());
        if (Budget <= 0)
        {
            if (!_CapReported && _Balls.Num() >= _MaxBalls)
            {
                _CapReported = true;
                ck::Trace(f"JoltStressGym: cap reached ({_MaxBalls} live balls) - cycle the Max balls row to go higher");
            }
            return;
        }
        _CapReported = false;

        auto Width = _DropMax.X - _DropMin.X;
        auto Depth = _DropMax.Y - _DropMin.Y;
        auto CellsPerSide = 24;   // 7/11 strides below are co-prime with 24 -> even coverage

        for (int32 i = 0; i < Budget; i++)
        {
            // Deterministic scatter - no RNG dependency; the Z stagger separates same-cell
            // revisits and the physics does the rest.
            auto Index = _TotalSpawned;
            auto CellX = (Index * 7) % CellsPerSide;
            auto CellY = (Index * 11) % CellsPerSide;
            auto X = _DropMin.X + (float(CellX) + 0.5) * (Width / float(CellsPerSide));
            auto Y = _DropMin.Y + (float(CellY) + 0.5) * (Depth / float(CellsPerSide));
            auto Z = _DropZ + float(Index % 7) * 90.0;
            DoSpawnBall(FVector(X, Y, Z), Index);
            _TotalSpawned += 1;
        }

        ck::Trace(f"JoltStressGym: +{Budget} balls -> {_Balls.Num()} live ({_TotalSpawned} spawned total)");
    }

    private void DoSpawnBall(FVector InLocation, int32 InIndex)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(Entity, f"Stress.Ball{InIndex}");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, InLocation),
            ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        Shape.Set_Radius(20.0 + float(InIndex % 6) * 5.0);   // 20..45uu variety
        auto Params = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.5);
        Params.Set_Restitution(0.3);
        auto Body = utils_jolt_body::Add(Entity, Params);

        FCk_Handle Generic = Body;
        _Balls.Add(Generic);
    }

    // A ball that rolls off the landscape falls forever and never sleeps - reap it once it's
    // well below the drop zone so the live count stays an honest stress number.
    private void DoReapFallenBalls()
    {
        auto KillZ = _DropZ - 6000.0;
        auto Survivors = TArray<FCk_Handle>();
        auto Reaped = 0;

        for (auto Ball : _Balls)
        {
            if (ck::Is_NOT_Valid(Ball))
            { continue; }

            auto BallLocation = utils_transform::Get_EntityCurrentLocation(utils_transform::DoCastChecked(Ball));
            if (BallLocation.Z < KillZ)
            {
                utils_entity_lifetime::Request_DestroyEntity(Ball);
                Reaped += 1;
                continue;
            }

            Survivors.Add(Ball);
        }

        if (Reaped > 0)
        {
            _Balls = Survivors;
            ck::Trace(f"JoltStressGym: reaped {Reaped} fallen balls");
        }
    }

    // ------------------------------------------------------------------------------------------
    // Control panel
    // ------------------------------------------------------------------------------------------
    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("BALL RAIN"));
        Rows.Add(CkGym_Control::Status("Live balls", f"{_Balls.Num()} - {_TotalSpawned} spawned"));
        Rows.Add(CkGym_Control::Cycle(EKeys::One,   "1", "Initial balls (on reset)", f"{_InitialBalls}"));
        Rows.Add(CkGym_Control::Cycle(EKeys::Two,   "2", "Balls per wave",           f"{_BallsPerWave}"));
        Rows.Add(CkGym_Control::Cycle(EKeys::Three, "3", "Wave interval",            f"{_WaveIntervalSeconds}s"));
        Rows.Add(CkGym_Control::Cycle(EKeys::Four,  "4", "Max balls",                f"{_MaxBalls}"));
        Rows.Add(CkGym_Control::Action(EKeys::B,    "B", "Drop a wave now"));
        Rows.Add(CkGym_Control::Action(EKeys::R,    "R", "Reset - re-drop initial"));
        Rows.Add(CkGym_Control::Toggle(EKeys::J,    "J", "Jolt debug draw", _JoltDrawEnabled));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 2)
        { _InitialBalls = _InitialBalls == 25 ? 50 : _InitialBalls == 50 ? 100 : _InitialBalls == 100 ? 200 : 25; }
        else if (InRowIndex == 3)
        { _BallsPerWave = _BallsPerWave == 5 ? 10 : _BallsPerWave == 10 ? 25 : _BallsPerWave == 25 ? 50 : 5; }
        else if (InRowIndex == 4)
        {
            _WaveIntervalSeconds = _WaveIntervalSeconds == 2.0 ? 5.0 : _WaveIntervalSeconds == 5.0 ? 10.0 : _WaveIntervalSeconds == 10.0 ? 20.0 : 2.0;
            DoArmWaveTimer();
        }
        else if (InRowIndex == 5)
        { _MaxBalls = _MaxBalls == 500 ? 1000 : _MaxBalls == 1000 ? 2000 : 500; }
        else if (InRowIndex == 6)
        { DoDropBalls(_BallsPerWave); }
        else if (InRowIndex == 7)
        { DoReset(); }
        else if (InRowIndex == 8)
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

    private void DoReset()
    {
        for (auto Ball : _Balls)
        {
            utils_entity_lifetime::Request_DestroyEntity(Ball);
        }
        _Balls.Empty();
        _TotalSpawned = 0;
        _CapReported = false;

        DoDropBalls(_InitialBalls);
        ck::Trace("JoltStressGym: reset - all balls destroyed, initial wave re-dropped");
    }
}
