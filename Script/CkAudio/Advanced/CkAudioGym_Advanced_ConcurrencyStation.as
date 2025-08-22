// Concurrency Station - Tests multiple audio cues playing simultaneously
// Inherits from UCkAudioGym_Advanced_Base

class UCkAudioGym_Advanced_ConcurrencyStation : UCkAudioGym_Advanced_Base
{
        // Concurrency specific properties
    UPROPERTY()
    int32 MaxConcurrentSounds = 5; // Maximum number of sounds that can play at once

    UPROPERTY()
    float SpawnInterval = 1.0f; // Time between spawning new sounds (seconds)

    UPROPERTY()
    TArray<FCk_Handle_AudioCue> ActiveAudioCues; // Track all currently playing sounds

    UPROPERTY()
    bool IsStationActive = false;

    UPROPERTY()
    FCk_Handle_Timer SpawnTimer; // Timer for continuous spawning

    // Override DoConstruct to set up concurrency audio station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        Super::DoConstruct(InHandle);

        // Set up the thunder audio cue tag (we'll use the same one for multiple instances)
        AudioCueTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Spatial.Thunder");

        // Override probe size for corridor testing - long and narrow for sequential triggering
        // Corridor is long in X (forward direction), narrow in Y and Z
        ProbeSize = FVector(200, 1200, 300); // Corridor: 200 units wide, 1200 units long, 300 units tall

        // Set visual properties
        StationName = "CONCURRENCY STATION";
        StationDescription = "Walk in/out of corridor to spawn overlapping thunder sounds";
        StationColor = FLinearColor(0.8f, 0.2f, 0.8f, 1.0f); // Purple for concurrency

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Concurrency"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        if (IsStationActive == false)
        {
            StartConcurrencyTest();
        }
        else
        {
            // Player re-entered - spawn more sounds for continuous testing
            SpawnMoreThunderSounds();
        }
    }

    UFUNCTION(BlueprintOverride)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        StopConcurrencyTest();
    }

        void StartConcurrencyTest()
    {
        IsStationActive = true;
        UpdateVisualFeedback(true);

        // Spawn initial sounds to test concurrency
        SpawnInitialThunderSounds();

        // Start continuous spawning timer
        StartContinuousSpawning();

        Print("🎵 Concurrency Test Started - Walk in/out to spawn more", 3.0f);
        Print("📊 Max Concurrent: 5 | Walk in/out for more sounds", 2.0f);
    }

        void StopConcurrencyTest()
    {
        IsStationActive = false;
        UpdateVisualFeedback(false);

        // Stop continuous spawning timer
        StopContinuousSpawning();

        // Stop all active audio cues
        StopAllActiveSounds();

        Print("🔇 Concurrency Test Stopped", 2.0f);
    }

    void SpawnInitialThunderSounds()
    {
        // Spawn initial thunder sounds to test concurrency
        for (int32 i = 0; i < 2; i++)
        {
            SpawnThunderSound();
        }
    }

    void SpawnMoreThunderSounds()
    {
        // Spawn 1-2 more thunder sounds when player re-enters
        for (int32 i = 0; i < 2; i++)
        {
            SpawnThunderSound();
        }
        Print("🔄 Spawned more thunder sounds!", 2.0f);
    }

    void StartContinuousSpawning()
    {
        // For now, just spawn initial sounds
        // Continuous spawning can be triggered manually or through other means
        Print("🔄 Continuous spawning ready - spawn more by re-entering", 2.0f);
    }

    void StopContinuousSpawning()
    {
        // Stop any spawning activity
        Print("⏹️ Continuous spawning stopped", 1.0f);
    }

    void SpawnThunderSound()
    {
        // Check if we can play more sounds
        if (ActiveAudioCues.Num() < MaxConcurrentSounds)
        {
            // Execute a new thunder audio cue with proper transform
            auto SelfEntity = ck::SelfEntity(this);

            // Create spawn params with the station's transform
            auto SpawnParams = FCkAudioGym_Advanced_AudioCue_SpawnParams();
            SpawnParams.Transform = Transform; // Use the station's transform

            auto Str = FInstancedStruct();
            Str.InitializeAs(SpawnParams);
            auto PendingEntityScript = utils_cue::Request_Execute_Local(SelfEntity, AudioCueTag, Str);

            PendingEntityScript.Promise_OnConstructed(FCk_Delegate_EntityScript_Constructed(this, n"OnThunderSoundComplete"));

            Print("⚡ Thunder sound spawned", 1.0f);
        }
        else
        {
            Print("🚫 Max concurrent sounds reached", 2.0f);
        }
    }

        UFUNCTION()
    private void OnThunderSoundComplete(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        auto Entity = InEntityScriptHandle;
        auto AudioCue = Entity.H().To_FCk_Handle_AudioCue();

        if (ck::IsValid(AudioCue))
        {
            // Add to active cues list
            ActiveAudioCues.Add(AudioCue);

            Print("⚡ Thunder spawned", 1.0f);
        }
    }



    void StopAllActiveSounds()
    {
        // Stop all currently playing sounds
        for (auto AudioCue : ActiveAudioCues)
        {
            if (ck::IsValid(AudioCue))
            {
                utils_audio_cue::Request_StopAll(AudioCue, FCk_Time(0.2f));
            }
        }

        ActiveAudioCues.Empty();
        Print("🔇 All active sounds stopped", 2.0f);
    }

    // Override visual feedback to show concurrency status
    void UpdateVisualFeedback(bool bIsAudioPlaying)
    {
        if (bIsAudioPlaying)
        {
            Print("🎵 Concurrency Test Active", 2.0f);
        }
        else
        {
            Print("🔇 Concurrency Test Inactive", 2.0f);
        }
    }
}
