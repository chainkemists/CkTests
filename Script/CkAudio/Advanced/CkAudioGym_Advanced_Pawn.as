// Advanced AudioGym Pawn - Clean and simple setup
// Following gym philosophy: simple, readable, organized

class ACkAudioGym_Advanced_Pawn : ADefaultPawn
{
    // EntityBridge component for ECS integration
    UPROPERTY(DefaultComponent)
    UCk_EntityBridge_ActorComponent_UE EntityBridge;
    default EntityBridge._Replication = ECk_Replication::DoesNotReplicate;
    default EntityBridge._ConstructionScript = UCk_Entity_ConstructionScript_WithTransform_PDA;

    // ============================================================================
    // PLAYER SETUP
    // ============================================================================

    UFUNCTION(BlueprintOverride)
    void ConstructionScript()
    {
        EntityBridge._OnReplicationComplete_MC.AddUFunction(this, n"OnReplicationComplete");
    }

    UFUNCTION()
    void OnReplicationComplete(FCk_Handle InEntity)
    {
        SetupPlayer(InEntity);
    }

    void SetupPlayer(FCk_Handle InEntity)
    {
        // Add player probe feature so player can overlap with stations
        auto ProbeParams = FCk_Fragment_Probe_ParamsData();
        ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe");
        ProbeParams._MotionType = ECk_MotionType::Kinematic;
        ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;

        // Add transform first (required for probe)
        auto TransformHandle = utils_transform::Add(InEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        // Create a larger probe around the player for better pickup detection
        auto PlayerProbeSize = FVector(150, 150, 250); // Larger player probe for better overlap detection
        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(PlayerProbeSize));
        utils_shapes::Add(InEntity, BoxShape);

        auto DebugInfo = FCk_Probe_DebugInfo();
        utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        ck::Trace("✅ Player probe added", NAME_None, 2.0f, utils_linear_color::Get_Green());
    }

    // ============================================================================
    // LEVEL SETUP
    // ============================================================================

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        SetupLevel();
    }

    void SetupLevel()
    {
        ck::Trace("🎯 AudioGym Advanced Level Ready - Use StationSpawner actors to place stations", NAME_None, 5.0f, utils_linear_color::Get_Orange());

        // Scatter audio pickups around the level for testing
        ScatterAudioPickups();
    }

    // ============================================================================
    // PICKUP SCATTERING
    // ============================================================================

    void ScatterAudioPickups()
    {
        ck::Trace("🎁 Scattering audio pickups throughout the level...", NAME_None, 3.0f, utils_linear_color::Get_Yellow());

        // Scatter pickups across the full 8000x6000 level area
        // Level dimensions: X: -4000 to +4000, Y: -3000 to +3000
        ScatterPickupsAcrossFullLevel();

        ck::Trace("✅ Audio pickups scattered successfully", NAME_None, 2.0f, utils_linear_color::Get_Green());
    }

void ScatterPickupsAcrossFullLevel()
{
    // Test cluster around (1000, 1000, 100) for audio debugging
    // Very close to test point - should be loud
    SpawnInterfacePickup(FVector(1000, 1000, 100));  // Exact test position
    SpawnInterfacePickup(FVector(1050, 1050, 100));  // 50 units away
    SpawnInterfacePickup(FVector(950, 950, 100));    // 50 units away, other direction

    // Medium distance - should be audible with attenuation
    SpawnLevelUpPickup(FVector(1200, 1200, 100));    // ~280 units away
    SpawnLevelUpPickup(FVector(800, 800, 100));      // ~280 units away
    SpawnLevelUpPickup(FVector(1000, 1400, 100));    // 400 units away
    SpawnLevelUpPickup(FVector(1000, 600, 100));     // 400 units away

    // Longer distance - testing attenuation falloff
    SpawnNotificationsPickup(FVector(1500, 1500, 100)); // ~700 units away
    SpawnNotificationsPickup(FVector(500, 500, 100));   // ~700 units away
    SpawnNotificationsPickup(FVector(1000, 1800, 100)); // 800 units away
    SpawnNotificationsPickup(FVector(1000, 200, 100));  // 800 units away

    // Control test - one near world origin to compare
    SpawnInterfacePickup(FVector(100, 100, 100));       // Near origin for comparison
}

    // ============================================================================
    // PICKUP SPAWNING HELPERS
    // ============================================================================

    void SpawnInterfacePickup(FVector Location)
    {
        auto SpawnParams = FCkAudioGym_Advanced_AudioPickup_SpawnParams();
        SpawnParams.Transform = FTransform(FRotator::ZeroRotator, Location);

        auto PickupEntity = utils_entity_script::Request_SpawnEntity(ck::SelfEntity(this),
            UCkAudioGym_Advanced_InterfacePickup, SpawnParams);

        if (ck::IsValid(PickupEntity))
        {
            ck::Trace(f"🔵 Interface pickup placed at {Location.X},{Location.Y}", NAME_None, 1.0f, utils_linear_color::Get_Cyan());
        }
    }

    void SpawnLevelUpPickup(FVector Location)
    {
        auto SpawnParams = FCkAudioGym_Advanced_AudioPickup_SpawnParams();
        SpawnParams.Transform = FTransform(FRotator::ZeroRotator, Location);

        auto PickupEntity = utils_entity_script::Request_SpawnEntity(ck::SelfEntity(this),
            UCkAudioGym_Advanced_LevelUpPickup, SpawnParams);

        if (ck::IsValid(PickupEntity))
        {
            ck::Trace(f"🟡 LevelUp pickup placed at {Location.X},{Location.Y}", NAME_None, 1.0f, utils_linear_color::Get_Yellow());
        }
    }

    void SpawnNotificationsPickup(FVector Location)
    {
        auto SpawnParams = FCkAudioGym_Advanced_AudioPickup_SpawnParams();
        SpawnParams.Transform = FTransform(FRotator::ZeroRotator, Location);

        auto PickupEntity = utils_entity_script::Request_SpawnEntity(ck::SelfEntity(this),
            UCkAudioGym_Advanced_NotificationsPickup, SpawnParams);

        if (ck::IsValid(PickupEntity))
        {
            ck::Trace(f"🟣 Notifications pickup placed at {Location.X},{Location.Y}", NAME_None, 1.0f, utils_linear_color::Get_Magenta());
        }
    }
}
