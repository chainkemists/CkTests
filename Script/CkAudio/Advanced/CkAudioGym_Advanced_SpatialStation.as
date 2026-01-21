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

    // UPROPERTY()
    // FCk_Handle_AudioCue AudioCue;

    // Override DoConstruct to set up spatial audio station
    UFUNCTION(BlueprintOverride)
    ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
    {
        Super::DoConstruct(InHandle);

        // Set up the spatial audio cue tag
        AudioCueTag = utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Spatial.Thunder");

        // Override probe size for spatial testing - medium sized for 3D positioning
        ProbeSize = FVector(400, 400, 300);

        // Set visual properties
        StationName = "SPATIAL AUDIO STATION";
        StationDescription = "Test 3D positioning and thunder effects";
        StationColor = FLinearColor(1.0f, 0.5f, 0.0f, 1.0f); // Orange for spatial

        utils_entity_tag::Add_UsingGameplayTag(InHandle,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Advanced.Station.Spatial"));

        return ECk_EntityScript_ConstructionFlow::Finished;
    }

    // Override base class overlap functions
    UFUNCTION(BlueprintOverride, meta=(NoSuperCall))
    void OnPlayerEnteredStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnBeginOverlap InOverlapInfo)
    {
        if (IsAudioPlaying == false)
        {
            StartSpatialAudio();
        }
    }

    UFUNCTION(BlueprintOverride, meta=(NoSuperCall))
    void OnPlayerExitedStation(FCk_Handle_Probe InProbe, FCk_Probe_Payload_OnEndOverlap InOverlapInfo)
    {
        StopSpatialAudio();
    }

    void StartSpatialAudio()
    {
        // if (ck::IsValid(AudioCue))
        // {
        //     auto Request = FCk_Request_AudioCue_Play();
        //     Request.Set_FadeInTime(FCk_Time(0.2f));
        //     utils_audio_cue::Request_Play(AudioCue, Request);
        //     return;
        // }

        // Execute the spatial audio cue with proper transform
        auto SelfEntity = ck::ToEntity(this);

        // Create spawn params with the station's transform (same struct as music cue)
        auto SpawnParams = FCkAudioGym_Advanced_AudioCue_SpawnParams();
        SpawnParams.Transform = Transform; // Use the station's transform

        auto Str = FInstancedStruct();
        Str.InitializeAs(SpawnParams);
        auto PendingEntityScript = utils_cue_audio::Request_ExecuteCue_Local(SelfEntity, AudioCueTag, Str);

        PendingEntityScript.Promise_OnConstructed(FCk_Delegate_EntityScript_Constructed(this, n"OnSpatialAudioComplete"));

        IsAudioPlaying = true;
        UpdateVisualFeedback(true);
        Print("🔊 Spatial Audio Started", 2.0f);
    }

    UFUNCTION()
    private void OnSpatialAudioComplete(FCk_Handle_EntityScript InEntityScriptHandle)
    {
        auto Entity = InEntityScriptHandle;
        // AudioCue = Entity.As_AudioDirector();
    }

    void StopSpatialAudio()
    {
        // Stop the spatial audio cue
        // utils_audio_cue::Request_StopAll(AudioCue);

        IsAudioPlaying = false;
        UpdateVisualFeedback(false);
        Print("🔇 Spatial Audio Stopped", 2.0f);
    }
}
