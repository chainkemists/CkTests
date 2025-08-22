// Audio Pickup - Interactive audio triggers for powerups, levelups, and interface sounds
// Can be scattered throughout the level for testing various audio stingers

// Cube asset for visual representation
asset Asset_RegularCube of UCk_IsmRenderer_Data
{
    _Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/EngineMeshes/Cube.Cube",
        ECk_AssetSearchScope::Engine)._Asset);
    _Mobility = ECk_Mobility::Movable;
}

// Spawn parameters for AudioGym Advanced Audio Pickups
struct FCkAudioGym_Advanced_AudioPickup_SpawnParams
{
    UPROPERTY()
    FTransform Transform;
}

// Base Audio Pickup class
class UCkAudioGym_Advanced_AudioPickup : UCk_EntityScript_UE
{
    default _Replication = ECk_Replication::DoesNotReplicate;

    // Transform handle for positioning
    FCk_Handle_Transform TransformHandle;

    // Probe handle for overlap detection
    FCk_Handle_Probe ProbeHandle;

    // Visual representation
    FCk_Handle_IsmProxy PickupRenderer;

    // Spawn parameters
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    // Audio properties
    FGameplayTag AudioCueTag;

    // Pickup properties
    FVector PickupSize = FVector(100, 100, 100); // Size of pickup trigger

    FString PickupName = "Audio Pickup";

    FLinearColor PickupColor = FLinearColor(1.0f, 1.0f, 0.0f, 1.0f); // Yellow default

    bool bIsActive = true; // Can be picked up

    float CooldownTime = 2.0f; // Time before pickup can be triggered again

    FCk_Handle_Timer CooldownTimer;

    // Probe parameters
    FCk_Fragment_Probe_ParamsData ProbeParams;

    // Override construction script
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Set up probe parameters
        ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Pickup");
        ProbeParams._MotionType = ECk_MotionType::Kinematic;
        ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;

        // Filter to detect player probe overlaps
        ProbeParams._Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe"));

        // Use Static motion type for better overlap detection with kinematic player probe
        ProbeParams._MotionType = ECk_MotionType::Static;

        // Add transform component
        TransformHandle = utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);

        // Create probe (requires shape first)
        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(PickupSize / 2));
        utils_shapes::Add(InHandle, BoxShape);

        // Create probe with default debug info
        auto DebugInfo = FCk_Probe_DebugInfo();
        ProbeHandle = utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        // Draw debug box to visualize pickup area using CkDebugDraw_Utils
        auto PickupCenter = Transform.GetLocation();
        auto PickupExtent = PickupSize / 2;
        auto PickupRotation = Transform.GetRotation().Rotator();

        // Draw debug box around pickup area
        utils_debug_draw::DrawDebugBox(PickupCenter, PickupExtent, PickupColor, PickupRotation, 0.0f, 3.0f);

        // Add visual representation using regular cube
        auto IsmProxyParams = FCk_Fragment_IsmProxy_ParamsData(Asset_RegularCube);
        // Scale the 260x260x260 regular cube to match our pickup size
        FVector ScaleMultiplier = CalculateRegularCubeScale(PickupSize);
        IsmProxyParams._ScaleMultiplier = ScaleMultiplier;
        PickupRenderer = utils_ism_proxy::Add(InHandle, IsmProxyParams);

        // Bind overlap events
        utils_probe::BindTo_OnBeginOverlap(ProbeHandle,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnPlayerEnteredPickup"));

        // Print pickup info with probe details for debugging
        Print("🎁 Pickup Created: " + PickupName + " at " + Transform.GetLocation().ToString(), 3.0f);
        Print("🔍 Probe Filter: Player.Probe, Motion: Static, Size: " + PickupSize.ToString(), 2.0f);

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Utility function to calculate scale for 260x260x260 regular cube
    FVector CalculateRegularCubeScale(FVector InDesiredSize)
    {
        return InDesiredSize / 260.0f;
    }

    // Handle player entering pickup area
    UFUNCTION()
    void OnPlayerEnteredPickup(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        if (!bIsActive)
        {
            Print("🚫 Pickup on cooldown: " + PickupName, 1.0f);
            return;
        }

        // Trigger the pickup
        TriggerPickup();
    }

    void TriggerPickup()
    {
        // Play the audio
        PlayPickupAudio();

        // Deactivate pickup temporarily
        bIsActive = false;

        // Change color to indicate pickup was used
        UpdatePickupVisual(false);

        // Start cooldown timer
        StartCooldown();

        Print("🎁 Pickup triggered: " + PickupName, 2.0f);
    }

    void PlayPickupAudio()
    {
        // Execute the pickup audio cue
        auto SelfEntity = ck::SelfEntity(this);

        // Create spawn params with the pickup's transform
        auto AudioSpawnParams = FCkAudioGym_Advanced_AudioCue_SpawnParams();
        AudioSpawnParams.Transform = Transform;

        auto Str = FInstancedStruct();
        Str.InitializeAs(AudioSpawnParams);
        auto PendingEntityScript = utils_cue::Request_Execute_Local(SelfEntity, AudioCueTag, Str);

        Print("🔊 Playing pickup audio: " + PickupName, 1.0f);
    }

    void UpdatePickupVisual(bool bActive)
    {
        if (!ck::IsValid(PickupRenderer))
        {
            return;
        }

        // Change color based on active state
        FLinearColor NewColor = bActive ? PickupColor : FLinearColor(0.3f, 0.3f, 0.3f, 1.0f); // Grey when inactive

        // Note: ISM color changes might require re-adding the component
        // For now, we'll just log the state change
        Print(bActive ? "✅ Pickup ready" : "⏸️ Pickup cooling down", 1.0f);
    }

    void StartCooldown()
    {
        // Start cooldown timer (simplified - no timer for now, just immediate reset)
        // In a real implementation, you'd use utils_timer here
        Print("⏱️ Cooldown started", 1.0f);

        // For now, just reset after a short delay (this would be timer-based in production)
        ResetPickup();
    }

    void ResetPickup()
    {
        bIsActive = true;
        UpdatePickupVisual(true);
        Print("🔄 Pickup reset: " + PickupName, 1.0f);
    }
}
