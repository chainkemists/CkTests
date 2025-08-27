class UCkAudioGym_Advanced_FeaturesStation : UCkAudioGym_Advanced_Base
{
    // Advanced features specific properties
    UPROPERTY()
    FCk_Handle_AudioDirector OrchestralDirector;

    UPROPERTY()
    TArray<FGameplayTag> OrchestralTrackTags;

    UPROPERTY()
    bool IsOrchestralSequenceActive = false;

    UPROPERTY()
    int32 CurrentSequenceStep = 0;

    UPROPERTY()
    FCk_Handle_Timer SequenceTimer;

    UPROPERTY()
    float DynamicVolumeMultiplier = 1.0f;

    // Complex track management
    UPROPERTY()
    TMap<FGameplayTag, FCk_Handle_AudioTrack> ManagedTracks;

    UPROPERTY()
    bool IsShowcaseMode = false;

    // Override DoConstruct to set up advanced features station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Configure station properties
        StationName = "ADVANCED FEATURES STATION";
        StationDescription = "Experience complete AudioDirector orchestration and dynamic audio";
        StationThemeColor = FLinearColor(1.0f, 0.0f, 1.0f, 1.0f); // Magenta for advanced
        StationBounds = FVector(1000, 1000, 500); // Large area for comprehensive testing

        // Configure primary AudioDirector for advanced orchestration
        AudioDirectorParams._DefaultCrossfadeDuration = FCk_Time(3.0f); // Long artistic crossfades
        AudioDirectorParams._MaxConcurrentTracks = 12; // Full orchestral arrangement
        AudioDirectorParams._SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

        // Setup orchestral track system
        SetupOrchestralTracks();

        // Call parent construction
        auto Result = Super::DoConstruct(InHandle);

        // Create secondary AudioDirector for complex layering
        CreateOrchestralDirector(InHandle);

        // Setup all advanced audio tracks
        SetupAdvancedAudioTracks();

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Features"));

        return Result;
    }

    void SetupOrchestralTracks()
    {
        OrchestralTrackTags.Empty();

        // Base rhythmic foundation
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Percussion.Base"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Percussion.Accent"));

        // Harmonic layers
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Harmony.Bass"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Harmony.Chords"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Harmony.Pads"));

        // Melodic elements
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Melody.Lead"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Melody.Counter"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Melody.Ornament"));

        // Dynamic elements
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Swell"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Stinger"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Climax"));
        OrchestralTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Resolution"));

        ck::Trace(f"Advanced Features Station: {OrchestralTrackTags.Num()} orchestral tracks configured", NAME_None, 2.0f, StationThemeColor);
    }

    void CreateOrchestralDirector(FCk_Handle& InHandle)
    {
        // Create specialized AudioDirector for orchestral management
        auto OrchestralParams = FCk_Fragment_AudioDirector_ParamsData();
        OrchestralParams._DefaultCrossfadeDuration = FCk_Time(4.0f); // Even longer for orchestral transitions
        OrchestralParams._MaxConcurrentTracks = 16; // Maximum orchestral complexity
        OrchestralParams._SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

        OrchestralDirector = utils_audio_director::Add(InHandle, OrchestralParams);

        // Bind orchestral director events
        utils_audio_director::BindTo_OnTrackStarted(OrchestralDirector,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_AudioDirector_Track(this, n"OnOrchestralTrackStarted"));

        utils_audio_director::BindTo_OnTrackStopped(OrchestralDirector,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_AudioDirector_Track(this, n"OnOrchestralTrackStopped"));
    }

    void SetupAdvancedAudioTracks()
    {
        SetupPrimaryDirectorTracks();
        SetupOrchestralDirectorTracks();
    }

    void SetupPrimaryDirectorTracks()
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            return;
        }

        // Setup foundational tracks in primary director
        auto AmbientTrackParams = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Features.Ambient.Foundation"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        AmbientTrackParams._Priority = 10; // Lowest priority foundation
        AmbientTrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
        AmbientTrackParams._LoopBehavior = ECk_LoopBehavior::Loop;
        AmbientTrackParams._Volume = 0.3f;
        AmbientTrackParams._DefaultFadeInTime = FCk_Time(5.0f);
        AmbientTrackParams._DefaultFadeOutTime = FCk_Time(5.0f);

        utils_audio_director::Request_AddTrack(AudioDirector, AmbientTrackParams);
    }

    void SetupOrchestralDirectorTracks()
    {
        if (ck::IsValid(OrchestralDirector) == false)
        {
            return;
        }

        ManagedTracks.Empty();

        for (int32 i = 0; i < OrchestralTrackTags.Num(); i++)
        {
            auto TrackTag = OrchestralTrackTags[i];
            auto SoundAsset = GetOrchestralSoundAsset(i);

            auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(TrackTag, SoundAsset);

            // Configure orchestral track parameters based on type
            ConfigureOrchestralTrackParams(TrackParams, i);

            utils_audio_director::Request_AddTrack(OrchestralDirector, TrackParams);

            // Track the handle for dynamic control
            auto TrackHandle = utils_audio_director::Get_TrackByName(OrchestralDirector, TrackTag);
            if (ck::IsValid(TrackHandle))
            {
                ManagedTracks.Add(TrackTag, TrackHandle);
            }
        }

        ck::Trace("Advanced Features Station: Orchestral AudioDirector fully configured", NAME_None, 2.0f, ActiveColor);
    }

    USoundBase GetOrchestralSoundAsset(int32 InTrackIndex)
    {
        if (InTrackIndex < 2) // Percussion
        {
            return Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset);
        }
        else if (InTrackIndex < 5) // Harmony
        {
            return Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset);
        }
        else if (InTrackIndex < 8) // Melody
        {
            return Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset);
        }
        else // Dynamic elements
        {
            return Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset);
        }
    }

    void ConfigureOrchestralTrackParams(FCk_Fragment_AudioTrack_ParamsData& InOutParams, int32 InTrackIndex)
    {
        if (InTrackIndex < 2) // Percussion - foundation rhythm
        {
            InOutParams._Priority = 20 + InTrackIndex;
            InOutParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Queue;
            InOutParams._LoopBehavior = ECk_LoopBehavior::Loop;
            InOutParams._Volume = 0.7f;
        }
        else if (InTrackIndex < 5) // Harmony - sustained pads
        {
            InOutParams._Priority = 30 + InTrackIndex;
            InOutParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
            InOutParams._LoopBehavior = ECk_LoopBehavior::Loop;
            InOutParams._Volume = 0.5f;
        }
        else if (InTrackIndex < 8) // Melody - prominent leads
        {
            InOutParams._Priority = 50 + InTrackIndex;
            InOutParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
            InOutParams._LoopBehavior = ECk_LoopBehavior::Loop;
            InOutParams._Volume = 0.8f;
        }
        else // Dynamic elements - highest priority effects
        {
            InOutParams._Priority = 80 + InTrackIndex;
            InOutParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
            InOutParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
            InOutParams._Volume = 0.9f;
        }

        // Set sophisticated fade times
        InOutParams._DefaultFadeInTime = FCk_Time(2.0f + (InTrackIndex * 0.3f));
        InOutParams._DefaultFadeOutTime = FCk_Time(1.5f + (InTrackIndex * 0.2f));
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        Super::OnPlayerEnteredStation(InProbe, InOverlapInfo);

        StartAdvancedFeaturesDemo();
    }

    UFUNCTION(BlueprintOverride)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        Super::OnPlayerExitedStation(InProbe, InOverlapInfo);

        StopAdvancedFeaturesDemo();
    }

    void StartAdvancedFeaturesDemo()
    {
        ck::Trace("ADVANCED FEATURES DEMONSTRATION STARTED", NAME_None, 4.0f, ActiveColor);
        ck::Trace("Dual AudioDirector orchestration with dynamic control", NAME_None, 3.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("Demonstrating complex multi-track arrangements", NAME_None, 3.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));

        IsShowcaseMode = true;

        // Start foundation layer
        StartFoundationLayer();

        // Begin orchestral sequence
        StartOrchestralSequence();

        DisplayAdvancedFeatures();
    }

    void StopAdvancedFeaturesDemo()
    {
        IsShowcaseMode = false;
        IsOrchestralSequenceActive = false;
        CurrentSequenceStep = 0;

        // Stop both directors
        Request_StopAllTracks(FCk_Time(3.0f));

        if (ck::IsValid(OrchestralDirector))
        {
            utils_audio_director::Request_StopAllTracks(OrchestralDirector, FCk_Time(3.0f));
        }

        ck::Trace("Advanced Features Demo Stopped", NAME_None, 2.0f, InactiveColor);
    }

    void StartFoundationLayer()
    {
        // Start ambient foundation in primary director
        Request_StartTrack_WithParams(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Features.Ambient.Foundation"),
                                     10, FCk_Time(5.0f));

        ck::Trace("Foundation layer started in Primary AudioDirector", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));
    }

    void StartOrchestralSequence()
    {
        if (ck::IsValid(OrchestralDirector) == false)
        {
            return;
        }

        IsOrchestralSequenceActive = true;
        CurrentSequenceStep = 0;

        ck::Trace("Starting orchestral sequence in Orchestral AudioDirector", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));

        // Begin with percussion foundation
        ExecuteOrchestralStep();
    }

    void ExecuteOrchestralStep()
    {
        if (IsOrchestralSequenceActive == false || CurrentSequenceStep >= OrchestralTrackTags.Num())
        {
            CompleteOrchestralSequence();
            return;
        }

        auto TrackTag = OrchestralTrackTags[CurrentSequenceStep];
        auto Priority = 20 + (CurrentSequenceStep * 5);

        if (ck::IsValid(OrchestralDirector))
        {
            auto Request = FCk_Request_AudioDirector_StartTrack(TrackTag);
            Request._PriorityOverrideMode = ECk_PriorityOverride::Override;
            Request._PriorityOverrideValue = Priority;
            Request._FadeInTime = FCk_Time(2.0f + (CurrentSequenceStep * 0.3f));

            utils_audio_director::Request_StartTrack(OrchestralDirector, Request);
        }

        ck::Trace(f"Orchestral Step {CurrentSequenceStep + 1}: {TrackTag.ToString()}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));

        CurrentSequenceStep++;

        // Continue sequence (would use timer in real implementation)
        if (CurrentSequenceStep < 6) // Build up first 6 layers
        {
            ExecuteOrchestralStep();
        }
    }

    void CompleteOrchestralSequence()
    {
        IsOrchestralSequenceActive = false;

        ck::Trace("ORCHESTRAL SEQUENCE COMPLETE", NAME_None, 3.0f, ActiveColor);
        ck::Trace("Full orchestral arrangement now active", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));

        // Begin dynamic control demonstration
        StartDynamicControlDemo();
    }

    void StartDynamicControlDemo()
    {
        ck::Trace("Starting dynamic control demonstration", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));

        // Demonstrate volume control across multiple tracks
        DemonstrateDynamicVolume();

        // Show priority manipulation
        DemonstratePriorityManagement();
    }

    void DemonstrateDynamicVolume()
    {
        ck::Trace("Demonstrating dynamic volume control", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));

        // Apply volume changes to managed tracks
        for (auto& TrackPair : ManagedTracks)
        {
            auto TrackHandle = TrackPair.Value;
            if (ck::IsValid(TrackHandle))
            {
                auto NewVolume = 0.5f * DynamicVolumeMultiplier;
                utils_audio_track::Request_SetVolume(TrackHandle, NewVolume, FCk_Time(1.0f));
            }
        }

        DynamicVolumeMultiplier = 1.5f; // Increase for next iteration
    }

    void DemonstratePriorityManagement()
    {
        ck::Trace("Demonstrating priority-based track management", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));

        // Trigger high priority stingers that should interrupt/crossfade with existing tracks
        auto StingerTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Climax");

        if (ck::IsValid(OrchestralDirector))
        {
            auto Request = FCk_Request_AudioDirector_StartTrack(StingerTag);
            Request._PriorityOverrideMode = ECk_PriorityOverride::Override;
            Request._PriorityOverrideValue = 95; // Very high priority
            Request._FadeInTime = FCk_Time(0.5f);

            utils_audio_director::Request_StartTrack(OrchestralDirector, Request);
        }
    }

    void DisplayAdvancedFeatures()
    {
        ck::Trace("ADVANCED AUDIODIRECTOR FEATURES ACTIVE:", NAME_None, 3.0f, FLinearColor(1.0f, 0.0f, 1.0f, 1.0f));
        ck::Trace("• Dual AudioDirector orchestration", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• 16-track concurrent management", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Dynamic priority manipulation", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Real-time volume control", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Complex crossfading sequences", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Multi-layer orchestral arrangement", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
    }

    // Orchestral director event handlers
    UFUNCTION()
    void OnOrchestralTrackStarted(FCk_Handle_AudioDirector InDirector, FGameplayTag InTrackName, FCk_Handle_AudioTrack InTrack)
    {
        ck::Trace(f"Orchestral track started: {InTrackName.ToString()}", NAME_None, 1.5f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        DisplayDualDirectorStats();
    }

    UFUNCTION()
    void OnOrchestralTrackStopped(FCk_Handle_AudioDirector InDirector, FGameplayTag InTrackName, FCk_Handle_AudioTrack InTrack)
    {
        ck::Trace(f"Orchestral track stopped: {InTrackName.ToString()}", NAME_None, 1.5f, FLinearColor(0.5f, 0.5f, 0.5f, 1.0f));
    }

    void DisplayDualDirectorStats()
    {
        auto PrimaryTracks = Get_ActiveTrackCount();
        auto OrchestralTracks = ck::IsValid(OrchestralDirector) ? utils_audio_director::Get_AllTracks(OrchestralDirector).Num() : 0;
        auto TotalTracks = PrimaryTracks + OrchestralTracks;

        ck::Trace(f"Audio System Status: {TotalTracks} total tracks", NAME_None, 1.5f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Primary Director: {PrimaryTracks} tracks", NAME_None, 1.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Orchestral Director: {OrchestralTracks} tracks", NAME_None, 1.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
    }

    // Public interface for advanced control
    UFUNCTION()
    void TriggerOrchestralClimax()
    {
        if (IsShowcaseMode == false)
        {
            return;
        }

        ck::Trace("Triggering orchestral climax sequence", NAME_None, 3.0f, ActiveColor);

        // Trigger multiple high-priority dynamic elements
        auto ClimaxTags = TArray<FGameplayTag>();
        ClimaxTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Swell"));
        ClimaxTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Climax"));
        ClimaxTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Orchestra.Dynamic.Resolution"));

        for (int32 i = 0; i < ClimaxTags.Num(); i++)
        {
            auto Request = FCk_Request_AudioDirector_StartTrack(ClimaxTags[i]);
            Request._PriorityOverrideMode = ECk_PriorityOverride::Override;
            Request._PriorityOverrideValue = 90 + i;
            Request._FadeInTime = FCk_Time(0.5f * (i + 1));

            utils_audio_director::Request_StartTrack(OrchestralDirector, Request);
        }
    }

    UFUNCTION()
    void DemonstrateCompleteSystemCapabilities()
    {
        ck::Trace("COMPLETE SYSTEM CAPABILITIES DEMONSTRATION", NAME_None, 4.0f, ActiveColor);

        TriggerOrchestralClimax();
        DemonstrateDynamicVolume();
        DemonstratePriorityManagement();

        ck::Trace("AudioDirector system operating at full capacity", NAME_None, 3.0f, FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));
    }
}