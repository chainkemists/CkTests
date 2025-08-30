class ACk_AudioGym_Simple_PlayerController : ACk_Gym_Base_PlayerController
{
    FString Get_GymName() override
    {
        return "Simple Audio Gym";
    }

    FString Get_GymDescription() override
    {
        return "Tests basic AudioCue functionality: background music and spatial audio";
    }

    TArray<FString> Get_RequiredStationTags() override
    {
        auto RequiredTags = TArray<FString>();
        RequiredTags.Add("Gym.Audio.BackgroundMusic");
        RequiredTags.Add("Gym.Audio.SpatialAudio");
        return RequiredTags;
    }

    void Request_StartGym() override
    {
        // Start both audio features
        Request_StartBackgroundMusic();
        Request_StartSpatialAudio();

        ck::Trace("🎵 Simple Audio Gym - All audio features started");
    }

    void Request_StartBackgroundMusic()
    {
        auto BackgroundMusicTransform = Get_StationTransform("Gym.Audio.BackgroundMusic");

        utils_cue_executor::Request_ExecuteCue_Local(ck::SelfEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic"),
            FAudioCueTransform(BackgroundMusicTransform));

        ck::Trace("🎵 Background music cue executed at demo display location");
    }

    void Request_StartSpatialAudio()
    {
        auto SpatialAudioTransform = Get_StationTransform("Gym.Audio.SpatialAudio");

        utils_cue_executor::Request_ExecuteCue_Local(ck::SelfEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio"),
            FAudioCueTransform(SpatialAudioTransform));

        ck::Trace("🔊 Spatial audio cue executed at demo display location");
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Restart Background Music")
    void Ck_GymAudioSimple_RestartBackgroundMusic()
    {
        Request_StartBackgroundMusic();
    }

    UFUNCTION(Exec, DisplayName="Simple AudioGym - Trigger Spatial Audio")
    void Ck_GymAudioSimple_TriggerSpatialAudio()
    {
        Request_StartSpatialAudio();
    }
}