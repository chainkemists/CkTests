class UCk_AudioTest_AudioDirectorConfig_DA : UCk_AudioDirector_Config
{
}

class UCk_AudioTest_Library_DA : UCk_MusicLibrary_Base
{
    default _LibraryName = utils_gameplay_tag::ResolveGameplayTag(n"Audio.Music.Test.Ambient");
}

class ACk_AudioTest_GymPlayerController : ACk_PlayerController_UE
{
    UPROPERTY()
    FCk_Handle_AudioDirector AudioTestEntity;

    UFUNCTION(BlueprintOverride)
    void BeginPlay()
    {
        auto NewEntity = utils_entity_lifetime::Request_CreateEntity_TransientOwner();

        auto DirectorParams = FCk_Fragment_AudioDirector_ParamsData();
        DirectorParams._DefaultCrossfadeDuration = FCk_Time(2.0f);
        DirectorParams._MaxConcurrentTracks = 4;

        AudioTestEntity = utils_audio_director::Add(NewEntity, DirectorParams);

        auto TimerParams = FCk_Fragment_Timer_ParamsData(FCk_Time(5.0f));
        TimerParams._StartingState = ECk_Timer_State::Running;
        TimerParams._Behavior = ECk_Timer_Behavior::ResetOnDone;
        auto TimerEntity = utils_timer::Add(NewEntity, TimerParams);

        utils_timer::BindTo_OnUpdate(TimerEntity, ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"OnTimerUpdate"));
        utils_timer::BindTo_OnDone(TimerEntity, ECk_Signal_BindingPolicy::FireIfPayloadInFlight, FCk_Delegate_Timer(this, n"OnTimerDone"));

        StartAudioTrack();
    }

    UFUNCTION()
    private void OnTimerUpdate(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        const auto Duration = 2.0f;
        const auto Color = FLinearColor(1.00, 0.65, 0.00);
        ck::Trace(f"STOPPING Audio in: {InChrono.Get_TimeRemaining()._Seconds} seconds", n"TimerUpdate", Duration, Color);
    }

    UFUNCTION()
    private void OnTimerDone(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        StopAudioTrack();
    }

    UFUNCTION(Exec, DisplayName="Ck Tests START Audio Track")
    void StartAudioTrack()
    {
        auto EdmMusic = Cast<USoundBase>(
            utils_i_o::LoadAssetByName("/CkTests/CkAudio/SFX/edm-gaming-music-335408.edm-gaming-music-335408",
            ECk_AssetSearchScope::Plugins)._Asset);
        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(utils_gameplay_tag::ResolveGameplayTag(n"Audio.Test.Ambient"), EdmMusic);
        TrackParams._Priority = 10;
        TrackParams._Loop = true;
        TrackParams._ScriptAsset = UCk_AudioTest_GymEntityScript;

        utils_audio_director::Request_AddTrack(AudioTestEntity, TrackParams);
        utils_audio_director::Request_StartTrack(AudioTestEntity, utils_gameplay_tag::ResolveGameplayTag(n"Audio.Test.Ambient"), TOptional<int32>(), FCk_Time(6.0f));
    }

    UFUNCTION(Exec, DisplayName="Ck Tests STOP Audio Track")
    void StopAudioTrack()
    {
        UCk_Utils_AudioDirector_UE::Request_StopTrack(AudioTestEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"Audio.Test.Ambient"), FCk_Time(0.5f));
    }

    UFUNCTION(Exec, DisplayName="Ck Tests Music Library")
    void TestMusicLibrary()
    {
        auto Config = Cast<UCk_AudioDirector_Config>(
            utils_i_o::LoadAssetByName("/CkTests/CkAudio/Data/AudioDirector_CkTests_DA.AudioDirector_CkTests_DA",
            ECk_AssetSearchScope::Plugins)._Asset);

        if (!ck::IsValid(Config))
        { return; }

        auto Library = Config.Find_MusicLibrary(
            utils_gameplay_tag::ResolveGameplayTag(n"Audio.Music.Test.Ambient"));

        if (!ck::IsValid(Library))
        { return; }

        utils_audio_director::Request_AddMusicLibrary(AudioTestEntity, Library);
        utils_audio_director::Request_StartMusicLibrary(AudioTestEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"Audio.Music.Test.Ambient"), TOptional<int32>(), FCk_Time(2.0f));
    }

    UFUNCTION(Exec, DisplayName="Ck Tests Music Library Repeat")
    void TestMusicLibraryRepeat()
    {
        utils_audio_director::Request_StartMusicLibrary(AudioTestEntity,
            utils_gameplay_tag::ResolveGameplayTag(n"Audio.Music.Test.Ambient"), TOptional<int32>(2), FCk_Time(2.0f));
    }
};