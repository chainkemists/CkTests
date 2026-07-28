// Language=angelscript
//
// CK AUDIO — AUTOMATION TEST: soft-ref sound resolves through the loader, plays, and survives GC
//
// Pins the soft-params design: Params hold a soft path only; the Setup processor resolves it
// through CkResourceLoader (async by default) and roots the resolved batch on the track's Current.
// A Play requested IMMEDIATELY after Add must queue behind FTag_AudioTrack_NeedsSetup and fire once
// the load lands; a full GC after playback starts must not disturb the loader-rooted asset.
//
// In-editor the package/asset-registry machinery also keeps a real asset resident, so the negative
// half (collection without the root) is only falsifiable in a packaged build — the C++ unit tests
// own the params-layer no-dangle contract; this test owns the resolve/queue/root pipeline.

class UCk_AutoTest_AudioTrack_SoftSoundResolvesPlaysAndSurvivesGC : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_AudioTrack _Track;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto OwnerHandle = InHandle;

        auto Director = utils_audio_director::Add(OwnerHandle, FCk_Fragment_AudioDirector_ParamsData());
        Assert_True(ck::IsValid(Director), "utils_audio_director::Add should return a valid director handle");
        if (IsFinished()) { return; }

        auto TrackParams = FCk_Fragment_AudioTrack_ParamsData(
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/Engine/EngineSounds/1kSineTonePing.1kSineTonePing",
                ECk_AssetSearchScope::Engine)._Asset));
        TrackParams._TrackName = n"AutoTest_SoftSound";
        TrackParams.Set_DefaultFadeInTime(FCk_Time(0.0f));

        utils_audio_director::Request_AddTrack(Director, TrackParams);

        utils_audio_director::BindTo_OnTrackStarted(Director,
            FCk_Delegate_AudioDirector_Track(this, n"OnTrackStarted"));

        // Requested BEFORE setup/load completes — must queue behind NeedsSetup and fire once resolved
        utils_audio_director::Request_StartTrack(Director,
            FCk_Request_AudioDirector_StartTrack(n"AutoTest_SoftSound"));
    }

    UFUNCTION()
    private void OnTrackStarted(FCk_Handle_AudioDirector InDirector, FName InTrackName, FCk_Handle_AudioTrack InTrack)
    {
        if (IsFinished()) { return; }

        _Track = InTrack;

        System::CollectGarbage();
        WaitOneFrame(n"OnGCSettled");
    }

    UFUNCTION()
    private void OnGCSettled(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto State = utils_audio_track::Get_State(_Track);
        Assert_True(State == ECk_AudioTrack_State::Playing || State == ECk_AudioTrack_State::FadingIn,
            f"after a full GC the loader-rooted track must still be playing (state: {State})");

        FinishSuccess();
    }
}
