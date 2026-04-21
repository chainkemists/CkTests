class ACk_AudioGym_Simple_PlayerController : ACk_Gym_Base_PlayerController
{
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

        utils_cue_audio::Request_ExecuteCue(ck::ToEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic"),
            FAudioCueTransform(BackgroundMusicTransform),
            ECk_Cue_ReliabilityPolicy::Unreliable,
            ECk_Cue_MulticastPolicy::LocalOnly);

        ck::Trace("🎵 Background music cue executed at demo display location");
    }

    void Request_StartSpatialAudio()
    {
        auto SpatialAudioTransform = Get_StationTransform("Gym.Audio.SpatialAudio");

        utils_cue_audio::Request_ExecuteCue(ck::ToEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio"),
            FAudioCueTransform(SpatialAudioTransform),
            ECk_Cue_ReliabilityPolicy::Unreliable,
            ECk_Cue_MulticastPolicy::LocalOnly);

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