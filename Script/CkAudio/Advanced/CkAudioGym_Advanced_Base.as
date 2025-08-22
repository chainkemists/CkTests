// Base class for Advanced AudioGym stations, power-ups, and spatial sounds
// Derived from UCk_EntityScript_UE to house common elements

// Cube assets for visual representation
asset Asset_RegularCube of UCk_IsmRenderer_Data
{
    _Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/EngineMeshes/Cube.Cube",
        ECk_AssetSearchScope::Engine)._Asset);
    _Mobility = ECk_Mobility::Movable;
}

// Background cube with inverted normals - useful for future visual elements
asset Asset_BackgroundCube of UCk_IsmRenderer_Data
{
    _Mesh = Cast<UStaticMesh>(utils_i_o::LoadAssetByName("/Engine/EngineMeshes/BackgroundCube.BackgroundCube",
        ECk_AssetSearchScope::Engine)._Asset);
    _Mobility = ECk_Mobility::Movable;
}



// Spawn parameters for AudioGym Advanced Stations
struct FCkAudioGym_Advanced_Station_SpawnParams
{
    UPROPERTY()
    FTransform Transform; // name MUST match the ExposeOnSpawn in the EntityScript
}

class UCkAudioGym_Advanced_Base : UCk_EntityScript_UE
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform; // this name MUST match the one in the above SpawnParams

    default _Replication = ECk_Replication::DoesNotReplicate;

    // Transform feature
    FCk_Handle_Transform TransformHandle;

    // Probe feature
    FCk_Handle_Probe ProbeHandle;

    // AudioCue to use
    FGameplayTag AudioCueTag;

    // Probe parameters - exposed as class defaults for derived classes to override
    UPROPERTY()
    FCk_Fragment_Probe_ParamsData ProbeParams;

    // Default probe setup
    UPROPERTY()
    FVector ProbeSize = FVector(800, 800, 400); // More reasonable default size

    // Visual representation properties
    UPROPERTY()
    FString StationName = "Audio Station";

    UPROPERTY()
    FString StationDescription = "Walk into this area to test audio features";

    UPROPERTY()
    FLinearColor StationColor = FLinearColor(0.2f, 0.6f, 1.0f, 1.0f); // Default blue

    // Utility functions for calculating scale multipliers
    FVector CalculateBackgroundCubeScale(FVector InDesiredSize)
    {
        // Background cube is 1040x1040x1040, so divide desired size by 1040
        return InDesiredSize / 1040.0f;
    }

    FVector CalculateRegularCubeScale(FVector InDesiredSize)
    {
        // Regular cube is 260x260x260, so divide desired size by 260
        return InDesiredSize / 260.0f;
    }



    // Set default probe parameters
    default ProbeParams._ProbeName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Probe.Station");
    default ProbeParams._MotionType = ECk_MotionType::Kinematic;
    default ProbeParams._ResponsePolicy = ECk_ProbeResponse_Policy::Notify;
    default ProbeParams._Filter.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Player.Probe"));

    // Override construction script
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Get self entity and add transform
        TransformHandle = utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);

        // Create probe (requires shape first)
        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(ProbeSize / 2));
        utils_shapes::Add(InHandle, BoxShape);

        // Create probe with default parameters
        auto DebugInfo = FCk_Probe_DebugInfo();
        ProbeHandle = utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        // Add ISM Proxy renderer for visual representation (station floor)
        auto IsmProxyParams = FCk_Fragment_IsmProxy_ParamsData(Asset_BackgroundCube);
        // Use utility function to calculate scale for 1040x1040x1040 background cube
        IsmProxyParams._ScaleMultiplier = CalculateBackgroundCubeScale(ProbeSize);
        utils_ism_proxy::Add(InHandle, IsmProxyParams);

                // Print station information to console for now
        Print("🎯 Station Created: " + StationName, 5.0f);
        Print("📝 Description: " + StationDescription, 5.0f);
        Print("🎨 Color Theme Applied", 3.0f);
        Print("📏 Large Testing Area Created", 3.0f);
        Print("📍 Position: Transform applied", 3.0f);
        Print("📐 Scale: Using utility function for 1040x1040x1040 background cube", 3.0f);

        // Bind overlaps to base class functions that derived classes can override
        utils_probe::BindTo_OnBeginOverlap(ProbeHandle,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_Probe_OnBeginOverlap(this, n"OnPlayerEnteredStation"));

        utils_probe::BindTo_OnEndOverlap(ProbeHandle,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_Probe_OnEndOverlap(this, n"OnPlayerExitedStation"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Base overlap functions that derived classes can override
    UFUNCTION(BlueprintEvent)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        // Base implementation - derived classes should override
    }

    UFUNCTION(BlueprintEvent)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        // Base implementation - derived classes should override
    }





    // Function to update visual feedback based on audio state
    protected void UpdateVisualFeedback(bool bIsAudioPlaying)
    {
        // This can be overridden by derived classes to provide specific visual feedback
        // For now, we'll just store the state for potential future use

        if (bIsAudioPlaying)
        {
            Print("🎵 Audio playing at: " + StationName, 2.0f);
        }
        else
        {
            Print("🔇 Audio stopped at: " + StationName, 2.0f);
        }
    }
}
