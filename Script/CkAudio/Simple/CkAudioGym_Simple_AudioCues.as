asset Asset_SoundAttenuation_AudioGym of USoundAttenuation
{
}

asset Asset_Concurrency_AudioGym of USoundConcurrency
{
}

// Simple Background Music AudioCue (non-spatial, looping)
class UCk_SimpleBackgroundMusicCue : UCk_AudioCue_EntityScript
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic");
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));

    default _PlaybackBehavior = ECk_AudioCue_PlaybackBehavior::DelayedPlay;
    default _DelayTime = FCk_Time(5.0f);

    // Configure as non-spatial background music
    default _SingleTrack._Priority = 10;
    default _SingleTrack._LoopBehavior = ECk_LoopBehavior::PlayOnce;
    default _SingleTrack._Volume = 0.5f;
    default _SingleTrack._DefaultFadeInTime = FCk_Time(2.0f);
    default _SingleTrack._DefaultFadeOutTime = FCk_Time(2.0f);
    default _SingleTrack._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    default _SingleTrack._LibraryAttenuationSettings = Asset_SoundAttenuation_AudioGym;
    default _SingleTrack._LibraryConcurrencySettings = Asset_Concurrency_AudioGym;

    default _DefaultCrossfadeDuration = FCk_Time(2.0f);
    default _MaxConcurrentTracks = 1;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Block;
}

// Simple Spatial Audio AudioCue (3D positioned, one-shot)
class UCk_SimpleSpatialAudioCue : UCk_AudioCue_EntityScript
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio");
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Transient;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));

    // Configure as spatial 3D audio
    default _SingleTrack._Priority = 50;
    default _SingleTrack._LoopBehavior = ECk_LoopBehavior::PlayOnce;
    default _SingleTrack._Volume = 0.8f;
    default _SingleTrack._DefaultFadeInTime = FCk_Time(0.2f);
    default _SingleTrack._DefaultFadeOutTime = FCk_Time(0.2f);
    default _SingleTrack._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
    default _SingleTrack._LibraryAttenuationSettings = Asset_SoundAttenuation_AudioGym;
    default _SingleTrack._LibraryConcurrencySettings = Asset_Concurrency_AudioGym;

    default _DefaultCrossfadeDuration = FCk_Time(0.5f);
    default _MaxConcurrentTracks = 1;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Block;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}