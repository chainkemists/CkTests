// Spawn parameters for AudioGym Advanced AudioCues
struct FCkAudioGym_Advanced_AudioCue_SpawnParams
{
    UPROPERTY()
    FTransform Transform;
}

// Advanced Sound Attenuation for comprehensive spatial testing
asset Asset_SoundAttenuation_Advanced of USoundAttenuation
{
    Attenuation.bAttenuate = true;
    Attenuation.bSpatialize = true;

    // Comprehensive distance-based attenuation curve
    Attenuation.AttenuationShape = EAttenuationShape::Sphere;
    Attenuation.FalloffDistance = 800.0f;
    Attenuation.AttenuationShapeExtents = FVector(400.0f, 400.0f, 400.0f);

    // Advanced low-pass filtering for realistic air absorption
    Attenuation.bAttenuateWithLPF = true;
    Attenuation.LPFRadiusMin = 200.0f;
    Attenuation.LPFRadiusMax = 1200.0f;
    Attenuation.LPFFrequencyAtMin = 20000.0f;
    Attenuation.LPFFrequencyAtMax = 1500.0f;

    // Dynamic reverb based on distance
    Attenuation.bEnableReverbSend = true;
    Attenuation.ReverbSendMethod = EReverbSendMethod::Linear;
    Attenuation.ReverbDistanceMin = 200.0f;
    Attenuation.ReverbDistanceMax = 1200.0f;
    Attenuation.ReverbWetLevelMin = 0.1f;
    Attenuation.ReverbWetLevelMax = 0.5f;

    // Priority attenuation for intelligent culling
    Attenuation.bEnablePriorityAttenuation = true;
    Attenuation.PriorityAttenuationMethod = EPriorityAttenuationMethod::Linear;
    Attenuation.PriorityAttenuationDistanceMin = 300.0f;
    Attenuation.PriorityAttenuationDistanceMax = 1500.0f;
    Attenuation.PriorityAttenuationMin = 1.0f;
    Attenuation.PriorityAttenuationMax = 0.2f;

    // Non-spatialized radius for intimate sounds
    Attenuation.NonSpatializedRadiusStart = 100.0f;
    Attenuation.NonSpatializedRadiusEnd = 50.0f;
}

// Close Range Attenuation for UI and pickup sounds
asset Asset_SoundAttenuation_CloseRange of USoundAttenuation
{
    Attenuation.bAttenuate = true;
    Attenuation.bSpatialize = true;

    Attenuation.AttenuationShape = EAttenuationShape::Sphere;
    Attenuation.FalloffDistance = 300.0f;
    Attenuation.AttenuationShapeExtents = FVector(150.0f, 150.0f, 150.0f);

    // Minimal LPF for UI clarity
    Attenuation.bAttenuateWithLPF = true;
    Attenuation.LPFRadiusMin = 50.0f;
    Attenuation.LPFRadiusMax = 300.0f;
    Attenuation.LPFFrequencyAtMin = 20000.0f;
    Attenuation.LPFFrequencyAtMax = 8000.0f;
}

// Multi-Track Advanced Music AudioCue for complex musical arrangements
class UCk_AdvancedMusicDirectorCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _SourcePriority = ECk_AudioCue_SourcePriority::LibraryOnly;
    default _DefaultCrossfadeDuration = FCk_Time(3.0f);
    default _MaxConcurrentTracks = 4;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

    // Build comprehensive music library with proper sound assets
    TArray<FCk_Fragment_AudioTrack_ParamsData> BuildTrackLibrary()
    {
        auto TrackLibrary = TArray<FCk_Fragment_AudioTrack_ParamsData>();

        // Ambient base layer (lowest priority, always playing)
        auto Track1 = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Ambient.Base"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        Track1._Priority = 10;
        Track1._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
        Track1._LoopBehavior = ECk_LoopBehavior::Loop;
        Track1._Volume = 0.4f;
        Track1._DefaultFadeInTime = FCk_Time(2.0f);
        Track1._DefaultFadeOutTime = FCk_Time(2.0f);
        Track1._LibraryAttenuationSettings = Asset_SoundAttenuation_Advanced;
        TrackLibrary.Add(Track1);

        // Melodic layer (medium priority)
        auto Track2 = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Melodic.Layer"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        Track2._Priority = 30;
        Track2._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Crossfade;
        Track2._LoopBehavior = ECk_LoopBehavior::Loop;
        Track2._Volume = 0.6f;
        Track2._DefaultFadeInTime = FCk_Time(1.5f);
        Track2._DefaultFadeOutTime = FCk_Time(1.5f);
        Track2._LibraryAttenuationSettings = Asset_SoundAttenuation_Advanced;
        TrackLibrary.Add(Track2);

        // Percussion layer (high priority, intermittent)
        auto Track3 = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Percussion.Layer"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        Track3._Priority = 50;
        Track3._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Queue;
        Track3._LoopBehavior = ECk_LoopBehavior::PlayOnce;
        Track3._Volume = 0.7f;
        Track3._DefaultFadeInTime = FCk_Time(0.5f);
        Track3._DefaultFadeOutTime = FCk_Time(1.0f);
        Track3._LibraryAttenuationSettings = Asset_SoundAttenuation_Advanced;
        TrackLibrary.Add(Track3);

        // Dynamic stinger (highest priority, interrupts)
        auto Track4 = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Stinger.Dynamic"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        Track4._Priority = 80;
        Track4._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
        Track4._LoopBehavior = ECk_LoopBehavior::PlayOnce;
        Track4._Volume = 0.8f;
        Track4._DefaultFadeInTime = FCk_Time(0.1f);
        Track4._DefaultFadeOutTime = FCk_Time(0.5f);
        Track4._LibraryAttenuationSettings = Asset_SoundAttenuation_Advanced;
        TrackLibrary.Add(Track4);

        return TrackLibrary;
    }

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Orchestral");
    default _TrackLibrary = BuildTrackLibrary();

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// Concurrency Test AudioCue - Multiple thunder sounds with priority management
class UCk_AdvancedConcurrencyTestCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Thunder");
    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    // Configure for concurrency testing
    default _DefaultCrossfadeDuration = FCk_Time(0.5f);
    default _MaxConcurrentTracks = 8;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

    // Build the single track properly with sound asset
    FCk_Fragment_AudioTrack_ParamsData BuildSingleTrack()
    {
        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Thunder.Track"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        TrackParams._Priority = 40;
        TrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Queue;
        TrackParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
        TrackParams._Volume = 0.8f;
        TrackParams._DefaultFadeInTime = FCk_Time(0.2f);
        TrackParams._DefaultFadeOutTime = FCk_Time(0.2f);
        TrackParams._LibraryAttenuationSettings = Asset_SoundAttenuation_Advanced;

        return TrackParams;
    }

    default _SingleTrack = BuildSingleTrack();

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// Enhanced Interface Pickup Audio - Close range, high clarity
class UCk_AdvancedInterfacePickupCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Interface.Pickup");
    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    // Build the single track properly with sound asset
    FCk_Fragment_AudioTrack_ParamsData BuildSingleTrack()
    {
        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Interface.Pickup.Track"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        TrackParams._Priority = 70;
        TrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
        TrackParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
        TrackParams._Volume = 0.8f;
        TrackParams._DefaultFadeInTime = FCk_Time(0.0f);
        TrackParams._DefaultFadeOutTime = FCk_Time(0.1f);
        TrackParams._LibraryAttenuationSettings = Asset_SoundAttenuation_CloseRange;

        return TrackParams;
    }

    default _SingleTrack = BuildSingleTrack();

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

// Enhanced Achievement Audio - Celebration sounds
class UCk_AdvancedAchievementCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _CueName = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Achievement.Fanfare");
    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    // Build the single track properly with sound asset
    FCk_Fragment_AudioTrack_ParamsData BuildSingleTrack()
    {
        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Achievement.Fanfare.Track"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));

        TrackParams._Priority = 90;
        TrackParams._OverrideBehavior = ECk_AudioTrack_OverrideBehavior::Interrupt;
        TrackParams._LoopBehavior = ECk_LoopBehavior::PlayOnce;
        TrackParams._Volume = 1.0f;
        TrackParams._DefaultFadeInTime = FCk_Time(0.0f);
        TrackParams._DefaultFadeOutTime = FCk_Time(0.5f);
        TrackParams._LibraryAttenuationSettings = Asset_SoundAttenuation_CloseRange;

        return TrackParams;
    }

    default _SingleTrack = BuildSingleTrack();

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}