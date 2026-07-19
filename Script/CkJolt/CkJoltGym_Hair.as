// Language=angelscript

//============================================================================
// CK JOLT GYM — HAIR (STRANDS ON A MOVING ANCHOR BODY)
//
// A Kinematic "head" sphere orbits and bobs (ECS-transform-driven, pushed
// into Jolt by the KinematicPush processor). A ring of short Springy rope
// strands is anchored to it via Create_Rope's AnchorBody — the strands whip
// and trail as the head moves: the hair pattern is ropes + a moving anchor,
// not a separate feature. Enable ck.Jolt.DebugDraw.Enabled 1 to see it.
//============================================================================

class ACk_JoltGym_Hair_GameMode : ACkTests_Gym_Base_GameMode
{
    default PlayerControllerClass = ACk_JoltGym_Hair_PlayerController;
    default DefaultPawnClass = ACk_Gym_Base_Pawn;
}

class ACk_JoltGym_Hair_PlayerController : ACk_Gym_Base_PlayerController
{
    private FVector _Origin = FVector::ZeroVector;
    private TArray<FCk_Handle> _SpawnedRoots;
    private FCk_Handle_Transform _HeadTransform;

    private FVector _HeadCenter = FVector::ZeroVector;
    private float _HeadRadius = 45.0;
    private int32 _StrandCount = 10;
    private float _Time = 0.0;
    private float _OrbitRadius = 140.0;
    private bool _Moving = true;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();

        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.Jolt.Hair");
        Station.Title = FText::FromString("JOLT HAIR");
        auto Description = TArray<FText>();
        Description.Add(FText::FromString("A kinematic head orbits with a ring of springy strands anchored to it.\nHair = ropes + a moving AnchorBody."));
        Description.Add(FText::FromString("Ck_GymJoltHair_ToggleMotion\nCk_GymJoltHair_Reset\nck.Jolt.DebugDraw.Enabled 1"));
        Station.Description = Description;
        Station.AutoSize = true;
        Stations.Add(Station);

        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.Jolt.Hair", ECk_GymStation_Anchor::FootprintCenter);
        _HeadCenter = _Origin + FVector(-400.0, 0.0, 320.0);

        DoBuildContent();

        // The tick driver lives OUTSIDE _SpawnedRoots so Reset never destroys (and re-creates) it.
        auto GymEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        GymEntity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(GymEntity, n"Hair.GymEntity");
        utils_timer::Create_Tick(GymEntity, FCk_Delegate_Timer(this, n"OnTick"));

        ck::Trace("JoltHairGym: started — strands anchored to the orbiting head");
    }

    private void DoBuildContent()
    {
        // ---- The kinematic head, driven by ECS transform updates each tick ----
        auto HeadEntity = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
        HeadEntity.Request_OverrideToSelf();
        utils_handle::Set_DebugName(HeadEntity, n"Hair.Head");
        _HeadTransform = utils_transform::Add(HeadEntity, FTransform(FRotator::ZeroRotator, _HeadCenter + DoOrbitOffset()),
            ECk_Replication::DoesNotReplicate);

        auto HeadShape = FCk_Jolt_ShapeDimensions(ECk_Jolt_ShapeType::Sphere);
        HeadShape.Set_Radius(_HeadRadius);
        auto HeadParams = FCk_Fragment_JoltBody_ParamsData(ECk_JoltBody_ShapeSource::ExplicitShape);
        HeadParams.Set_ShapeDimensions(HeadShape);
        HeadParams.Set_MotionType(ECk_MotionType::Kinematic);
        auto HeadBody = utils_jolt_body::Add(HeadEntity, HeadParams);

        FCk_Handle HeadGeneric = HeadEntity;
        _SpawnedRoots.Add(HeadGeneric);

        // ---- Strand ring on the upper hemisphere ----
        auto HeadNow = _HeadCenter + DoOrbitOffset();
        for (int32 i = 0; i < _StrandCount; i++)
        {
            auto Angle = (Math::PI * 2.0) * float(i) / float(_StrandCount);
            // Scalp ring sits clearly OUTSIDE the head sphere so the first segment never spawns
            // overlapping it (segments and head share the PhysicsActor profile and would pop apart).
            auto ScalpPoint = HeadNow + FVector(
                Math::Cos(Angle) * _HeadRadius * 0.85,
                Math::Sin(Angle) * _HeadRadius * 0.85,
                _HeadRadius * 0.7);

            auto StrandRoot = utils_entity_lifetime::Request_CreateEntity(ck::TransientEntity());
            StrandRoot.Request_OverrideToSelf();
            utils_handle::Set_DebugName(StrandRoot, f"Hair.Strand{i}");

            auto RopeParams = FCk_JoltRope_ParamsData(ScalpPoint);
            RopeParams.Set_AnchorBody(HeadGeneric);
            RopeParams.Set_Direction(FVector(Math::Cos(Angle) * 0.35, Math::Sin(Angle) * 0.35, -1.0));
            RopeParams.Set_SegmentCount(5);
            RopeParams.Set_SegmentLength(26.0);
            RopeParams.Set_SegmentRadius(3.0);
            RopeParams.Set_SegmentMassKg(0.25);
            RopeParams.Set_LinkMode(ECk_JoltRope_LinkMode::Springy);
            RopeParams.Set_SpringFrequency(7.0);
            RopeParams.Set_SpringDamping(0.5);
            RopeParams.Set_LinearDamping(0.5);
            RopeParams.Set_AngularDamping(0.8);
            utils_jolt_rope::Create_Rope(StrandRoot, RopeParams);

            FCk_Handle RootGeneric = StrandRoot;
            _SpawnedRoots.Add(RootGeneric);
        }
    }

    private FVector DoOrbitOffset()
    {
        auto Angle = _Time * 1.1;
        return FVector(
            Math::Cos(Angle) * _OrbitRadius,
            Math::Sin(Angle) * _OrbitRadius,
            Math::Sin(_Time * 0.8) * 45.0);
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (!_Moving)
        { return; }

        if (ck::Is_NOT_Valid(_HeadTransform))
        { return; }

        _Time += float(InDeltaT.Get_Seconds());
        utils_transform::Request_SetTransform(_HeadTransform, FTransform(_HeadCenter + DoOrbitOffset()));
    }

    UFUNCTION(Exec, DisplayName="Jolt Hair - Toggle Head Motion")
    void Ck_GymJoltHair_ToggleMotion()
    {
        _Moving = !_Moving;
        if (_Moving)
        { ck::Trace("JoltHairGym: head motion ON"); }
        else
        { ck::Trace("JoltHairGym: head motion OFF"); }
    }

    UFUNCTION(Exec, DisplayName="Jolt Hair - Reset")
    void Ck_GymJoltHair_Reset()
    {
        for (auto Root : _SpawnedRoots)
        {
            utils_entity_lifetime::Request_DestroyEntity(Root);
        }
        _SpawnedRoots.Empty();
        _Time = 0.0;

        DoBuildContent();
        ck::Trace("JoltHairGym: reset");
    }
}
