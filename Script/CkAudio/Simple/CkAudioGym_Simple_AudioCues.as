asset Asset_SoundAttenuation_AudioGym of USoundAttenuation
{
}

asset Asset_Concurrency_AudioGym of USoundConcurrency
{
}

USTRUCT()
struct FAudioCueTransform
{
    UPROPERTY()
    FTransform InitialTransform = FTransform::Identity;

    FAudioCueTransform(FTransform InTransform)
    {
        InitialTransform = InTransform;
    }
}

// Simple Background Music AudioCue (non-spatial, looping)
class UCk_SimpleBackgroundMusicCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
        ECk_AssetSearchScope::Plugins).Get_Asset().Get()));

    default _PlaybackBehavior = ECk_AudioCue_PlaybackBehavior::DelayedPlay;
    default _DelayTime = FCk_Time(5.0f);

    // Configure as non-spatial background music
    default _SingleTrack.Set_Priority(10);
    default _SingleTrack.Set_LoopBehavior(ECk_LoopBehavior::PlayOnce);
    default _SingleTrack.Set_Volume(0.5f);
    default _SingleTrack.Set_DefaultFadeInTime(FCk_Time(2.0f));
    default _SingleTrack.Set_DefaultFadeOutTime(FCk_Time(2.0f));
    default _SingleTrack.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Crossfade);
    default _SingleTrack.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_AudioGym);
    default _SingleTrack.Set_LibraryConcurrencySettings(Asset_Concurrency_AudioGym);

    default _DefaultCrossfadeDuration = FCk_Time(2.0f);
    default _MaxConcurrentTracks = 1;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Block;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic");
    }
}

// Simple Spatial Audio AudioCue (3D positioned, one-shot)
class UCk_SimpleSpatialAudioCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform InitialTransform = FTransform::Identity;

    default _Replication = ECk_Replication::DoesNotReplicate;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
        ECk_AssetSearchScope::Plugins)._Asset));

    // Configure as spatial 3D audio
    default _SingleTrack.Set_Priority(50);
    default _SingleTrack.Set_LoopBehavior(ECk_LoopBehavior::PlayOnce);
    default _SingleTrack.Set_Volume(0.8f);
    default _SingleTrack.Set_DefaultFadeInTime(FCk_Time(0.2f));
    default _SingleTrack.Set_DefaultFadeOutTime(FCk_Time(0.2f));
    default _SingleTrack.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Interrupt);
    default _SingleTrack.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_AudioGym);
    default _SingleTrack.Set_LibraryConcurrencySettings(Asset_Concurrency_AudioGym);

    default _DefaultCrossfadeDuration = FCk_Time(0.5f);
    default _MaxConcurrentTracks = 1;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Block;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio");
    }

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}