namespace ck
{
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
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX", ECk_AssetSearchScope::Plugins)._Asset));
    InterfaceStinger._Volume = 0.8f;
    InterfaceStinger._Priority = 50;
    InterfaceStinger._Cooldown = 0.1f;
    InterfaceStinger._IsSpatial = false;
    InterfaceStinger._DefaultFadeInTime = FCk_Time(0.1f);
    InterfaceStinger._DefaultFadeOutTime = FCk_Time(0.1f);
    Stingers.Add(InterfaceStinger);

    // Level up stinger (higher priority)
    auto LevelUpStinger = FCk_StingerEntry(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.LevelUp"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_LevelUp_SFX.Stinger_LevelUp_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    LevelUpStinger._Volume = 1.0f;
    LevelUpStinger._Priority = 70;
    LevelUpStinger._Cooldown = 0.5f;  // Longer cooldown for celebration sound
    LevelUpStinger._IsSpatial = true;
    LevelUpStinger._DefaultFadeInTime = FCk_Time(0.1f);
    LevelUpStinger._DefaultFadeOutTime = FCk_Time(0.1f);
    Stingers.Add(LevelUpStinger);

    // Notification stinger
    auto NotificationStinger = FCk_StingerEntry(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Notification"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Notifications_SFX.Stinger_Notifications_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    NotificationStinger._Volume = 0.7f;
    NotificationStinger._Priority = 40;
    NotificationStinger._Cooldown = 0.2f;
    NotificationStinger._IsSpatial = true;
    NotificationStinger._DefaultFadeInTime = FCk_Time(0.1f);
    NotificationStinger._DefaultFadeOutTime = FCk_Time(0.1f);
    Stingers.Add(NotificationStinger);

    // Thunder stinger (long, dramatic - lowest priority to avoid interrupting)
    auto ThunderStinger = FCk_StingerEntry(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Thunder"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    ThunderStinger._Volume = 0.9f;
    ThunderStinger._Priority = 30;  // Lower priority since it's long
    ThunderStinger._Cooldown = 2.0f;  // Much longer cooldown for dramatic effect
    ThunderStinger._IsSpatial = true;
    ThunderStinger._DefaultFadeInTime = FCk_Time(0.1f);
    ThunderStinger._DefaultFadeOutTime = FCk_Time(0.1f);
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

asset Asset_SoundAttenuation of USoundAttenuation
{
}

asset Asset_SoundConcurrency of USoundConcurrency
{
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

    _DefaultAttenuationSettings = Asset_SoundAttenuation;
    _DefaultConcurrencySettings = Asset_SoundConcurrency;
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

    _DefaultAttenuationSettings = Asset_SoundAttenuation;
    _DefaultConcurrencySettings = Asset_SoundConcurrency;
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

    _DefaultAttenuationSettings = Asset_SoundAttenuation;
    _DefaultConcurrencySettings = Asset_SoundConcurrency;
}

// Stinger Library
asset Asset_StingerLibrary of UCk_StingerLibrary_Base
{
    _LibraryName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI");
    _MaxConcurrent = 4;
    _VoiceStealing = ECk_SFXVoiceStealingMode::KillLowestPriority;
    _Stingers = Get_StingerEntries();

    _DefaultAttenuationSettings = Asset_SoundAttenuation;
    _DefaultConcurrencySettings = Asset_SoundConcurrency;
}
}