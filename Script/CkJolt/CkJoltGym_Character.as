// Language=angelscript

//============================================================================
// CK JOLT GYM — CHARACTER
//
// Three scripted (non-player-input) JoltCharacter lanes, each looping forever
// so the gym is alive the moment you walk in:
//   Lane 1 (Patrol + Jump) — walks back and forth, jumps every ~2.5s.
//   Lane 2 (Slope Limit)   — approaches a 60 deg ramp (default character slope
//                             limit is 50 deg) and is blocked/slides instead of
//                             climbing it, then retreats and tries again.
//   Lane 3 (Push Policy)   — PushAndBePushed character walks into a light
//                             Dynamic box and shoves it; both reset and repeat.
//                             Ck_GymJoltCharacter_CyclePushPolicy respawns this
//                             lane's character with the next PushPolicy value
//                             so the difference in box displacement is visible.
//
// Content is built in world -X from the station anchor (house rule: stations
// face -X) — every lane's "forward" is -X.
//============================================================================

class ACk_JoltGym_Character_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_Character_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_Character_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;

    private float _Lane1Y = -350.0;
    private float _Lane2Y = 0.0;
    private float _Lane3Y = 350.0;

    private float _WalkSpeed = 150.0;
    private float _JumpVelocity = 400.0;

    // ---- Lane 1: patrol + jump -------------------------------------------------------------
    private FCk_Handle_JoltCharacter _Lane1Char;
    private float _Lane1PhaseElapsed = 0.0;
    private float _Lane1PhasePeriod = 6.0;
    private float _Lane1JumpElapsed = 0.0;
    private float _Lane1JumpPeriod = 2.5;
    private float _Lane1LastDir = -1.0;

    // ---- Lane 2: slope limit ------------------------------------------------------------------
    private FCk_Handle_JoltCharacter _Lane2Char;
    private float _Lane2PhaseElapsed = 0.0;
    private float _Lane2PhasePeriod = 5.0;
    private float _Lane2LastDir = -1.0;

    // ---- Lane 3: push policy --------------------------------------------------------------
    private FCk_Handle_JoltCharacter _Lane3Char;
    private FCk_Handle_JoltBody _Lane3Box;
    private FVector _Lane3CharStart = FVector::ZeroVector;
    private FVector _Lane3BoxStart = FVector::ZeroVector;
    private float _Lane3PhaseElapsed = 0.0;
    private float _Lane3PhasePeriod = 3.5;
    private int32 _Lane3PolicyIndex = 0;   // 0=PushAndBePushed, 1=PushOnly, 2=BePushedOnly, 3=Neither

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.Character");
        Station.Title = FText::FromString("JOLT CHARACTER");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("Lane 1: patrol walk + jump.\nLane 2: 60 deg ramp exceeds the 50 deg slope limit."));
        Description.Add(FText::FromString("Lane 3: PushAndBePushed shoves a light box.\nCk_GymJoltCharacter_CyclePushPolicy to compare."));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.Character", ECk_GymStation_Anchor::FootprintCenter);

        DoStartLane1();
        DoStartLane2();
        DoStartLane3();

        utils_timer::Create_Tick(ck::ToEntity(this), FCk_Delegate_Timer(this, n"OnTick"));

        ck::Trace("JoltCharacterGym: started — patrol/jump, slope-limit, and push-policy lanes running");
    }

    // ---- Shared helpers ---------------------------------------------------------------------

    private void DoAddFloor(FVector InLocalOffset, FVector InHalfExtents)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"Character.Floor");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + InLocalOffset), ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(InHalfExtents);
        auto Params = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(Entity, Params);
    }

    private FCk_Handle_JoltCharacter DoAddCharacter(FVector InLocalOffset, ECk_JoltCharacter_PushPolicy InPolicy, FName InDebugName)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(InDebugName);
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, _Origin + InLocalOffset), ECk_Replication::DoesNotReplicate);

        auto Params = FCk_JoltCharacter_Spec(40.0, 60.0);
        Params.Set_PushPolicy(InPolicy);
        Params.Set_MaxStrengthNewtons(200.0);
        return utils_jolt_character::Add(Entity, Params);
    }

    // ---- Lane 1: patrol + jump ----------------------------------------------------------------

    private void DoStartLane1()
    {
        DoAddFloor(FVector(-300.0, _Lane1Y, -25.0), FVector(500.0, 140.0, 25.0));
        _Lane1Char = DoAddCharacter(FVector(-100.0, _Lane1Y, 125.0), ECk_JoltCharacter_PushPolicy::PushAndBePushed, n"Character.Lane1Char");
        utils_jolt_character::Request_Move(_Lane1Char, FCk_Request_JoltCharacter_Move(FVector(-_WalkSpeed, 0.0, 0.0)));
    }

    private void DoTickLane1(float InDeltaSeconds)
    {
        _Lane1PhaseElapsed += InDeltaSeconds;
        if (_Lane1PhaseElapsed >= _Lane1PhasePeriod)
        {
            _Lane1PhaseElapsed = 0.0;
        }

        // Walk -X for the first half of the cycle, +X for the second half.
        auto DesiredDir = (_Lane1PhaseElapsed < _Lane1PhasePeriod * 0.5) ? -1.0 : 1.0;
        if (DesiredDir != _Lane1LastDir)
        {
            utils_jolt_character::Request_Move(_Lane1Char, FCk_Request_JoltCharacter_Move(FVector(DesiredDir * _WalkSpeed, 0.0, 0.0)));
            _Lane1LastDir = DesiredDir;
        }

        _Lane1JumpElapsed += InDeltaSeconds;
        if (_Lane1JumpElapsed >= _Lane1JumpPeriod)
        {
            utils_jolt_character::Request_Jump(_Lane1Char, FCk_Request_JoltCharacter_Jump(_JumpVelocity));
            _Lane1JumpElapsed = 0.0;
        }
    }

    // ---- Lane 2: slope limit ------------------------------------------------------------------

    private void DoStartLane2()
    {
        DoAddFloor(FVector(-100.0, _Lane2Y, -25.0), FVector(300.0, 140.0, 25.0));

        // Ramp pitched 60 deg — steeper than the character's default 50 deg MaxSlopeAngleDegrees,
        // so approach should be blocked/slide instead of climbed.
        auto RampEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        RampEntity.Request_OverrideToSelf();
        RampEntity.Set_DebugName(n"Character.Ramp");
        utils_transform::Add(RampEntity, FTransform(FRotator(60.0, 0.0, 0.0), _Origin + FVector(-430.0, _Lane2Y, 150.0)),
            ECk_Replication::DoesNotReplicate);
        auto RampShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        RampShape.Set_HalfExtents(FVector(300.0, 130.0, 15.0));
        auto RampParams = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        RampParams.Set_ShapeDimensions(RampShape);
        RampParams.Set_MotionType(ECk_MotionType::Static);
        utils_jolt_body::Add(RampEntity, RampParams);

        _Lane2Char = DoAddCharacter(FVector(-150.0, _Lane2Y, 125.0), ECk_JoltCharacter_PushPolicy::Neither, n"Character.Lane2Char");
        utils_jolt_character::Request_Move(_Lane2Char, FCk_Request_JoltCharacter_Move(FVector(-_WalkSpeed * 0.8, 0.0, 0.0)));
    }

    private void DoTickLane2(float InDeltaSeconds)
    {
        _Lane2PhaseElapsed += InDeltaSeconds;
        if (_Lane2PhaseElapsed >= _Lane2PhasePeriod)
        {
            _Lane2PhaseElapsed = 0.0;
        }

        auto DesiredDir = (_Lane2PhaseElapsed < _Lane2PhasePeriod * 0.5) ? -1.0 : 1.0;
        if (DesiredDir != _Lane2LastDir)
        {
            utils_jolt_character::Request_Move(_Lane2Char, FCk_Request_JoltCharacter_Move(FVector(DesiredDir * _WalkSpeed * 0.8, 0.0, 0.0)));
            _Lane2LastDir = DesiredDir;
        }
    }

    // ---- Lane 3: push policy ------------------------------------------------------------------

    private void DoStartLane3()
    {
        DoAddFloor(FVector(-150.0, _Lane3Y, -25.0), FVector(350.0, 140.0, 25.0));

        _Lane3BoxStart = _Origin + FVector(-350.0, _Lane3Y, 75.0);
        _Lane3Box = DoAddLane3Box(_Lane3BoxStart);

        _Lane3CharStart = _Origin + FVector(-150.0, _Lane3Y, 125.0);
        _Lane3Char = DoAddCharacter(FVector(-150.0, _Lane3Y, 125.0), DoPolicyFromIndex(_Lane3PolicyIndex), n"Character.Lane3Char");
        utils_jolt_character::Request_Move(_Lane3Char, FCk_Request_JoltCharacter_Move(FVector(-_WalkSpeed, 0.0, 0.0)));
    }

    private FCk_Handle_JoltBody DoAddLane3Box(FVector InWorldLocation)
    {
        auto Entity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        Entity.Request_OverrideToSelf();
        Entity.Set_DebugName(n"Character.Lane3Box");
        utils_transform::Add(Entity, FTransform(FRotator::ZeroRotator, InWorldLocation), ECk_Replication::DoesNotReplicate);

        auto Shape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Box);
        Shape.Set_HalfExtents(FVector(50.0, 50.0, 50.0));
        auto Params = FCk_JoltBody_Spec(ECk_JoltBody_ShapeSource::ExplicitShape);
        Params.Set_ShapeDimensions(Shape);
        Params.Set_MotionType(ECk_MotionType::Dynamic);
        Params.Set_MassSource(ECk_JoltBody_MassSource::Explicit);
        Params.Set_MassKg(1.0);
        Params.Set_SurfaceSource(ECk_JoltBody_SurfaceSource::Explicit);
        Params.Set_Friction(0.2);
        Params.Set_Restitution(0.0);
        return utils_jolt_body::Add(Entity, Params);
    }

    private ECk_JoltCharacter_PushPolicy DoPolicyFromIndex(int32 InIndex)
    {
        if (InIndex == 0) { return ECk_JoltCharacter_PushPolicy::PushAndBePushed; }
        if (InIndex == 1) { return ECk_JoltCharacter_PushPolicy::PushOnly; }
        if (InIndex == 2) { return ECk_JoltCharacter_PushPolicy::BePushedOnly; }
        return ECk_JoltCharacter_PushPolicy::Neither;
    }

    private void DoTickLane3(float InDeltaSeconds)
    {
        _Lane3PhaseElapsed += InDeltaSeconds;
        if (_Lane3PhaseElapsed >= _Lane3PhasePeriod)
        {
            auto TeleCharRequest = FCk_Request_JoltCharacter_Teleport(_Lane3CharStart);
            utils_jolt_character::Request_Teleport(_Lane3Char, TeleCharRequest);

            auto TeleBoxRequest = FCk_Request_JoltBody_Teleport(_Lane3BoxStart, FRotator::ZeroRotator);
            TeleBoxRequest.Set_VelocityPolicy(ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
            utils_jolt_body::Request_Teleport(_Lane3Box, TeleBoxRequest);

            _Lane3PhaseElapsed = 0.0;
        }
    }

    // ---- Tick + commands ----------------------------------------------------------------------

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Delta = float(InDeltaT.Get_Seconds());
        DoTickLane1(Delta);
        DoTickLane2(Delta);
        DoTickLane3(Delta);
    }

    UFUNCTION(Exec, DisplayName="Jolt Character - Force Jump (Lane 1)")
    void Ck_GymJoltCharacter_Jump()
    {
        utils_jolt_character::Request_Jump(_Lane1Char, FCk_Request_JoltCharacter_Jump(_JumpVelocity));
        _Lane1JumpElapsed = 0.0;
        ck::Trace("JoltCharacterGym: manual jump fired on lane 1");
    }

    UFUNCTION(Exec, DisplayName="Jolt Character - Reset All Lanes")
    void Ck_GymJoltCharacter_ResetAll()
    {
        utils_jolt_character::Request_Teleport(_Lane1Char, FCk_Request_JoltCharacter_Teleport(_Origin + FVector(-100.0, _Lane1Y, 125.0)));
        utils_jolt_character::Request_Teleport(_Lane2Char, FCk_Request_JoltCharacter_Teleport(_Origin + FVector(-150.0, _Lane2Y, 125.0)));

        auto TeleCharRequest = FCk_Request_JoltCharacter_Teleport(_Lane3CharStart);
        utils_jolt_character::Request_Teleport(_Lane3Char, TeleCharRequest);
        auto TeleBoxRequest = FCk_Request_JoltBody_Teleport(_Lane3BoxStart, FRotator::ZeroRotator);
        TeleBoxRequest.Set_VelocityPolicy(ECk_Jolt_TeleportVelocityPolicy::ResetVelocity);
        utils_jolt_body::Request_Teleport(_Lane3Box, TeleBoxRequest);

        _Lane1PhaseElapsed = 0.0;
        _Lane2PhaseElapsed = 0.0;
        _Lane3PhaseElapsed = 0.0;
        ck::Trace("JoltCharacterGym: reset all lanes to their start positions");
    }

    UFUNCTION(Exec, DisplayName="Jolt Character - Cycle Lane 3 Push Policy")
    void Ck_GymJoltCharacter_CyclePushPolicy()
    {
        _Lane3PolicyIndex = (_Lane3PolicyIndex + 1) % 4;
        auto NewPolicy = DoPolicyFromIndex(_Lane3PolicyIndex);

        utils_entity_lifetime::Request_DestroyEntity(_Lane3Char);
        utils_entity_lifetime::Request_DestroyEntity(_Lane3Box);

        _Lane3Box = DoAddLane3Box(_Lane3BoxStart);
        _Lane3Char = DoAddCharacter(_Lane3CharStart - _Origin, NewPolicy, n"Character.Lane3Char");
        utils_jolt_character::Request_Move(_Lane3Char, FCk_Request_JoltCharacter_Move(FVector(-_WalkSpeed, 0.0, 0.0)));
        _Lane3PhaseElapsed = 0.0;

        ck::Trace(f"JoltCharacterGym: lane 3 respawned with PushPolicy={NewPolicy}");
    }
}
