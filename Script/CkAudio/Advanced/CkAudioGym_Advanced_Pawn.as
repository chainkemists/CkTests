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
    }

    void SpawnSpatialStation()
    {
        // Spawn the spatial station at a specific location
        auto StationLocation = FVector(500, 0, 0); // 500 units to the right of origin
        auto StationRotation = FRotator::ZeroRotator;
        auto StationTransform = FTransform(StationRotation, StationLocation);

        // Spawn the spatial station entity script
        auto SpatialStationEntity = utils_entity_script::Request_SpawnEntity(ck::SelfEntity(this),
            UCkAudioGym_Advanced_SpatialStation, FInstancedStruct());

        if (ck::IsValid(SpatialStationEntity))
        {
            Print("✅ Spatial Station spawned successfully", 3.0f);
        }
        else
        {
            Print("❌ Failed to spawn Spatial Station", 3.0f);
        }
    }
}
