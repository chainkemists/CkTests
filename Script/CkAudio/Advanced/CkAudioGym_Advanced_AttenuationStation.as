class UCkAudioGym_Advanced_AttenuationStation : UCkAudioGym_Advanced_Base
{
    // Attenuation testing specific properties
    UPROPERTY()
    FGameplayTag MusicTrackTag;

    UPROPERTY()
    FGameplayTag AmbientTrackTag;

    UPROPERTY()
    TArray<FVector> AttenuationTestZones;

    UPROPERTY()
    TArray<FString> AttenuationZoneNames;

    UPROPERTY()
    int32 CurrentZoneIndex = -1;

    UPROPERTY()
    bool IsPlayingAttenuationTest = false;

    // Zone marker visuals
    TArray<FCk_Handle_IsmProxy> ZoneMarkers;

    // Override DoConstruct to set up attenuation audio station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        // Configure station properties
        StationName = "ATTENUATION STATION";
        StationDescription = "Walk between zones to hear volume and frequency changes";
        StationThemeColor = FLinearColor(0.0f, 1.0f, 0.5f, 1.0f); // Green-blue for attenuation
        StationBounds = FVector(1200, 800, 400); // Large elongated area for distance testing

        // Configure AudioDirector for attenuation testing
        AudioDirectorParams._DefaultCrossfadeDuration = FCk_Time(2.0f); // Longer crossfades for smooth transitions
        AudioDirectorParams._MaxConcurrentTracks = 3; // Ambient + music + occasional effects
        AudioDirectorParams._SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

        // Setup attenuation test zones
        SetupAttenuationZones();

        // Configure track tags
        MusicTrackTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Attenuation.Music");
        AmbientTrackTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Attenuation.Ambient");

        // Call parent construction
        auto Result = Super::DoConstruct(InHandle);

        // Add audio tracks to director
        SetupAttenuationAudioTracks();

        // Create visual zone markers
        CreateZoneMarkers(InHandle);

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Attenuation"));

        return Result;
    }

    void SetupAttenuationZones()
    {
        auto StationCenter = Transform.GetLocation();

        AttenuationTestZones.Empty();
        AttenuationZoneNames.Empty();

        // Create zones at different distances from audio source
        // Zone 1: Very close (should be loud and full frequency)
        AttenuationTestZones.Add(StationCenter + FVector(100, 0, 0));
        AttenuationZoneNames.Add("CLOSE ZONE (100 units)");

        // Zone 2: Medium distance (moderate volume, some HF loss)
        AttenuationTestZones.Add(StationCenter + FVector(400, 0, 0));
        AttenuationZoneNames.Add("MEDIUM ZONE (400 units)");

        // Zone 3: Far distance (quiet, significant HF rolloff)
        AttenuationTestZones.Add(StationCenter + FVector(800, 0, 0));
        AttenuationZoneNames.Add("FAR ZONE (800 units)");

        // Zone 4: Very far (barely audible, heavy filtering)
        AttenuationTestZones.Add(StationCenter + FVector(1200, 0, 0));
        AttenuationZoneNames.Add("EXTREME ZONE (1200 units)");

        ck::Trace(f"Attenuation Station: {AttenuationTestZones.Num()} test zones configured", NAME_None, 2.0f, StationThemeColor);
    }

    void SetupAttenuationAudioTracks()
    {
        if (ck::IsValid(AudioDirector) == false)
        {
            ck::Trace("AudioDirector NOT valid - cannot setup attenuation tracks", NAME_None, 3.0f, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
            return;
        }

        // Add continuous music track for attenuation testing
        auto MusicTrackParams = FCk_Fragment_AudioTrack_ParamsData(
            MusicTrackTag,
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        MusicTrackParams._Priority = 40;
        MusicTrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
        MusicTrackParams._LoopBehavior = ECk_LoopBehavior::Loop;
        MusicTrackParams._Volume = 0.8f;
        MusicTrackParams._DefaultFadeInTime = FCk_Time(2.0f);
        MusicTrackParams._DefaultFadeOutTime = FCk_Time(2.0f);

        // Use advanced attenuation settings
        MusicTrackParams._LibraryAttenuationSettings = Cast<USoundAttenuation>(utils_i_o::LoadAssetByName("Asset_SoundAttenuation_Advanced", ECk_AssetSearchScope::Plugins)._Asset);

        utils_audio_director::Request_AddTrack(AudioDirector, MusicTrackParams);

        // Add ambient background for layered attenuation testing
        auto AmbientTrackParams = FCk_Fragment_AudioTrack_ParamsData(
            AmbientTrackTag,
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        AmbientTrackParams._Priority = 20; // Lower priority background
        AmbientTrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
        AmbientTrackParams._LoopBehavior = ECk_LoopBehavior::Loop;
        AmbientTrackParams._Volume = 0.5f;
        AmbientTrackParams._DefaultFadeInTime = FCk_Time(3.0f);
        AmbientTrackParams._DefaultFadeOutTime = FCk_Time(3.0f);
        AmbientTrackParams._LibraryAttenuationSettings = Cast<USoundAttenuation>(utils_i_o::LoadAssetByName("Asset_SoundAttenuation_Advanced", ECk_AssetSearchScope::Plugins)._Asset);

        utils_audio_director::Request_AddTrack(AudioDirector, AmbientTrackParams);

        ck::Trace("Attenuation Station: Audio tracks configured with advanced spatial settings", NAME_None, 2.0f, ActiveColor);
    }

    void CreateZoneMarkers(FCk_Handle& InHandle)
    {
        ZoneMarkers.Empty();

        for (int32 i = 0; i < AttenuationTestZones.Num(); i++)
        {
            auto MarkerParams = FCk_Fragment_IsmProxy_ParamsData(ck::Asset_StationMarker);
            MarkerParams._ScaleMultiplier = FVector(0.4f, 0.4f, 0.4f);

            // Color code markers by distance (green = close, red = far)
            auto DistanceRatio = float(i) / float(AttenuationTestZones.Num() - 1);

            // TODO: Position markers at AttenuationTestZones[i]
            auto Marker = utils_ism_proxy::Add(InHandle, MarkerParams);
            ZoneMarkers.Add(Marker);
        }
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        Super::OnPlayerEnteredStation(InProbe, InOverlapInfo);

        StartAttenuationTest();
    }

    UFUNCTION(BlueprintOverride)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        Super::OnPlayerExitedStation(InProbe, InOverlapInfo);

        StopAttenuationTest();
    }

    void StartAttenuationTest()
    {
        ck::Trace("Attenuation Test Started", NAME_None, 3.0f, ActiveColor);
        ck::Trace("Walk between the colored zone markers to hear volume changes", NAME_None, 3.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("Listen for both volume reduction AND frequency filtering", NAME_None, 3.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));

        IsPlayingAttenuationTest = true;

        // Start both music and ambient tracks for layered attenuation testing
        Request_StartTrack_WithParams(MusicTrackTag, 40, FCk_Time(2.0f));
        Request_StartTrack_WithParams(AmbientTrackTag, 20, FCk_Time(3.0f));

        DisplayAttenuationInstructions();
    }

    void StopAttenuationTest()
    {
        IsPlayingAttenuationTest = false;
        CurrentZoneIndex = -1;

        Request_StopAllTracks(FCk_Time(2.0f));

        ck::Trace("Attenuation Test Stopped", NAME_None, 2.0f, InactiveColor);
    }

    void DisplayAttenuationInstructions()
    {
        ck::Trace("ATTENUATION TEST ZONES:", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));

        for (int32 i = 0; i < AttenuationZoneNames.Num(); i++)
        {
            auto ZoneName = AttenuationZoneNames[i];
            auto ZonePosition = AttenuationTestZones[i];

            ck::Trace(f"Zone {i + 1}: {ZoneName}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
            ck::Trace(f"  Position: {ZonePosition.ToString()}", NAME_None, 1.5f, FLinearColor(0.5f, 0.5f, 0.5f, 1.0f));
        }

        ck::Trace("Advanced attenuation features active:", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Volume falloff based on distance", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Low-pass filtering (air absorption)", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Dynamic reverb wet level", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace("• Priority attenuation for culling", NAME_None, 1.5f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
    }

    // Zone detection and feedback
    void OnPlayerEnteredZone(int32 InZoneIndex)
    {
        if (IsPlayingAttenuationTest == false || InZoneIndex == CurrentZoneIndex)
        {
            return;
        }

        CurrentZoneIndex = InZoneIndex;

        if (InZoneIndex >= 0 && InZoneIndex < AttenuationZoneNames.Num())
        {
            auto ZoneName = AttenuationZoneNames[InZoneIndex];
            auto ZonePosition = AttenuationTestZones[InZoneIndex];

            ck::Trace(f"Entered {ZoneName}", NAME_None, 2.0f, ActiveColor);
            ck::Trace("Listen for volume and frequency changes", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));

            DisplayCurrentZoneStats(InZoneIndex);
        }
    }

    void DisplayCurrentZoneStats(int32 InZoneIndex)
    {
        auto AudioSourcePosition = Transform.GetLocation(); // Station center is audio source
        auto PlayerZonePosition = AttenuationTestZones[InZoneIndex];
        auto Distance = Math::Sqrt(
            Math::Pow(AudioSourcePosition.X - PlayerZonePosition.X, 2) +
            Math::Pow(AudioSourcePosition.Y - PlayerZonePosition.Y, 2) +
            Math::Pow(AudioSourcePosition.Z - PlayerZonePosition.Z, 2));

        ck::Trace("ZONE AUDIO ANALYSIS:", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
        ck::Trace(f"Distance from source: {int32(Distance)} units", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Active tracks: {Get_ActiveTrackCount()}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));
        ck::Trace(f"Highest priority: {Get_CurrentHighestPriority()}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 1.0f, 1.0f));

        // Provide expected audio characteristics for this distance
        if (Distance < 200)
        {
            ck::Trace("Expected: Full volume, full frequency range", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 0.0f, 1.0f));
        }
        else if (Distance < 500)
        {
            ck::Trace("Expected: Moderate volume, slight HF rolloff", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
        }
        else if (Distance < 1000)
        {
            ck::Trace("Expected: Reduced volume, noticeable filtering", NAME_None, 2.0f, FLinearColor(1.0f, 0.5f, 0.0f, 1.0f));
        }
        else
        {
            ck::Trace("Expected: Very quiet, heavy filtering, reverb", NAME_None, 2.0f, FLinearColor(1.0f, 0.0f, 0.0f, 1.0f));
        }
    }

    // Public interface for zone testing
    UFUNCTION()
    void TriggerZoneTest(int32 InZoneIndex)
    {
        OnPlayerEnteredZone(InZoneIndex);
    }

    UFUNCTION()
    void CycleAttenuationDemo()
    {
        if (IsPlayingAttenuationTest == false)
        {
            return;
        }

        ck::Trace("Starting automatic attenuation demonstration", NAME_None, 3.0f, ActiveColor);

        // Demonstrate different attenuation effects by cycling through priorities
        for (int32 i = 0; i < 4; i++)
        {
            auto Priority = 30 + (i * 10);
            Request_StartTrack_WithParams(MusicTrackTag, Priority, FCk_Time(1.0f));

            ck::Trace(f"Attenuation demo step {i + 1}: Priority {Priority}", NAME_None, 2.0f, FLinearColor(1.0f, 1.0f, 0.0f, 1.0f));
        }
    }

    UFUNCTION()
    void TestCrossfadeAttenuation()
    {
        if (IsPlayingAttenuationTest == false)
        {
            return;
        }

        ck::Trace("Testing crossfade with attenuation", NAME_None, 2.0f, ActiveColor);

        // Stop current tracks and restart with crossfade to test interaction
        Request_StopTrack(MusicTrackTag, FCk_Time(1.0f));
        Request_StartTrack_WithParams(MusicTrackTag, 45, FCk_Time(2.0f));

        ck::Trace("Crossfade initiated - listen for smooth transition", NAME_None, 2.0f, FLinearColor(0.0f, 1.0f, 1.0f, 1.0f));
    }

    // Status reporting
    UFUNCTION()
    int32 Get_CurrentZoneIndex()
    {
        return CurrentZoneIndex;
    }

    UFUNCTION()
    FString Get_CurrentZoneName()
    {
        if (CurrentZoneIndex >= 0 && CurrentZoneIndex < AttenuationZoneNames.Num())
        {
            return AttenuationZoneNames[CurrentZoneIndex];
        }
        return "No Zone";
    }

    UFUNCTION()
    bool Get_IsAttenuationTestActive()
    {
        return IsPlayingAttenuationTest;
    }

    UFUNCTION()
    int32 Get_ConfiguredZoneCount()
    {
        return AttenuationTestZones.Num();
    }
}