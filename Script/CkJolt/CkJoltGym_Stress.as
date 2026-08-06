// Language=angelscript

//============================================================================
// CK JOLT GYM — STRESS (landscape ball rain)
//
// Drops CVar-driven waves of Dynamic Jolt spheres onto the authored landscape
// (Ck.Gym.AuthorJoltStaticBakeContent) and keeps adding more — a load harness
// for the heightfield + dynamic-body pipeline. Watch with
// ck.Jolt.DebugDraw.Enabled 1 and measure with `stat CkJolt` / the CK Jolt
// Physics Debugger tab.
//
//   CVars (registered from C++ at module load — settable any time; see
//   CkJoltStressGym_Utils.cpp):
//     ck.JoltStressGym.InitialBalls        (50)   balls at gym start
//     ck.JoltStressGym.BallsPerWave        (10)   read live each wave
//     ck.JoltStressGym.WaveIntervalSeconds (10)   read at gym start
//     ck.JoltStressGym.MaxBalls            (2000) hard cap, read live
//   Exec:
//     Ck_GymJoltStress_Drop [N]   burst-drop N balls now (default: BallsPerWave)
//     Ck_GymJoltStress_Reset      destroy all balls + re-drop the initial wave
//
// The drop zone derives from the FOUND landscape's bounds (20% inset). With no
// landscape in the level a static fallback floor is spawned so the gym still
// functions — but the heightfield is the real target: author it first.
//
// Balls that roll off the landscape are reaped once they fall well below it
// (a fallen ball never sleeps — it would pollute the stress numbers forever).
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

    private TArray<FCk_Handle> _Balls;
    private int32 _TotalSpawned = 0;
    private bool _CapReported = false;

    // Drop zone (resolved from the landscape's bounds — or the fallback floor — at gym start).
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
        Description.Add(FText::FromString("CVar-driven Dynamic spheres rain onto the authored landscape heightfield. Set ck.Jolt.DebugDraw.Enabled 1 to see them; stat CkJolt to measure."));
        Description.Add(FText::FromString("ck.JoltStressGym.InitialBalls (50) | .BallsPerWave (10) | .WaveIntervalSeconds (10) | .MaxBalls (2000)"));
        Description.Add(FText::FromString("Ck_GymJoltStress_Drop [N]\nCk_GymJoltStress_Reset"));
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

        auto InitialCount = UCk_Utils_JoltStressGym_UE::Get_InitialBalls();
        auto PerWave = UCk_Utils_JoltStressGym_UE::Get_BallsPerWave();
        auto Interval = UCk_Utils_JoltStressGym_UE::Get_WaveIntervalSeconds();
        auto Cap = UCk_Utils_JoltStressGym_UE::Get_MaxBalls();
        DoDropBalls(InitialCount);
        ck::Trace(f"JoltStressGym: started — {InitialCount} initial balls, +{PerWave} every {Interval}s, cap {Cap}");

        // Repeating wave timer. The interval is read ONCE here — change the CVar, then
        // Ck_Gym_Restart to apply it.
        auto Params = FCk_Timer_Spec(FCk_Time(Interval));
        Params.Set_StartingState(ECk_Timer_State::Running)
              .Set_Behavior(ECk_Timer_Behavior::ResetOnDone);
        auto Timer = utils_timer::Add(_GymEntity, Params);
        Timer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnWave"));

        // One-frame settle: retry the teleport in case the pawn wasn't possessed yet.
        auto SettleParams = FCk_Timer_Spec(FCk_Time(0.05));
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
        DoDropBalls(UCk_Utils_JoltStressGym_UE::Get_BallsPerWave());
    }

    // The station is pinned far from the level's PlayerStart — without this the player spawns
    // ~20k units from the gym. Traced so a stranded player is diagnosable from the log.
    private void DoBringPlayerToStation()
    {
        auto ViewPawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(ViewPawn))
        {
            ck::Trace("JoltStressGym: no controlled pawn yet — teleport to the pinned station skipped");
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

        // No landscape — a fallback floor keeps the gym functional (balls would otherwise fall
        // forever). The heightfield is the real stress target: author it.
        ck::Trace("JoltStressGym: NO landscape — run Ck.Gym.AuthorJoltStaticBakeContent in the editor (TestGyms level, then save). Using a fallback static floor");
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
        auto MaxBalls = UCk_Utils_JoltStressGym_UE::Get_MaxBalls();
        auto Budget = Math::Min(InCount, MaxBalls - _Balls.Num());
        if (Budget <= 0)
        {
            if (!_CapReported && _Balls.Num() >= MaxBalls)
            {
                _CapReported = true;
                ck::Trace(f"JoltStressGym: cap reached ({MaxBalls} live balls) — raise ck.JoltStressGym.MaxBalls to go higher");
            }
            return;
        }
        _CapReported = false;

        auto Width = _DropMax.X - _DropMin.X;
        auto Depth = _DropMax.Y - _DropMin.Y;
        auto CellsPerSide = 24;   // 7/11 strides below are co-prime with 24 -> even coverage

        for (int32 i = 0; i < Budget; i++)
        {
            // Deterministic scatter — no RNG dependency; the Z stagger separates same-cell
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

    // A ball that rolls off the landscape falls forever and never sleeps — reap it once it's
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
    // Console commands
    // ------------------------------------------------------------------------------------------
    UFUNCTION(Exec, DisplayName="Jolt Stress - Drop Balls")
    void Ck_GymJoltStress_Drop(int32 InCount = -1)
    {
        auto Count = InCount;
        if (Count <= 0)
        { Count = UCk_Utils_JoltStressGym_UE::Get_BallsPerWave(); }

        DoDropBalls(Count);
    }

    UFUNCTION(Exec, DisplayName="Jolt Stress - Reset")
    void Ck_GymJoltStress_Reset()
    {
        for (auto Ball : _Balls)
        {
            utils_entity_lifetime::Request_DestroyEntity(Ball);
        }
        _Balls.Empty();
        _TotalSpawned = 0;
        _CapReported = false;

        DoDropBalls(UCk_Utils_JoltStressGym_UE::Get_InitialBalls());
        ck::Trace("JoltStressGym: reset — all balls destroyed, initial wave re-dropped");
    }
}
