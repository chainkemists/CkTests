// Basic Audio Station - Foundation for audio system testing
// Demonstrates simple track management and UI sound integration

class UCkAudioGym_Advanced_BasicStation : UCkAudioGym_Advanced_Base
{
    // Basic station specific properties
    UPROPERTY()
    FGameplayTag InterfaceTrackTag;

    UPROPERTY()
    FGameplayTag AchievementTrackTag;

    UPROPERTY()
    bool HasPlayedInterfaceSound = false;

    UPROPERTY()
    bool HasPlayedAchievementSound = false;

    // Override DoConstruct to configure basic audio station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Configure station properties
        StationName = "BASIC AUDIO STATION";
        StationDescription = "Learn fundamental audio playback - Interface and Achievement sounds";
        StationThemeColor = FLinearColor(0.2f, 0.8f, 0.2f, 1.0f); // Green for basic/beginner
        StationBounds = FVector(400, 400, 250); // Smaller, intimate space

        // Configure audio tracks
        InterfaceTrackTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Interface.Pickup");
        AchievementTrackTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Achievement.Fanfare");

        // Configure AudioDirector for basic usage
        AudioDirectorParams._DefaultCrossfadeDuration = FCk_Time(0.5f);
        AudioDirectorParams._MaxConcurrentTracks = 2;
        AudioDirectorParams._SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

        // Call parent construction
        Super::DoConstruct(InHandle);

        // Add audio tracks to director
        SetupAudioTracks();

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Basic"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    void SetupAudioTracks()
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            ck::Trace("AudioDirector NOT valid - cannot setup tracks", NAME_None, 3.0f, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
            return;
        }

        // Add Interface sound track
        auto InterfaceTrackParams = FCk_Fragment_AudioTrack_ParamsData(
            InterfaceTrackTag,
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        InterfaceTrackParams._Priority = 60;
        InterfaceTrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
        InterfaceTrackParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
        InterfaceTrackParams._Volume = 0.7f;
        InterfaceTrackParams._DefaultFadeInTime = FCk_Time(0.1f);
        InterfaceTrackParams._DefaultFadeOutTime = FCk_Time(0.2f);

        utils_audio_director::Request_AddTrack(AudioDirector, InterfaceTrackParams);

        // Add Achievement sound track
        auto AchievementTrackParams = FCk_Fragment_AudioTrack_ParamsData(
            AchievementTrackTag,
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        AchievementTrackParams._Priority = 80;
        AchievementTrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
        AchievementTrackParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
        AchievementTrackParams._Volume = 0.9f;
        AchievementTrackParams._DefaultFadeInTime = FCk_Time(0.0f);
        AchievementTrackParams._DefaultFadeOutTime = FCk_Time(0.3f);

        utils_audio_director::Request_AddTrack(AudioDirector, AchievementTrackParams);

        ck::Trace("Basic Audio Station: Tracks configured successfully", NAME_None, 2.0f, ActiveColor);
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        Super::OnPlayerEnteredStation(InProbe, InOverlapInfo);

        StartBasicAudioTest();
    }

    UFUNCTION(BlueprintOverride)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        Super::OnPlayerExitedStation(InProbe, InOverlapInfo);

        StopBasicAudioTest();
    }

    void StartBasicAudioTest()
    {
        ck::Trace("Basic Audio Test Started", NAME_None, 3.0f, ActiveColor);
        ck::Trace("Press [Space] to play Interface sound", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("Press [Enter] to play Achievement sound", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));

        // Play welcome interface sound
        Request_StartTrack_WithParams(InterfaceTrackTag, 60, FCk_Time(0.1f));
        HasPlayedInterfaceSound = true;

        UpdateTestProgress();
    }

    void StopBasicAudioTest()
    {
        Request_StopAllTracks(FCk_Time(0.5f));
        ck::Trace("Basic Audio Test Stopped", NAME_None, 2.0f, InactiveColor);

        // Reset progress
        HasPlayedInterfaceSound = false;
        HasPlayedAchievementSound = false;
        CurrentTestProgress = 0.0f;
    }

    void PlayInterfaceSound()
    {
        if (PlayerInside == false)
        {
            return;
        }

        Request_StartTrack_WithParams(InterfaceTrackTag, 60, FCk_Time(0.1f));
        HasPlayedInterfaceSound = true;

        ck::Trace("Interface sound triggered", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        UpdateTestProgress();
    }

    void PlayAchievementSound()
    {
        if (PlayerInside == false)
        {
            return;
        }

        Request_StartTrack_WithParams(AchievementTrackTag, 80, FCk_Time(0.0f));
        HasPlayedAchievementSound = true;

        ck::Trace("Achievement sound triggered", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
        UpdateTestProgress();

        // Check if test completed
        if (HasPlayedInterfaceSound && HasPlayedAchievementSound)
        {
            CompleteBasicTest();
        }
    }

    void UpdateTestProgress()
    {
        auto CompletedSteps = 0;
        if (HasPlayedInterfaceSound) CompletedSteps++;
        if (HasPlayedAchievementSound) CompletedSteps++;

        CurrentTestProgress = float(CompletedSteps) / 2.0f;

        auto ProgressPercent = int32(CurrentTestProgress * 100);
        ck::Trace(f"Test Progress: {ProgressPercent}%", NAME_None, 1.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
    }

    void CompleteBasicTest()
    {
        ck::Trace("BASIC AUDIO TEST COMPLETED!", NAME_None, 4.0f, ActiveColor);
        ck::Trace("You successfully triggered both audio types", NAME_None, 3.0f, FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));
        ck::Trace("AudioDirector Stats:", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Active Tracks: {Get_ActiveTrackCount()}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Highest Priority: {Get_CurrentHighestPriority()}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));

        // Play celebration sequence
        PlayCelebrationSequence();
    }

    void PlayCelebrationSequence()
    {
        // Quick sequence of achievement sounds to demonstrate priority
        Request_StartTrack_WithParams(AchievementTrackTag, 90, FCk_Time(0.0f));

        // TODO: In a real implementation, you'd use timers for sequencing
        // For now, just play the celebration sound
        ck::Trace("Celebration sequence triggered", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
    }

    // Public interface for external triggering (like input handling)
    UFUNCTION()
    void TriggerInterfaceSound()
    {
        PlayInterfaceSound();
    }

    UFUNCTION()
    void TriggerAchievementSound()
    {
        PlayAchievementSound();
    }

    // Status reporting
    UFUNCTION()
    bool Get_IsTestCompleted()
    {
        return HasPlayedInterfaceSound && HasPlayedAchievementSound;
    }

    UFUNCTION()
    float Get_TestProgress()
    {
        return CurrentTestProgress;
    }

    // Visual feedback override
    void UpdateStationVisualState()
    {
        Super::UpdateStationVisualState();

        // Additional visual feedback based on test progress
        if (Get_IsTestCompleted())
        {
            // Station completed - could update materials, etc.
            ck::Trace("Station Status: COMPLETED", NAME_None, 1.0f, ActiveColor);
        }
        else if (PlayerInside)
        {
            ck::Trace("Station Status: TESTING", NAME_None, 1.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
        }
    }
}