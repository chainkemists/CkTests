// Simple Background Music AudioCue (non-spatial, looping)
class UCk_SimpleBackgroundMusicCue : UCk_AudioCue_EntityScript
{
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic");
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/edm-gaming-music-335408.edm-gaming-music-335408",
        ECk_AssetSearchScope::Plugins)._Asset));

    // Configure as non-spatial background music
    default _SingleTrack._Priority = 10;
    default _SingleTrack._Loop = true;
    default _SingleTrack._Volume = 0.5f;
    default _SingleTrack._IsSpatial = false;
    default _SingleTrack._DefaultFadeInTime = FCk_Time(2.0f);
    default _SingleTrack._DefaultFadeOutTime = FCk_Time(2.0f);
    default _SingleTrack._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;

    default _DefaultCrossfadeDuration = FCk_Time(2.0f);
    default _MaxConcurrentTracks = 1;
    default _AllowSamePriorityTracks = false;
}

// Simple Spatial Audio AudioCue (3D positioned, one-shot)
class UCk_SimpleSpatialAudioCue : UCk_AudioCue_EntityScript
{
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio");
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Transient;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));

    // Configure as spatial 3D audio
    default _SingleTrack._Priority = 50;
    default _SingleTrack._Loop = false;
    default _SingleTrack._Volume = 0.8f;
    default _SingleTrack._IsSpatial = true;
    default _SingleTrack._DefaultFadeInTime = FCk_Time(0.2f);
    default _SingleTrack._DefaultFadeOutTime = FCk_Time(0.2f);
    default _SingleTrack._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;

    default _DefaultCrossfadeDuration = FCk_Time(0.5f);
    default _MaxConcurrentTracks = 1;
    default _AllowSamePriorityTracks = false;
}

asset Asset_SimpleBackgroundMusicCue of UCk_SimpleBackgroundMusicCue
{
}