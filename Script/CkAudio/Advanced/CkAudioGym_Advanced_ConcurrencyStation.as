class UCkAudioGym_Advanced_ConcurrencyStation : UCkAudioGym_Advanced_Base
{
    // Concurrency testing specific properties
    UPROPERTY()
    TArray<FGameplayTag> ConcurrentTrackTags;

    UPROPERTY()
    int32 MaxConcurrentTracks = 8;

    UPROPERTY()
    float SpawnInterval = 1.5f;

    UPROPERTY()
    bool IsSpawningConcurrentSounds = false;

    UPROPERTY()
    FCk_Handle_Timer SpawnTimer;

    UPROPERTY()
    int32 CurrentSpawnIndex = 0;

    UPROPERTY()
    int32 TotalSoundsSpawned = 0;

    // Visual indicators for concurrent track status
    TArray<FCk_Handle_IsmProxy> TrackIndicators;

    // Override DoConstruct to set up concurrency testing station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Configure station properties
        StationName = "CONCURRENCY STATION";
        StationDescription = "Test multiple simultaneous audio tracks with priority management";
        StationThemeColor = FLinearColor(0.8f, 0.2f, 0.8f, 1.0f); // Purple for concurrency
        StationBounds = FVector(600, 1000, 350); // Corridor-shaped for sequential triggering

        // Configure AudioDirector for maximum concurrency testing
        AudioDirectorParams._DefaultCrossfadeDuration = FCk_Time(0.8f);
        AudioDirectorParams._MaxConcurrentTracks = MaxConcurrentTracks;
        AudioDirectorParams._SamePriorityBehavior = ECk_SamePriorityBehavior::Allow; // Allow overlapping sounds

        // Setup concurrent track tags
        SetupConcurrentTrackTags();

        // Call parent construction
        auto Result = Super::DoConstruct(InHandle);

        // Add all concurrent tracks to director
        SetupConcurrentAudioTracks();

        // Create visual indicators for track status
        CreateTrackIndicators(InHandle);

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Concurrency"));

        return Result;
    }

    void SetupConcurrentTrackTags()
    {
        ConcurrentTrackTags.Empty();

        // Create tags for different types of concurrent sounds
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Thunder.A"));
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Thunder.B"));
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Thunder.C"));
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Interface.A"));
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Interface.B"));
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Ambient.A"));
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Ambient.B"));
        ConcurrentTrackTags.Add(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Music"));

        ck::Trace(f"Concurrency Station: {ConcurrentTrackTags.Num()} concurrent tracks configured", NAME_None, 2.0f, StationThemeColor);
    }

    void SetupConcurrentAudioTracks()
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            ck::Trace("AudioDirector NOT valid - cannot setup concurrent tracks", NAME_None, 3.0f, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
            return;
        }

        for (int32 i = 0; i < ConcurrentTrackTags.Num(); i++)
        {
            auto TrackTag = ConcurrentTrackTags[i];

            // Choose appropriate sound asset based on track type
            auto SoundAsset = GetSoundAssetForTrackType(i);

            auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(TrackTag, SoundAsset);

            // Configure track parameters for concurrency testing
            TrackParams._Priority = 30 + (i * 5); // Varied priorities for interesting interactions
            TrackParams._Volume = 0.6f; // Lower volume since many will play simultaneously
            TrackParams._DefaultFadeInTime = FCk_Time(0.3f);
            TrackParams._DefaultFadeOutTime = FCk_Time(0.5f);

            // Set different override behaviors for testing
            if (i < 3) // Thunder sounds - queue up
            {
                TrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Queue;
                TrackParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
            }
            else if (i < 5) // Interface sounds - interrupt
            {
                TrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
                TrackParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
            }
            else // Ambient and music - crossfade
            {
                TrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
                TrackParams._LoopBehavior = ECk_LoopBehavior::Loop;
            }

            utils_audio_director::Request_AddTrack(AudioDirector, TrackParams);
        }

        ck::Trace("Concurrency Station: All concurrent tracks configured with varied priorities", NAME_None, 2.0f, ActiveColor);
    }

    USoundBase GetSoundAssetForTrackType(int32 InTrackIndex)
    {
        if (InTrackIndex < 3) // Thunder variants
        {
            return Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset);
        }
        else if (InTrackIndex < 5) // Interface variants
        {
            return Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset);
        }
        else // Ambient and music
        {
            return Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset);
        }
    }

    void CreateTrackIndicators(FCk_Handle& InHandle)
    {
        TrackIndicators.Empty();

        for (int32 i = 0; i < ConcurrentTrackTags.Num(); i++)
        {
            auto IndicatorParams = FCk_Fragment_IsmProxy_ParamsData(ck::Asset_StationMarker);
            IndicatorParams._ScaleMultiplier = FVector(0.2f, 0.2f, 0.2f);

            // Arrange indicators in a line above the station
            // TODO: Position indicators based on index
            auto Indicator = utils_ism_proxy::Add(InHandle, IndicatorParams);
            TrackIndicators.Add(Indicator);
        }
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        Super::OnPlayerEnteredStation(InProbe, InOverlapInfo);

        StartConcurrencyTest();
    }

    UFUNCTION(BlueprintOverride)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        Super::OnPlayerExitedStation(InProbe, InOverlapInfo);

        StopConcurrencyTest();
    }

    void StartConcurrencyTest()
    {
        ck::Trace("Concurrency Test Started", NAME_None, 3.0f, ActiveColor);
        ck::Trace("Multiple audio tracks will spawn automatically", NAME_None, 3.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("Watch the AudioDirector manage priority conflicts", NAME_None, 3.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));

        IsSpawningConcurrentSounds = true;
        CurrentSpawnIndex = 0;
        TotalSoundsSpawned = 0;

        // Start with a few immediate sounds
        SpawnInitialConcurrentSounds();

        // Begin automatic spawning sequence
        StartAutomaticSpawning();

        DisplayConcurrencyInstructions();
    }

    void StopConcurrencyTest()
    {
        IsSpawningConcurrentSounds = false;

        // Stop automatic spawning
        StopAutomaticSpawning();

        // Stop all active tracks
        Request_StopAllTracks(FCk_Time(1.0f));

        // Reset counters
        CurrentSpawnIndex = 0;
        TotalSoundsSpawned = 0;

        ck::Trace("Concurrency Test Stopped", NAME_None, 2.0f, InactiveColor);
    }

    void SpawnInitialConcurrentSounds()
    {
        // Spawn a few sounds immediately to start the test
        for (int32 i = 0; i < 3; i++)
        {
            SpawnNextConcurrentSound();
        }
    }

    void StartAutomaticSpawning()
    {
        // TODO: In a real implementation, use utils_timer to create periodic spawning
        // For now, spawn sounds in sequence
        ck::Trace("Automatic spawning started", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));

        // Continue spawning sounds manually for demonstration
        for (int32 i = 0; i < 5; i++)
        {
            SpawnNextConcurrentSound();
        }
    }

    void StopAutomaticSpawning()
    {
        if (ck::IsValid(SpawnTimer))
        {
            utils_timer::Request_Stop(SpawnTimer);
        }
    }

    void SpawnNextConcurrentSound()
    {
        if (IsSpawningConcurrentSounds == false || CurrentSpawnIndex >= ConcurrentTrackTags.Num())
        {
            CurrentSpawnIndex = 0; // Wrap around to continue cycling
        }

        auto TrackTag = ConcurrentTrackTags[CurrentSpawnIndex];
        auto Priority = 30 + (CurrentSpawnIndex * 5);

        Request_StartTrack_WithParams(TrackTag, Priority, FCk_Time(0.3f));

        TotalSoundsSpawned++;
        CurrentSpawnIndex++;

        ck::Trace(f"Spawned concurrent sound #{TotalSoundsSpawned}: {TrackTag.ToString()}", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));

        DisplayConcurrencyStats();
    }

    void DisplayConcurrencyInstructions()
    {
        ck::Trace("CONCURRENCY TEST FEATURES:", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
        ck::Trace(f"Maximum concurrent tracks: {MaxConcurrentTracks}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("Priority-based track management enabled", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("Multiple override behaviors tested:", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Thunder: Queue behavior", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Interface: Interrupt behavior", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Ambient/Music: Crossfade behavior", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
    }

    void DisplayConcurrencyStats()
    {
        auto ActiveTracks = Get_ActiveTrackCount();
        auto HighestPriority = Get_CurrentHighestPriority();

        ck::Trace(f"Active tracks: {ActiveTracks}/{MaxConcurrentTracks}", NAME_None, 1.5f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Total spawned: {TotalSoundsSpawned}", NAME_None, 1.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Highest priority: {HighestPriority}", NAME_None, 1.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));

        if (ActiveTracks >= MaxConcurrentTracks)
        {
            ck::Trace("MAXIMUM CONCURRENCY REACHED", NAME_None, 2.0f, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
            ck::Trace("AudioDirector managing track priorities", NAME_None, 2.0f, FLinearColor(1.0f, 0.5f, 0.0f, 1.0f));
        }
    }

    // Public interface for manual control
    UFUNCTION()
    void TriggerConcurrentSoundBurst()
    {
        if (PlayerInside == false)
        {
            return;
        }

        ck::Trace("Triggering concurrent sound burst", NAME_None, 2.0f, ActiveColor);

        // Spawn multiple sounds rapidly to stress test the system
        for (int32 i = 0; i < 4; i++)
        {
            SpawnNextConcurrentSound();
        }
    }

    UFUNCTION()
    void TriggerHighPrioritySounds()
    {
        if (PlayerInside == false)
        {
            return;
        }

        ck::Trace("Triggering high priority sounds", NAME_None, 2.0f, ActiveColor);

        // Spawn interface sounds with very high priority to test interruption
        for (int32 i = 3; i < 5; i++) // Interface track indices
        {
            auto TrackTag = ConcurrentTrackTags[i];
            Request_StartTrack_WithParams(TrackTag, 90 + i, FCk_Time(0.1f));
        }
    }

    UFUNCTION()
    void TriggerCrossfadeTest()
    {
        if (PlayerInside == false)
        {
            return;
        }

        ck::Trace("Testing crossfade behavior with concurrent tracks", NAME_None, 2.0f, ActiveColor);

        // Start ambient tracks with crossfade behavior
        for (int32 i = 5; i < ConcurrentTrackTags.Num(); i++) // Ambient/music indices
        {
            auto TrackTag = ConcurrentTrackTags[i];
            Request_StartTrack_WithParams(TrackTag, 40 + i, FCk_Time(2.0f));
        }
    }

    UFUNCTION()
    void DemonstratePriorityPreemption()
    {
        ck::Trace("Demonstrating priority-based preemption", NAME_None, 3.0f, ActiveColor);

        // Fill up concurrent slots with low priority
        for (int32 i = 0; i < MaxConcurrentTracks; i++)
        {
            auto TrackTag = ConcurrentTrackTags[i % ConcurrentTrackTags.Num()];
            Request_StartTrack_WithParams(TrackTag, 20, FCk_Time(0.2f)); // Low priority
        }

        // Then trigger high priority sound that should preempt
        auto HighPriorityTag = ConcurrentTrackTags[4]; // Interface sound
        Request_StartTrack_WithParams(HighPriorityTag, 95, FCk_Time(0.1f));

        ck::Trace("High priority sound should preempt lower priority tracks", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
    }

    // Status reporting
    UFUNCTION()
    int32 Get_TotalSoundsSpawned()
    {
        return TotalSoundsSpawned;
    }

    UFUNCTION()
    bool Get_IsSpawningActive()
    {
        return IsSpawningConcurrentSounds;
    }

    UFUNCTION()
    int32 Get_MaxConcurrentTracks()
    {
        return MaxConcurrentTracks;
    }

    UFUNCTION()
    float Get_ConcurrencyUtilization()
    {
        auto ActiveTracks = Get_ActiveTrackCount();
        return float(ActiveTracks) / float(MaxConcurrentTracks);
    }
}