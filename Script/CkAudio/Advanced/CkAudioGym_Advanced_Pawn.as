// Advanced AudioGym Pawn - Clean and simple setup

class ACkAudioGym_Advanced_Pawn : ADefaultPawn
{
    // EntityBridge component for ECS integration
    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    // Override ConstructionScript to add player probe
    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        // Add player probe feature to the entity
        AddPlayerProbe(InEntity);
    }

    void AddPlayerProbe(FCk_Handle InEntity)
    {
        // Add a probe feature to the player entity so it can overlap with stations
        auto ProbeParams = FCk_Fragment_Probe_ParamsData();
        ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe");
        ProbeParams._MotionType = ECk_MotionType::Kinematic;
        ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;

        // Add transform first (required for probe)
        auto TransformHandle = utils_transform::Add(InEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Create a small probe around the player
        auto PlayerProbeSize = FVector(100, 100, 200); // Player-sized probe
        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(PlayerProbeSize));
        utils_shapes::Add(InEntity, BoxShape);

        auto DebugInfo = FCk_Probe_DebugInfo();
        utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        Print("✅ Player probe added", 2.0f);
    }

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        // Set up the level with stations
        SetupLevel();
    }

    void SetupLevel()
    {
        // Spawn the spatial station
        SpawnSpatialStation();

        // Spawn the attenuation station
        SpawnAttenuationStation();
    }

    void SpawnSpatialStation()
    {
        // Spawn the spatial station at a specific location - positioned for medium-sized station
        // Actual size: 400/1040 ≈ 0.38x of 1040 = ~395x395x296
        auto StationLocation = FVector(0, 200, 0); // Center X, 200 units forward
        auto StationRotation = FRotator::ZeroRotator;
        auto StationTransform = FTransform(StationRotation, StationLocation);

        // Create spawn params for the spatial station
        auto SpawnParams = FCkAudioGym_Advanced_Station_SpawnParams();
        SpawnParams.Transform = StationTransform;

        // Spawn the spatial station entity script
        auto SpatialStationEntity = utils_entity_script::Request_SpawnEntity(ck::SelfEntity(this),
            UCkAudioGym_Advanced_SpatialStation, SpawnParams);

        if (ck::IsValid(SpatialStationEntity))
        {
            Print("✅ Spatial Station spawned successfully at (0, 200, 0)", 3.0f);
        }
        else
        {
            Print("❌ Failed to spawn Spatial Station", 3.0f);
        }
    }

    void SpawnAttenuationStation()
    {
        // Spawn the attenuation station at a specific location - positioned to avoid overlap
        // Actual size: 800/1040 ≈ 0.77x of 1040 = ~800x800x308
        // Need separation: 395/2 + 800/2 + 500 padding = 197.5 + 400 + 500 = 1097.5
        auto StationLocation = FVector(0, 1100, 0); // Center X, 1100 units forward
        auto StationRotation = FRotator::ZeroRotator;
        auto StationTransform = FTransform(StationRotation, StationLocation);

        // Create spawn params for the attenuation station
        auto SpawnParams = FCkAudioGym_Advanced_Station_SpawnParams();
        SpawnParams.Transform = StationTransform;

        // Spawn the attenuation station entity script
        auto AttenuationStationEntity = utils_entity_script::Request_SpawnEntity(ck::SelfEntity(this),
            UCkAudioGym_Advanced_AttenuationStation, SpawnParams);

        if (ck::IsValid(AttenuationStationEntity))
        {
            Print("✅ Attenuation Station spawned successfully at (0, 1100, 0)", 3.0f);
        }
        else
        {
            Print("❌ Failed to spawn Attenuation Station", 3.0f);
        }
    }
}
