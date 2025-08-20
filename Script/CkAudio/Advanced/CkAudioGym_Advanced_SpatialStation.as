// Spatial Station - Tests 3D positioning, attenuation, and concurrency
// Inherits from UCkAudioGym_Advanced_Base

class UCkAudioGym_Advanced_SpatialStation : UCkAudioGym_Advanced_Base
{
    // Spatial audio specific properties
    UPROPERTY()
    FVector AudioSourceOffset = FVector(0, 0, 100); // Offset from station center

    UPROPERTY()
    float AudioRadius = 300.0f; // Range of audio effect

    UPROPERTY()
    bool IsAudioPlaying = false;

    UPROPERTY()
    FCk_Handle_AudioCue AudioCue;

    // Override DoConstruct to set up spatial audio station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        Super::DoConstruct(InHandle);

        // Set up the spatial audio cue tag
        AudioCueTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Spatial.Thunder");

        // Override probe size for spatial testing
        ProbeSize = FVector(AudioRadius * 2, AudioRadius * 2, 200);

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Spatial"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride)
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        if (IsAudioPlaying == false)
        {
            StartSpatialAudio();
        }
    }

    UFUNCTION(BlueprintOverride)
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        StopSpatialAudio();
    }

    void StartSpatialAudio()
    {
        if (ck::IsValid(AudioCue))
        {
            utils_audio_cue::Request_Play(AudioCue, TOptional<int32>(), FCk_Time(0.2f));
            return;
        }

        // Execute the spatial audio cue
        auto SelfEntity = ck::SelfEntity(this);
        auto PendingEntityScript = utils_cue::Request_Execute_Local(SelfEntity, AudioCueTag, FInstancedStruct());

        PendingEntityScript.Promise_OnConstructed(FCk_Delegate_EntityScript_Constructed(this, n"OnSpatialAudioComplete"));

        IsAudioPlaying = true;
        Print("🔊 Spatial Audio Started", 2.0f);
    }

    UFUNCTION()
    private void OnSpatialAudioComplete(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        auto Entity = InEntityScriptHandle;
        AudioCue = Entity.H().To_FCk_Handle_AudioCue();
    }

    void StopSpatialAudio()
    {
        // Stop the spatial audio cue
        utils_audio_cue::Request_StopAll(AudioCue, FCk_Time(0.1f));

        IsAudioPlaying = false;
        Print("🔇 Spatial Audio Stopped", 2.0f);
    }
}
