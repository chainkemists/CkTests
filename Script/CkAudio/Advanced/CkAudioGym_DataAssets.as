namespace ck
{
// Helper functions for creating track libraries
TArray<FCk_Fragment_AudioTrack_ParamsData> Get_AmbientTracks()
{
    TArray<FCk_Fragment_AudioTrack_ParamsData> Tracks;

    auto Track1 = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient.Track1"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track1._Volume = 0.8f;
    Track1._Priority = 10;
    Track1._Loop = true;
    Track1._DefaultFadeInTime = FCk_Time(3.0f);
    Track1._DefaultFadeOutTime = FCk_Time(2.0f);
    Track1._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    Tracks.Add(Track1);

    auto Track2 = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient.Track2"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Kids_SFX.Ambient_Kids_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track2._Volume = 0.8f;
    Track2._Priority = 10;
    Track2._Loop = true;
    Track2._DefaultFadeInTime = FCk_Time(3.0f);
    Track2._DefaultFadeOutTime = FCk_Time(2.0f);
    Track2._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    Tracks.Add(Track2);

    auto Track3 = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient.Track3"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Retro_SFX.Ambient_Retro_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track3._Volume = 0.8f;
    Track3._Priority = 10;
    Track3._Loop = true;
    Track3._DefaultFadeInTime = FCk_Time(3.0f);
    Track3._DefaultFadeOutTime = FCk_Time(2.0f);
    Track3._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    Tracks.Add(Track3);

    return Tracks;
}

TArray<FCk_Fragment_AudioTrack_ParamsData> Get_CombatTracks()
{
    TArray<FCk_Fragment_AudioTrack_ParamsData> Tracks;

    auto Track1 = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat.Track1"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track1._Volume = 1.0f;  // Louder for combat
    Track1._Priority = 100;  // High priority
    Track1._Loop = true;
    Track1._DefaultFadeInTime = FCk_Time(1.0f);
    Track1._DefaultFadeOutTime = FCk_Time(1.0f);
    Track1._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
    Tracks.Add(Track1);

    return Tracks;
}

TArray<FCk_Fragment_AudioTrack_ParamsData> Get_ActivityTracks()
{
    TArray<FCk_Fragment_AudioTrack_ParamsData> Tracks;

    auto Track1 = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Activity.Track1"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Kids_SFX.Ambient_Kids_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    Track1._Volume = 0.85f;
    Track1._Priority = 90;  // Medium priority
    Track1._Loop = true;
    Track1._DefaultFadeInTime = FCk_Time(1.5f);
    Track1._DefaultFadeOutTime = FCk_Time(1.5f);
    Track1._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    Tracks.Add(Track1);

    return Tracks;
}

// Stinger tracks for UI sounds
TArray<FCk_Fragment_AudioTrack_ParamsData> Get_StingerTracks()
{
    TArray<FCk_Fragment_AudioTrack_ParamsData> Stingers;

    // Interface stinger
    auto InterfaceStinger = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Interface"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    InterfaceStinger._Volume = 0.8f;
    InterfaceStinger._Priority = 50;
    InterfaceStinger._Loop = false;  // Stingers don't loop
    InterfaceStinger._IsSpatial = false;
    InterfaceStinger._DefaultFadeInTime = FCk_Time(0.1f);
    InterfaceStinger._DefaultFadeOutTime = FCk_Time(0.1f);
    InterfaceStinger._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
    Stingers.Add(InterfaceStinger);

    // Level up stinger
    auto LevelUpStinger = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.LevelUp"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_LevelUp_SFX.Stinger_LevelUp_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    LevelUpStinger._Volume = 1.0f;
    LevelUpStinger._Priority = 70;
    LevelUpStinger._Loop = false;
    LevelUpStinger._IsSpatial = true;
    LevelUpStinger._DefaultFadeInTime = FCk_Time(0.1f);
    LevelUpStinger._DefaultFadeOutTime = FCk_Time(0.1f);
    LevelUpStinger._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
    Stingers.Add(LevelUpStinger);

    // Notification stinger
    auto NotificationStinger = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Notification"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Notifications_SFX.Stinger_Notifications_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    NotificationStinger._Volume = 0.7f;
    NotificationStinger._Priority = 40;
    NotificationStinger._Loop = false;
    NotificationStinger._IsSpatial = true;
    NotificationStinger._DefaultFadeInTime = FCk_Time(0.1f);
    NotificationStinger._DefaultFadeOutTime = FCk_Time(0.1f);
    NotificationStinger._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Queue;
    Stingers.Add(NotificationStinger);

    // Thunder stinger
    auto ThunderStinger = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI.Thunder"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));
    ThunderStinger._Volume = 0.9f;
    ThunderStinger._Priority = 30;  // Lower priority since it's long
    ThunderStinger._Loop = false;
    ThunderStinger._IsSpatial = true;
    ThunderStinger._DefaultFadeInTime = FCk_Time(0.1f);
    ThunderStinger._DefaultFadeOutTime = FCk_Time(0.1f);
    ThunderStinger._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Queue;  // Don't interrupt existing thunder
    Stingers.Add(ThunderStinger);

    return Stingers;
}

asset Asset_SoundAttenuation of USoundAttenuation
{
}

asset Asset_SoundConcurrency of USoundConcurrency
{
}

// Ambient Music AudioCue (using library mode)
asset Asset_AmbientMusicCue of UCk_AudioCue_EntityScript
{
    _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Ambient");
    _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;

    _SourcePriority = ECk_AudioCue_SourcePriority::LibraryOnly;
    _TrackLibrary = Get_AmbientTracks();
    _SelectionMode = ECk_AudioCue_SelectionMode::Random;
    _RecentTrackAvoidanceTime = 300.0f; // 5 minutes

    _DefaultCrossfadeDuration = FCk_Time(2.0f);
    _MaxConcurrentTracks = 1;
    _AllowSamePriorityTracks = false;
}

// Combat Music AudioCue (using single track mode)
asset Asset_CombatMusicCue of UCk_AudioCue_EntityScript
{
    _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat");
    _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;

    _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Combat.Main"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));

    _DefaultCrossfadeDuration = FCk_Time(1.0f);
    _MaxConcurrentTracks = 1;
    _AllowSamePriorityTracks = false;
}

// Activity Music AudioCue (using single track mode)
asset Asset_ActivityMusicCue of UCk_AudioCue_EntityScript
{
    _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Activity");
    _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;

    _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Music.Activity.Main"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Kids_SFX.Ambient_Kids_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));

    _DefaultCrossfadeDuration = FCk_Time(1.5f);
    _MaxConcurrentTracks = 1;
    _AllowSamePriorityTracks = false;
}

// Stinger AudioCue (using library mode for variety)
asset Asset_StingerCue of UCk_AudioCue_EntityScript
{
    _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Stingers.UI");
    _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Transient; // Stingers are transient

    _SourcePriority = ECk_AudioCue_SourcePriority::LibraryOnly;
    _TrackLibrary = Get_StingerTracks();
    _SelectionMode = ECk_AudioCue_SelectionMode::Random;
    _RecentTrackAvoidanceTime = 30.0f; // 30 seconds

    _DefaultCrossfadeDuration = FCk_Time(0.1f);
    _MaxConcurrentTracks = 4;  // Allow multiple stingers
    _AllowSamePriorityTracks = true;
}

// Spatial Thunder Cue (for moving audio source)
asset Asset_SpatialThunderCue of UCk_AudioCue_EntityScript
{
    _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Spatial.Moving");
    _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Transient;

    _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Spatial.Thunder"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));

    // Configure for spatial playback
    _SingleTrack._IsSpatial = true;
    _SingleTrack._Loop = false;
    _SingleTrack._Volume = 0.9f;
    _SingleTrack._Priority = 30;
    _SingleTrack._LibraryAttenuationSettings = Asset_SoundAttenuation;
    _SingleTrack._LibraryConcurrencySettings = Asset_SoundConcurrency;

    _DefaultCrossfadeDuration = FCk_Time(0.5f);
    _MaxConcurrentTracks = 1;
    _AllowSamePriorityTracks = false;
}
}