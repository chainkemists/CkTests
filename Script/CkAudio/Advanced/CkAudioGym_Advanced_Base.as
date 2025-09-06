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

    // AudioDirector feature
    FCk_Handle_AudioDirector AudioDirector;

    // AudioCue to use
    FGameplayTag AudioCueTag;

    // Probe parameters - exposed as class defaults for derived classes to override
    UPROPERTY()
    FCk_Fragment_Probe_ParamsData ProbeParams;

    // AudioDirector parameters
    UPROPERTY()
    FCk_Fragment_AudioDirector_ParamsData AudioDirectorParams;

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

    // Color constants for derived classes
    FLinearColor StationThemeColor = FLinearColor(0.2f, 0.6f, 1.0f, 1.0f);
    FVector StationBounds = FVector(800, 800, 400);
    FLinearColor ActiveColor = FLinearColor(0.0f, 1.0f, 0.0f, 1.0f);    // Green
    FLinearColor InactiveColor = FLinearColor(0.5f, 0.5f, 0.5f, 1.0f);  // Gray

    // Player tracking
    bool PlayerInside = false;
    float CurrentTestProgress = 0.0f;

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

    // Set default AudioDirector parameters
    default AudioDirectorParams._DefaultCrossfadeDuration = FCk_Time(2.0f);
    default AudioDirectorParams._MaxConcurrentTracks = 4;
    default AudioDirectorParams._SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

    // Override construction script
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Get self entity and add transform
        TransformHandle = utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);

        // Add AudioDirector
        AudioDirector = utils_audio_director::Add(InHandle, AudioDirectorParams);

        // Create probe (requires shape first)
        auto BoxShape = utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(ProbeSize / 2));
        utils_shapes::Add(InHandle, BoxShape);

        // Create probe with default parameters
        auto DebugInfo = FCk_Probe_DebugInfo();
        ProbeHandle = utils_probe::Add(TransformHandle, ProbeParams, DebugInfo);

        // Add ISM Proxy renderer for visual representation (station floor)
        auto IsmProxyParams = FCk_Fragment_IsmProxy_ParamsData(ck::Asset_BackgroundCube);
        // Use utility function to calculate scale for 1040x1040x1040 background cube
        IsmProxyParams._ScaleMultiplier = CalculateBackgroundCubeScale(ProbeSize);
        utils_ism_proxy::Add(InHandle, IsmProxyParams);

        // Print station information to console for now
        Print("🎯 Station Created: " + StationName, 5.0f);
        Print("📝 Description: " + StationDescription, 5.0f);
        Print("🎨 Color Theme Applied", 3.0f);
        Print("📐 Large Testing Area Created", 3.0f);
        Print("📍 Position: Transform applied", 3.0f);
        Print("📏 Scale: Using utility function for 1040x1040x1040 background cube", 3.0f);

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
        PlayerInside = true;
        // Base implementation - derived classes should override
    }

    UFUNCTION(BlueprintEvent)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        PlayerInside = false;
        // Base implementation - derived classes should override
    }

    // AudioDirector convenience methods for derived classes
    void Request_StartTrack_WithParams(FGameplayTag InTrackTag, int32 InPriority, FCk_Time InFadeTime)
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            return;
        }

        auto Request = FCk_Request_AudioDirector_StartTrack(InTrackTag);
        Request._PriorityOverrideMode = ECk_PriorityOverride::Override;
        Request._PriorityOverrideValue = InPriority;
        Request._FadeInTime = InFadeTime;
        utils_audio_director::Request_StartTrack(AudioDirector, Request);
    }

    void Request_StopTrack(FGameplayTag InTrackTag, FCk_Time InFadeTime)
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            return;
        }

        utils_audio_director::Request_StopTrack(AudioDirector, InTrackTag, InFadeTime);
    }

    void Request_StopAllTracks(FCk_Time InFadeTime)
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            return;
        }

        utils_audio_director::Request_StopAllTracks(AudioDirector, InFadeTime);
    }

    int32 Get_ActiveTrackCount()
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            return 0;
        }

        return utils_audio_director::Get_AllTracks(AudioDirector).Num();
    }

    int32 Get_CurrentHighestPriority()
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            return 0;
        }

        // This would need to be implemented based on your framework's capabilities
        return 50; // Placeholder
    }

    // Function to update visual feedback based on audio state
    protected void UpdateVisualFeedback(bool IsAudioPlaying)
    {
        // This can be overridden by derived classes to provide specific visual feedback
        // For now, we'll just store the state for potential future use

        if (IsAudioPlaying)
        {
            Print("🎵 Audio playing at: " + StationName, 2.0f);
        }
        else
        {
            Print("🔇 Audio stopped at: " + StationName, 2.0f);
        }
    }

    // Station visual state management
    void UpdateStationVisualState()
    {
        // Base implementation for station visual feedback
        if (PlayerInside)
        {
            Print("Station Status: ACTIVE", 1.0f);
        }
        else
        {
            Print("Station Status: INACTIVE", 1.0f);
        }
    }
}