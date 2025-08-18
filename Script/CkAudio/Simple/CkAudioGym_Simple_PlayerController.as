class ACk_AudioGym_Simple_PlayerController : ACk_PlayerController_UE
{
    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        StartBackgroundMusic();
        StartSpatialAudio();

        Print("Simple AudioCue Gym Started - Background music and spatial audio should be playing", 5.0f);
    }

    void StartBackgroundMusic()
    {
        // Execute the background music AudioCue via subsystem
        auto ContextEntity = ck::SelfEntity(this);
        utils_cue::Request_Execute_Local(ContextEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic"),
            FInstancedStruct());

        Print("🎵 Background Music AudioCue Executed", 3.0f);
    }

    void StartSpatialAudio()
    {
        // Execute the spatial audio AudioCue via subsystem
        auto ContextEntity = ck::SelfEntity(this);
        utils_cue::Request_Execute_Local(ContextEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio"),
            FInstancedStruct());

        Print("🔊 Spatial Audio AudioCue Executed", 3.0f);
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Restart Background Music")
    void RestartBackgroundMusic()
    {
        StartBackgroundMusic();
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Trigger Spatial Audio")
    void TriggerSpatialAudio()
    {
        StartSpatialAudio();
    }
}