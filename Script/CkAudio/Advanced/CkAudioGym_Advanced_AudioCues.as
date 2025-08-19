// Advanced AudioGym AudioCues
// Spatial, Music, Combat, and Activity audio definitions

// Advanced Spatial Thunder AudioCue (3D positioned, one-shot)
class UCk_AdvancedSpatialThunderCue : UCk_AudioCue_EntityScript
{
    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Spatial.Thunder");
    default _LifetimeBehavior = ECk_Cue_LifetimeBehavior::Transient;

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
        utils_transform::Add(InHandle, FTransform::Identity, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}
