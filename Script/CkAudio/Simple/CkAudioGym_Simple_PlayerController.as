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
        auto BackgroundMusicTransform = Get_StationAnchorTransform("Gym.Audio.BackgroundMusic", ECk_GymStation_Anchor::PanelCenter);

        utils_cue_audio::Request_ExecuteCue(ck::ToEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.BackgroundMusic"),
            FAudioCueTransform(BackgroundMusicTransform),
            ECk_Cue_ReliabilityPolicy::Unreliable,
            ECk_Cue_MulticastPolicy::LocalOnly);

        ck::Trace("🎵 Background music cue executed at demo display location");
    }

    void Request_StartSpatialAudio()
    {
        auto SpatialAudioTransform = Get_StationAnchorTransform("Gym.Audio.SpatialAudio", ECk_GymStation_Anchor::PanelCenter);

        utils_cue_audio::Request_ExecuteCue(ck::ToEntity(this),
            utils_gameplay_tag::ResolveGameplayTag(n"AudioGym.Simple.SpatialAudio"),
            FAudioCueTransform(SpatialAudioTransform),
            ECk_Cue_ReliabilityPolicy::Unreliable,
            ECk_Cue_MulticastPolicy::LocalOnly);

        ck::Trace("🔊 Spatial audio cue executed at demo display location");
    }

    //--------------------------------------------------------------------------------------------------------------------------
    // CONTROL PANEL (Script/Common/CkGym_ControlPanel.as)
    //
    // A one-shot spatial cue has to be FIRED to be heard, and the music has to be restarted to be heard
    // from the top. Both were console-only, which made a working audio gym sound like a silent one.
    //--------------------------------------------------------------------------------------------------------------------------

    FString Get_ControlPanelTitle() override
    {
        return "AUDIO";
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Action(EKeys::M, "M", "Restart background music"));
        Rows.Add(CkGym_Control::Action(EKeys::S, "S", "Fire the spatial cue"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 0) { Ck_GymAudioSimple_RestartBackgroundMusic(); }
        else if (InRowIndex == 1) { Ck_GymAudioSimple_TriggerSpatialAudio(); }
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