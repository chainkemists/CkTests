class ACk_AudioGym_PlayerController : ACk_PlayerController_UE
{
    UPROPERTY()
    FCk_Handle_AudioDirector AudioDirector;

    UPROPERTY()
    UCk_MusicLibrary_Base AmbientMusicLibrary;
    default AmbientMusicLibrary = ck::Asset_AmbientMusicLibrary;

    UPROPERTY()
    UCk_MusicLibrary_Base CombatMusicLibrary;
    default CombatMusicLibrary = ck::Asset_CombatMusicLibrary;

    UPROPERTY()
    UCk_MusicLibrary_Base ActivityMusicLibrary;
    default ActivityMusicLibrary = ck::Asset_ActivityMusicLibrary;

    UPROPERTY()
    UCk_StingerLibrary_Base StingerLibrary;
    default StingerLibrary = ck::Asset_StingerLibrary;

    UPROPERTY()
    FString CurrentMusicTrack = "None";
    UPROPERTY()
    FString CurrentZone = "None";
    UPROPERTY()
    ACk_AudioGym_DebugDisplay DebugDisplay;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        SetupAudioDirector();
        LoadAudioLibraries();
        SpawnGymElements();
    }

    void SetupAudioDirector()
    {
        auto NewEntity = utils_entity_lifetime::Request_CreateEntity_TransientOwner();

        auto DirectorParams = FCk_Fragment_AudioDirector_ParamsData();
        DirectorParams._DefaultCrossfadeDuration = FCk_Time(2.0f);
        DirectorParams._MaxConcurrentTracks = 6;

        AudioDirector = utils_audio_director::Add(NewEntity, DirectorParams);

        utils_audio_director::BindTo_OnTrackStarted(AudioDirector,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_AudioDirector_Track(this, n"OnTrackStarted"));

        utils_audio_director::BindTo_OnTrackStopped(AudioDirector,
            ECk_Signal_BindingPolicy::FireIfPayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing,
            FCk_Delegate_AudioDirector_Track(this, n"OnTrackStopped"));
    }

    UFUNCTION()
    void OnTrackStarted(FCk_Handle_AudioDirector InDirector, FGameplayTag InTrackName, FCk_Handle_AudioTrack InTrack)
    {
        Print(f"🎵 Track Started: {InTrackName.ToString()}", 3.0f);
    }

    UFUNCTION()
    void OnTrackStopped(FCk_Handle_AudioDirector InDirector, FGameplayTag InTrackName, FCk_Handle_AudioTrack InTrack)
    {
        Print(f"🛑 Track Stopped: {InTrackName.ToString()}", 3.0f);
    }

    void LoadAudioLibraries()
    {
        // Add to director
        if (ck::IsValid(AmbientMusicLibrary))
            utils_audio_director::Request_AddMusicLibrary(AudioDirector, AmbientMusicLibrary);
        if (ck::IsValid(CombatMusicLibrary))
            utils_audio_director::Request_AddMusicLibrary(AudioDirector, CombatMusicLibrary);
        if (ck::IsValid(ActivityMusicLibrary))
            utils_audio_director::Request_AddMusicLibrary(AudioDirector, ActivityMusicLibrary);
        if (ck::IsValid(StingerLibrary))
            utils_audio_director::Request_AddStingerLibrary(AudioDirector, StingerLibrary);
    }

    void SpawnGymElements()
    {
        // Create 4 separate booths in corners of a square
        // Each booth is 800x800, with 1000 units between centers

        // Booth 1: Ambient Zone (Top-Left)
        SpawnActor(ACk_AudioGym_AmbientZone, FVector(-1000, -1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-1000, -800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-800, -1000, 50));
        SpawnBoothLabel("AMBIENT MUSIC\nLow Priority (10)\nCrossfade Transitions\n\nCollect stingers to test UI sounds",
            FVector(-1000, -1000, 200), FLinearColor(0.0f, 0.0f, 1.0f));

        // Booth 2: Combat Zone (Top-Right)
        SpawnActor(ACk_AudioGym_CombatZone, FVector(1000, -1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(1000, -800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(800, -1000, 50));
        SpawnBoothLabel("COMBAT MUSIC\nHigh Priority (100)\nOverrides other music\n\nFast transitions",
            FVector(1000, -1000, 200), FLinearColor(1.0f, 0.0f, 0.0f));

        // Booth 3: Activity Zone (Bottom-Left)
        SpawnActor(ACk_AudioGym_ActivityZone, FVector(-1000, 1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-1000, 800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-800, 1000, 50));
        SpawnBoothLabel("ACTIVITY MUSIC\nMedium Priority (90)\nSmooth crossfades\n\nBalanced volume",
            FVector(-1000, 1000, 200), FLinearColor(1.0f, 1.0f, 0.0f));

        // Booth 4: Quiet Zone (Bottom-Right)
        SpawnActor(ACk_AudioGym_QuietZone, FVector(1000, 1000, 0));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(1000, 800, 50));
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(800, 1000, 50));
        SpawnBoothLabel("QUIET ZONE\nStops all music\nSilence for testing\n\nEnter to mute audio",
            FVector(1000, 1000, 200), FLinearColor(0.0f, 1.0f, 0.0f));

        // Center area: Controls and spatial audio
        SpawnActor(ACk_AudioGym_ControlPanel, FVector(0, 0, 0));
        SpawnActor(ACk_AudioGym_MovingAudioSource, FVector(0, -300, 100));
        SpawnBoothLabel("CONTROL PANEL\nWalk into to cycle options\nManual audio testing",
            FVector(0, 0, 100), FLinearColor(1.0f, 0.0f, 1.0f));
        SpawnBoothLabel("3D SPATIAL AUDIO\nOrbiting sound source\nTest 3D positioning",
            FVector(0, -300, 200), FLinearColor(1.0f, 0.65f, 0.0f));

        // Pathway stingers between booths
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(0, -1000, 50));  // Top center
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(0, 1000, 50));   // Bottom center
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(-1000, 0, 50));  // Left center
        SpawnActor(ACk_AudioGym_StingerPickup, FVector(1000, 0, 50));   // Right center
    }

    void SpawnBoothLabel(const FString& Text, FVector Location, FLinearColor Color)
    {
        auto TextActor = Cast<ATextRenderActor>(SpawnActor(ATextRenderActor, Location));
        if (ck::IsValid(TextActor))
        {
            auto TextComponent = TextActor.TextRender;
            if (ck::IsValid(TextComponent))
            {
                TextComponent.Text = ck::Text(Text);
                TextComponent.TextRenderColor = Color.ToFColor(true);
                TextComponent.HorizontalAlignment = EHorizTextAligment::EHTA_Center;
                TextComponent.VerticalAlignment = EVerticalTextAligment::EVRTA_TextCenter;
                TextComponent.SetWorldSize(48.0f);
            }
        }
    }

    UFUNCTION()
    void OnEnteredZone(const FString& ZoneName, FGameplayTag MusicTag)
    {
        CurrentZone = ZoneName;
        ck::Trace(f"Zone: {ZoneName}", n"AudioGym_Zone", 0.0f, FLinearColor(1.0f, 1.0f, 0.0f));

        if (MusicTag.IsValid())
        {
            utils_audio_director::Request_StartMusicLibrary(AudioDirector, MusicTag,
                TOptional<int32>(), FCk_Time(2.0f));
            CurrentMusicTrack = MusicTag.ToString();
            ck::Trace(f"Music: {CurrentMusicTrack}", n"AudioGym_Music", 0.0f, FLinearColor(0.0f, 1.0f, 1.0f));
        }
    }

    void OnExitedZone(const FString& ZoneName)
    {
        if (CurrentZone == ZoneName)
        {
            CurrentZone = "None";
            ck::Trace("Zone: None", n"AudioGym_Zone", 0.0f, FLinearColor(0.5f, 0.5f, 0.5f));
            StopAllMusic();
        }
    }

    UFUNCTION()
    void OnStingerTriggered(FGameplayTag StingerTag)
    {
        if (ck::IsValid(StingerLibrary))
        {
            utils_audio_director::Request_PlayStinger(AudioDirector, StingerTag, TOptional<float32>());
            ck::Trace(f"Stinger: {StingerTag.ToString()}", n"AudioGym_Stinger", 3.0f, FLinearColor(1.0f, 0.5f, 0.0f));
        }
    }

    void StartAmbientMusic()
    {
        if (ck::IsValid(AmbientMusicLibrary))
        {
            utils_audio_director::Request_StartMusicLibrary(AudioDirector,
                utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient"),
                TOptional<int32>(), FCk_Time(3.0f));
            CurrentMusicTrack = "Ambient";
            if (ck::IsValid(DebugDisplay))
            {
                DebugDisplay.UpdateMusic("Ambient");
            }
        }
    }

    UFUNCTION(Exec, DisplayName="AudioGym - Start Combat Music")
    void StartCombatMusic()
    {
        if (ck::IsValid(CombatMusicLibrary))
        {
            utils_audio_director::Request_StartMusicLibrary(AudioDirector,
                utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat"),
                TOptional<int32>(), FCk_Time(1.0f));
            CurrentMusicTrack = "Combat";
            if (ck::IsValid(DebugDisplay))
            {
                DebugDisplay.UpdateMusic("Combat");
            }
        }
    }

    void StopAllMusic()
    {
        utils_audio_director::Request_StopAllTracks(AudioDirector, FCk_Time(2.0f));
        CurrentMusicTrack = "None";
        ck::Trace("Music: None", n"AudioGym_Music", 0.0f, FLinearColor(0.5f, 0.5f, 0.5f));
    }

    UFUNCTION(Exec, DisplayName="AudioGym - Play Test Stinger")
    void PlayTestStinger()
    {
        OnStingerTriggered(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Interface"));
    }
};