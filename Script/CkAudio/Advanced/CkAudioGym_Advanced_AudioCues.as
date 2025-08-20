// Advanced AudioGym AudioCues
// Spatial, Music, Combat, and Activity audio definitions

// Spawn parameters for AudioGym Advanced AudioCues
struct FCkAudioGym_Advanced_AudioCue_SpawnParams
{
    UPROPERTY()
    FTransform Transform;
}

// Advanced Sound Attenuation for spatial audio testing
asset Asset_SoundAttenuation_Advanced of USoundAttenuation
{
    // Enable volume attenuation and spatialization
    Attenuation.bAttenuate = true;
    Attenuation.bSpatialize = true;

    // Distance-based volume attenuation
    // Note: Basic attenuation is enabled, distance settings configured in Blueprint editor

    // Volume curve - starts at full volume, drops to 20% at max distance
    // Note: Curve setup would be done in Blueprint editor for complex curves

    // Enable air absorption (low-pass filter based on distance)
    Attenuation.bAttenuateWithLPF = true;
    Attenuation.LPFRadiusMin = 100.0f;
    Attenuation.LPFRadiusMax = 1000.0f;
    Attenuation.LPFFrequencyAtMin = 20000.0f; // Full frequency at close range
    Attenuation.LPFFrequencyAtMax = 2000.0f;  // Low-pass at far range

    // Enable reverb send based on distance
    Attenuation.bEnableReverbSend = true;
    Attenuation.ReverbSendMethod = EReverbSendMethod::Linear;
    Attenuation.ReverbDistanceMin = 100.0f;
    Attenuation.ReverbDistanceMax = 1000.0f;
    Attenuation.ReverbWetLevelMin = 0.0f;   // No reverb at close range
    Attenuation.ReverbWetLevelMax = 0.3f;   // Some reverb at far range

    // Enable priority attenuation based on distance
    Attenuation.bEnablePriorityAttenuation = true;
    Attenuation.PriorityAttenuationMethod = EPriorityAttenuationMethod::Linear;
    Attenuation.PriorityAttenuationDistanceMin = 100.0f;
    Attenuation.PriorityAttenuationDistanceMax = 1000.0f;
    Attenuation.PriorityAttenuationMin = 1.0f;  // Full priority at close range
    Attenuation.PriorityAttenuationMax = 0.3f;  // Reduced priority at far range

    // Non-spatialized radius for very close sounds
    Attenuation.NonSpatializedRadiusStart = 50.0f;
    Attenuation.NonSpatializedRadiusEnd = 25.0f;
    Attenuation.NonSpatializedRadiusMode = ENonSpatializedRadiusSpeakerMapMode::OmniDirectional;
}

// Advanced Spatial Thunder AudioCue (3D positioned, one-shot)
class UCk_AdvancedSpatialThunderCue : UCk_AudioCue_EntityScript
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Spatial.Thunder");
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Transient;

    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    // Load the Thunder sound asset and set up the track
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Spatial.Thunder.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
            ECk_AssetSearchScope::Plugins)._Asset));

    // Configure as spatial 3D audio
    default _SingleTrack._Priority = 50;
    default _SingleTrack._Loop = false;
    default _SingleTrack._Volume = 0.8f;
    default _SingleTrack._DefaultFadeInTime = FCk_Time(0.2f);
    default _SingleTrack._DefaultFadeOutTime = FCk_Time(0.2f);
    default _SingleTrack._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// Advanced Music AudioCue (3D positioned, looping with attenuation)
class UCk_AdvancedMusicCue : UCk_AudioCue_EntityScript
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Background");
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Persistent;

    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    // Load the background music asset and set up the track
    default _SingleTrack = FCk_Fragment_AudioTrack_ParamsData(
        utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Background.Track"),
        Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
            ECk_AssetSearchScope::Plugins)._Asset));

    // Configure as spatial looping music with attenuation
    default _SingleTrack._Priority = 30;
    default _SingleTrack._Loop = true;
    default _SingleTrack._Volume = 0.6f;
    default _SingleTrack._DefaultFadeInTime = FCk_Time(1.0f);
    default _SingleTrack._DefaultFadeOutTime = FCk_Time(1.0f);
    default _SingleTrack._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
    default _SingleTrack._LibraryAttenuationSettings = Asset_SoundAttenuation_Advanced;

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
