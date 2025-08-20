// Attenuation Station - Tests distance-based volume changes and spatial audio positioning
// Inherits from UCkAudioGym_Advanced_Base

class UCkAudioGym_Advanced_AttenuationStation : UCkAudioGym_Advanced_Base
{
    // Attenuation specific properties
    UPROPERTY()
    FVector AudioSourceOffset = FVector(0, 0, 150); // Offset from station center

    UPROPERTY()
    float AudioRadius = 400.0f; // Range of audio effect

    UPROPERTY()
    bool IsAudioPlaying = false;

    UPROPERTY()
    FCk_Handle_AudioCue AudioCue;

    // Override DoConstruct to set up attenuation audio station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        Super::DoConstruct(InHandle);

        // Set up the music audio cue tag
        AudioCueTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Music.Background");

        // Override probe size for attenuation testing - large room-sized area for volume testing
        ProbeSize = FVector(800, 800, 400);

        // Set visual properties
        StationName = "ATTENUATION STATION";
        StationDescription = "Walk around to hear volume and frequency changes";
        StationColor = FLinearColor(0.0f, 1.0f, 0.5f, 1.0f); // Green for attenuation

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Attenuation"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        if (IsAudioPlaying == false)
        {
            StartAttenuationAudio();
        }
    }

    UFUNCTION(BlueprintOverride)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        StopAttenuationAudio();
    }

    void StartAttenuationAudio()
    {
        if (ck::IsValid(AudioCue))
        {
            utils_audio_cue::Request_Play(AudioCue, TOptional<int32>(), FCk_Time(1.0f));
            return;
        }

        // Execute the music audio cue
        auto SelfEntity = ck::SelfEntity(this);
        auto SpawnParams = FCkAudioGym_Advanced_AudioCue_SpawnParams();
        SpawnParams.Transform = Transform;

        auto Str = FInstancedStruct();
        Str.InitializeAs(SpawnParams);
        auto PendingEntityScript = utils_cue::Request_Execute_Local(SelfEntity, AudioCueTag, Str);

        PendingEntityScript.Promise_OnConstructed(FCk_Delegate_EntityScript_Constructed(this, n"OnAttenuationAudioComplete"));

        IsAudioPlaying = true;
        UpdateVisualFeedback(true);
        Print("🎵 Attenuation Audio Started - Walk around to hear volume changes", 3.0f);
    }

    UFUNCTION()
    private void OnAttenuationAudioComplete(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        auto Entity = InEntityScriptHandle;
        AudioCue = Entity.H().To_FCk_Handle_AudioCue();
    }

    void StopAttenuationAudio()
    {
        // Stop the attenuation audio cue
        utils_audio_cue::Request_StopAll(AudioCue, FCk_Time(1.0f));

        IsAudioPlaying = false;
        UpdateVisualFeedback(false);
        Print("🔇 Attenuation Audio Stopped", 2.0f);
    }
}
