// Global functions for asset initialization
TArray<FCk_MusicTrackEntry> Get_AmbientTracks()
{
    TArray<FCk_MusicTrackEntry> Tracks;

    auto Track1 = FCk_MusicTrackEntry(Cast<USoundBase>(
        utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track1._Volume = 0.8f;
    Track1._Weight = 1.0f;
    Tracks.Add(Track1);

    auto Track2 = FCk_MusicTrackEntry(Cast<USoundBase>(
        utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Kids_SFX.Ambient_Kids_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track2._Volume = 0.8f;
    Track2._Weight = 1.0f;
    Tracks.Add(Track2);

    auto Track3 = FCk_MusicTrackEntry(Cast<USoundBase>(
        utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Retro_SFX.Ambient_Retro_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track3._Volume = 0.8f;
    Track3._Weight = 1.0f;
    Tracks.Add(Track3);

    return Tracks;
}

TArray<FCk_MusicTrackEntry> Get_CombatTracks()
{
    TArray<FCk_MusicTrackEntry> Tracks;

    // Reuse ambient tracks for combat (higher volume/intensity)
    auto Track1 = FCk_MusicTrackEntry(Cast<USoundBase>(
        utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track1._Volume = 1.0f;  // Louder for combat
    Track1._Weight = 1.0f;
    Tracks.Add(Track1);

    return Tracks;
}

TArray<FCk_MusicTrackEntry> Get_ActivityTracks()
{
    TArray<FCk_MusicTrackEntry> Tracks;

    // Use kids theme for activity
    auto Track1 = FCk_MusicTrackEntry(Cast<USoundBase>(
        utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Kids_SFX.Ambient_Kids_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track1._Volume = 0.85f;
    Track1._Weight = 1.0f;
    Tracks.Add(Track1);

    return Tracks;
}

TArray<FCk_StingerEntry> Get_StingerEntries()
{
    TArray<FCk_StingerEntry> Stingers;

    // Interface stinger (default pickup)
    auto InterfaceStinger = FCk_StingerEntry(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Interface"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    InterfaceStinger._Volume = 0.8f;
    InterfaceStinger._Priority = 50;
    InterfaceStinger._Cooldown = 0.1f;
    InterfaceStinger._SameSourceBehavior = ECk_SFXSameSourceBehavior::KillOldest;
    Stingers.Add(InterfaceStinger);

    // Level up stinger (higher priority)
    auto LevelUpStinger = FCk_StingerEntry(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.LevelUp"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_LevelUp_SFX.Stinger_LevelUp_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    LevelUpStinger._Volume = 1.0f;
    LevelUpStinger._Priority = 70;
    LevelUpStinger._Cooldown = 0.5f;  // Longer cooldown for celebration sound
    Stingers.Add(LevelUpStinger);

    // Notification stinger
    auto NotificationStinger = FCk_StingerEntry(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Notification"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Notifications_SFX.Stinger_Notifications_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    NotificationStinger._Volume = 0.7f;
    NotificationStinger._Priority = 40;
    NotificationStinger._Cooldown = 0.2f;
    Stingers.Add(NotificationStinger);

    // Thunder stinger (long, dramatic - lowest priority to avoid interrupting)
    auto ThunderStinger = FCk_StingerEntry(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Thunder"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    ThunderStinger._Volume = 0.9f;
    ThunderStinger._Priority = 30;  // Lower priority since it's long
    ThunderStinger._Cooldown = 2.0f;  // Much longer cooldown for dramatic effect
    ThunderStinger._SameSourceBehavior = ECk_SFXSameSourceBehavior::Ignore;  // Don't interrupt existing thunder
    Stingers.Add(ThunderStinger);

    return Stingers;
}

TArray<TObjectPtr<UCk_MusicLibrary_Base>> Get_MusicLibraries()
{
    TArray<TObjectPtr<UCk_MusicLibrary_Base>> Libraries;
    Libraries.Add(Asset_AmbientMusicLibrary);
    Libraries.Add(Asset_CombatMusicLibrary);
    Libraries.Add(Asset_ActivityMusicLibrary);
    return Libraries;
}

TArray<TObjectPtr<UCk_StingerLibrary_Base>> Get_StingerLibraries()
{
    TArray<TObjectPtr<UCk_StingerLibrary_Base>> Libraries;
    Libraries.Add(Asset_StingerLibrary);
    return Libraries;
}

// Main Audio Director Config
asset Asset_AudioGymConfig of UCk_AudioDirector_Config
{
    _DefaultCrossfadeDuration = 2.0f;
    _MaxConcurrentTracks = 6;
    _AllowSamePriorityTracks = false;
    _MusicLibraries = Get_MusicLibraries();
    _StingerLibraries = Get_StingerLibraries();
}

// Ambient Music Library
asset Asset_AmbientMusicLibrary of UCk_MusicLibrary_Base
{
    _LibraryName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient");
    _Priority = 10;
    _OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    _DefaultFadeInTime = FCk_Time(3.0f);
    _DefaultFadeOutTime = FCk_Time(2.0f);
    _Loop = true;
    _SelectionMode = ECk_MusicSelectionMode::Random;
    _Tracks = Get_AmbientTracks();
}

// Combat Music Library
asset Asset_CombatMusicLibrary of UCk_MusicLibrary_Base
{
    _LibraryName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat");
    _Priority = 100;
    _OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    _DefaultFadeInTime = FCk_Time(1.0f);
    _DefaultFadeOutTime = FCk_Time(1.0f);
    _Loop = true;
    _SelectionMode = ECk_MusicSelectionMode::Random;
    _Tracks = Get_CombatTracks();
}

// Activity Music Library
asset Asset_ActivityMusicLibrary of UCk_MusicLibrary_Base
{
    _LibraryName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Activity");
    _Priority = 90;
    _OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    _DefaultFadeInTime = FCk_Time(1.5f);
    _DefaultFadeOutTime = FCk_Time(1.5f);
    _Loop = true;
    _SelectionMode = ECk_MusicSelectionMode::Random;
    _Tracks = Get_ActivityTracks();
}

// Stinger Library
asset Asset_StingerLibrary of UCk_StingerLibrary_Base
{
    _LibraryName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI");
    _MaxConcurrent = 4;
    _VoiceStealing = ECk_SFXVoiceStealingMode::KillLowestPriority;
    _Stingers = Get_StingerEntries();
}




























class ACk_AudioGym_PlayerController : ACk_PlayerController_UE
{
    UPROPERTY()
    FCk_Handle_AudioDirector AudioDirector;

    UPROPERTY()
    UCk_MusicLibrary_Base AmbientMusicLibrary;
    default AmbientMusicLibrary = Asset_AmbientMusicLibrary;

    UPROPERTY()
    UCk_MusicLibrary_Base CombatMusicLibrary;
    default CombatMusicLibrary = Asset_CombatMusicLibrary;

    UPROPERTY()
    UCk_MusicLibrary_Base ActivityMusicLibrary;
    default ActivityMusicLibrary = Asset_ActivityMusicLibrary;

    UPROPERTY()
    UCk_StingerLibrary_Base StingerLibrary;
    default StingerLibrary = Asset_StingerLibrary;

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
        SpawnDebugDisplay();
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
        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.AddActiveTrack(f"STARTED: {InTrackName.ToString()}");
        }
        Print(f"🎵 Track Started: {InTrackName.ToString()}", 3.0f);
    }

    UFUNCTION()
    void OnTrackStopped(FCk_Handle_AudioDirector InDirector, FGameplayTag InTrackName, FCk_Handle_AudioTrack InTrack)
    {
        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.RemoveActiveTrack(InTrackName.ToString());
        }
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
        SpawnActor(ACk_AudioGym_AmbientZone, FVector(0, 0, 0));
        SpawnActor(ACk_AudioGym_CombatZone, FVector(1000, 0, 0));
        SpawnActor(ACk_AudioGym_ActivityZone, FVector(-1000, 0, 0));
        SpawnActor(ACk_AudioGym_QuietZone, FVector(0, 1000, 0));

        SpawnActor(ACk_AudioGym_MovingAudioSource, FVector(0, -500, 100));

        for (int32 i = 0; i < 8; i++)
        {
            auto Angle = (i / 8.0f) * 2.0f * PI;
            auto Location = FVector(Math::Cos(Angle) * 800, Math::Sin(Angle) * 800, 50);
            SpawnActor(ACk_AudioGym_StingerPickup, Location);
        }

        SpawnActor(ACk_AudioGym_ControlPanel, FVector(0, -1500, 0));
    }

    void SpawnDebugDisplay()
    {
        DebugDisplay = Cast<ACk_AudioGym_DebugDisplay>(
            SpawnActor(ACk_AudioGym_DebugDisplay, FVector(0, 0, 300)));
    }

    UFUNCTION()
    void OnEnteredZone(const FString& ZoneName, FGameplayTag MusicTag)
    {
        CurrentZone = ZoneName;
        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateZone(ZoneName);
        }

        if (MusicTag.IsValid())
        {
            utils_audio_director::Request_StartMusicLibrary(AudioDirector, MusicTag,
                TOptional<int32>(), FCk_Time(2.0f));
            CurrentMusicTrack = MusicTag.ToString();
            if (ck::IsValid(DebugDisplay))
            {
                DebugDisplay.UpdateMusic(CurrentMusicTrack);
            }
        }
    }

    UFUNCTION()
    void OnExitedZone(const FString& ZoneName)
    {
        if (CurrentZone == ZoneName)
        {
            CurrentZone = "None";
            if (ck::IsValid(DebugDisplay))
            {
                DebugDisplay.UpdateZone("None");
            }
            StopAllMusic();
        }
    }

    UFUNCTION()
    void OnStingerTriggered(FGameplayTag StingerTag)
    {
        if (ck::IsValid(StingerLibrary))
        {
            UCk_Utils_AudioDirector_UE::Request_PlayStinger(AudioDirector, StingerTag, TOptional<float32>());
            if (ck::IsValid(DebugDisplay))
            {
                DebugDisplay.UpdateStinger(StingerTag.ToString());
            }
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

    UFUNCTION(Exec, DisplayName="AudioGym - Stop All Music")
    void StopAllMusic()
    {
        utils_audio_director::Request_StopAllTracks(AudioDirector, FCk_Time(2.0f));
        CurrentMusicTrack = "None";
        if (ck::IsValid(DebugDisplay))
        {
            DebugDisplay.UpdateMusic("None");
        }
    }

    UFUNCTION(Exec, DisplayName="AudioGym - Play Test Stinger")
    void PlayTestStinger()
    {
        OnStingerTriggered(utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Interface"));
    }
};