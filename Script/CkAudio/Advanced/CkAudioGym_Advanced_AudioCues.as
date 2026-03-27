/*
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │     Spawn Parameters                                                        │
  └─────────────────────────────────────────────────────────────────────────────┘
*/

struct FCkAudioGym_Advanced_AudioCue_SpawnParams
{
    UPROPERTY()
    FTransform Transform;
}

/*
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │     Sound Attenuation Assets                                                │
  └─────────────────────────────────────────────────────────────────────────────┘
*/

asset Asset_SoundAttenuation_Advanced of USoundAttenuation
{
    Attenuation.bAttenuate = true;
    Attenuation.bSpatialize = true;

    Attenuation.AttenuationShape = EAttenuationShape::Sphere;
    Attenuation.FalloffDistance = 800.0f;
    Attenuation.AttenuationShapeExtents = FVector(400.0f, 400.0f, 400.0f);

    Attenuation.bAttenuateWithLPF = true;
    Attenuation.LPFRadiusMin = 200.0f;
    Attenuation.LPFRadiusMax = 1200.0f;
    Attenuation.LPFFrequencyAtMin = 20000.0f;
    Attenuation.LPFFrequencyAtMax = 1500.0f;

    Attenuation.bEnableReverbSend = true;
    Attenuation.ReverbSendMethod = EReverbSendMethod::Linear;
    Attenuation.ReverbDistanceMin = 200.0f;
    Attenuation.ReverbDistanceMax = 1200.0f;
    Attenuation.ReverbWetLevelMin = 0.1f;
    Attenuation.ReverbWetLevelMax = 0.5f;

    Attenuation.bEnablePriorityAttenuation = true;
    Attenuation.PriorityAttenuationMethod = EPriorityAttenuationMethod::Linear;
    Attenuation.PriorityAttenuationDistanceMin = 300.0f;
    Attenuation.PriorityAttenuationDistanceMax = 1500.0f;
    Attenuation.PriorityAttenuationMin = 1.0f;
    Attenuation.PriorityAttenuationMax = 0.2f;

    Attenuation.NonSpatializedRadiusStart = 100.0f;
    Attenuation.NonSpatializedRadiusEnd = 50.0f;
}

asset Asset_SoundAttenuation_CloseRange of USoundAttenuation
{
    Attenuation.bAttenuate = true;
    Attenuation.bSpatialize = true;

    Attenuation.AttenuationShape = EAttenuationShape::Sphere;
    Attenuation.FalloffDistance = 300.0f;
    Attenuation.AttenuationShapeExtents = FVector(150.0f, 150.0f, 150.0f);

    Attenuation.bAttenuateWithLPF = true;
    Attenuation.LPFRadiusMin = 50.0f;
    Attenuation.LPFRadiusMax = 300.0f;
    Attenuation.LPFFrequencyAtMin = 20000.0f;
    Attenuation.LPFFrequencyAtMax = 8000.0f;
}

/*
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │     Advanced Music Director Cue                                             │
  └─────────────────────────────────────────────────────────────────────────────┘
*/

class UCk_AdvancedMusicDirectorCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _SourcePriority = ECk_AudioCue_SourcePriority::LibraryOnly;
    default _DefaultCrossfadeDuration = FCk_Time(3.0f);
    default _MaxConcurrentTracks = 4;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AudioGym.Advanced.Music.Orchestral");
    }

    TArray<FCk_Fragment_AudioTrack_ParamsData> BuildTrackLibrary()
    {
        auto TrackLibrary = TArray<FCk_Fragment_AudioTrack_ParamsData>();

        auto Track1 = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));
        Track1._TrackName = n"AudioGym.Advanced.Music.Ambient.Base";

        Track1.Set_Priority(10);
        Track1.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Crossfade);
        Track1.Set_LoopBehavior(ECk_LoopBehavior::Loop);
        Track1.Set_Volume(0.4f);
        Track1.Set_DefaultFadeInTime(FCk_Time(2.0f));
        Track1.Set_DefaultFadeOutTime(FCk_Time(2.0f));
        Track1.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_Advanced);
        TrackLibrary.Add(Track1);

        auto Track2 = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Ambient_Edm_SFX.Ambient_Edm_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));
        Track2._TrackName = n"AudioGym.Advanced.Music.Melodic.Layer";

        Track2.Set_Priority(30);
        Track2.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Crossfade);
        Track2.Set_LoopBehavior(ECk_LoopBehavior::Loop);
        Track2.Set_Volume(0.6f);
        Track2.Set_DefaultFadeInTime(FCk_Time(1.5f));
        Track2.Set_DefaultFadeOutTime(FCk_Time(1.5f));
        Track2.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_Advanced);
        TrackLibrary.Add(Track2);

        auto Track3 = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));
        Track3._TrackName = n"AudioGym.Advanced.Music.Percussion.Layer";

        Track3.Set_Priority(50);
        Track3.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Queue);
        Track3.Set_LoopBehavior(ECk_LoopBehavior::PlayOnce);
        Track3.Set_Volume(0.7f);
        Track3.Set_DefaultFadeInTime(FCk_Time(0.5f));
        Track3.Set_DefaultFadeOutTime(FCk_Time(1.0f));
        Track3.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_Advanced);
        TrackLibrary.Add(Track3);

        auto Track4 = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));
        Track4._TrackName = n"AudioGym.Advanced.Music.Stinger.Dynamic";

        Track4.Set_Priority(80);
        Track4.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Interrupt);
        Track4.Set_LoopBehavior(ECk_LoopBehavior::PlayOnce);
        Track4.Set_Volume(0.8f);
        Track4.Set_DefaultFadeInTime(FCk_Time(0.1f));
        Track4.Set_DefaultFadeOutTime(FCk_Time(0.5f));
        Track4.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_Advanced);
        TrackLibrary.Add(Track4);

        return TrackLibrary;
    }

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _TrackLibrary = BuildTrackLibrary();

    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        utils_transform::Add(InHandle, Transform, ECk_Replication::DoesNotReplicate);
        return ECk_EntityScript_ConstructionFlow::Finished;
    }
}

/*
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │     Concurrency Test Cue                                                   │
  └─────────────────────────────────────────────────────────────────────────────┘
*/

class UCk_AdvancedConcurrencyTestCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    default _DefaultCrossfadeDuration = FCk_Time(0.5f);
    default _MaxConcurrentTracks = 8;
    default _SamePriorityBehavior = ECk_SamePriorityBehavior::Allow;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AudioGym.Advanced.Concurrency.Thunder");
    }

    FCk_Fragment_AudioTrack_ParamsData BuildSingleTrack()
    {
        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Thunder_SFX.Stinger_Thunder_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));
        TrackParams._TrackName = n"AudioGym.Advanced.Concurrency.Thunder.Track";

        TrackParams.Set_Priority(40);
        TrackParams.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Queue);
        TrackParams.Set_LoopBehavior(ECk_LoopBehavior::PlayOnce);
        TrackParams.Set_Volume(0.8f);
        TrackParams.Set_DefaultFadeInTime(FCk_Time(0.2f));
        TrackParams.Set_DefaultFadeOutTime(FCk_Time(0.2f));
        TrackParams.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_Advanced);

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

/*
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │     Interface Pickup Cue                                                   │
  └─────────────────────────────────────────────────────────────────────────────┘
*/

class UCk_AdvancedInterfacePickupCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AudioGym.Advanced.Interface.Pickup");
    }

    FCk_Fragment_AudioTrack_ParamsData BuildSingleTrack()
    {
        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));
        TrackParams._TrackName = n"AudioGym.Advanced.Interface.Pickup.Track";

        TrackParams.Set_Priority(70);
        TrackParams.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Interrupt);
        TrackParams.Set_LoopBehavior(ECk_LoopBehavior::PlayOnce);
        TrackParams.Set_Volume(0.8f);
        TrackParams.Set_DefaultFadeInTime(FCk_Time(0.0f));
        TrackParams.Set_DefaultFadeOutTime(FCk_Time(0.1f));
        TrackParams.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_CloseRange);

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

/*
  ┌─────────────────────────────────────────────────────────────────────────────┐
  │     Achievement Cue                                                         │
  └─────────────────────────────────────────────────────────────────────────────┘
*/

class UCk_AdvancedAchievementCue : UCk_AudioCue_EntityScript
{
    UPROPERTY(ExposeOnSpawn)
    FTransform Transform;

    default _Replication = ECk_Replication::DoesNotReplicate;
    default _SourcePriority = ECk_AudioCue_SourcePriority::SingleTrackOnly;

    UFUNCTION(BlueprintOverride)
    FGameplayTag Get_CueName() const
    {
        return GameplayTags::ResolveGameplayTag(n"AudioGym.Advanced.Achievement.Fanfare");
    }

    FCk_Fragment_AudioTrack_ParamsData BuildSingleTrack()
    {
        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/Stringers/Stinger_Interface_SFX.Stinger_Interface_SFX",
                ECk_AssetSearchScope::Plugins)._Asset));
        TrackParams._TrackName = n"AudioGym.Advanced.Achievement.Fanfare.Track";

        TrackParams.Set_Priority(90);
        TrackParams.Set_OverrideBehavior(ECk_AudioTrack_OverrideBehavior::Interrupt);
        TrackParams.Set_LoopBehavior(ECk_LoopBehavior::PlayOnce);
        TrackParams.Set_Volume(1.0f);
        TrackParams.Set_DefaultFadeInTime(FCk_Time(0.0f));
        TrackParams.Set_DefaultFadeOutTime(FCk_Time(0.5f));
        TrackParams.Set_LibraryAttenuationSettings(Asset_SoundAttenuation_CloseRange);

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