// Language=angelscript
//
// CK FX — AUTOMATION TEST: a soft-cue play queued before setup completes with Succeeded
//
// Pins the Sfx half of the soft-params design end-to-end: soft cue in Params, the Setup processor
// resolves + roots it through CkResourceLoader (async default), a play requested IMMEDIATELY after
// Add queues behind FTag_Sfx_NeedsSetup instead of silently skipping or ensuring, and the
// request-completion delegate reports Succeeded once the deferred spawn actually happens.

class UCk_AutoTest_Sfx_SoftCueQueuedPlayCompletes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto OwnerHandle = InHandle;

        auto Params = FCk_Fragment_Sfx_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Sfx.SoftCue_QueuedPlay"),
            Cast<USoundBase>(utils_i_o::LoadAssetByName("/Engine/EngineSounds/1kSineTonePing.1kSineTonePing",
                ECk_AssetSearchScope::Engine)._Asset));

        auto SfxHandle = utils_sfx::Add(OwnerHandle, Params);
        Assert_True(ck::IsValid(SfxHandle), "utils_sfx::Add should return a valid FCk_Handle_Sfx");
        if (IsFinished()) { return; }

        // Requested BEFORE setup/load completes — must queue behind NeedsSetup, then spawn + complete
        auto PlayRequest = FCk_Request_Sfx_PlayAtLocation();
        PlayRequest._Outer = this;

        utils_sfx::Request_PlayAtLocation(SfxHandle, PlayRequest,
            FCk_Delegate_Request_OnCompleted(this, n"OnPlayCompleted"));
    }

    UFUNCTION()
    private void OnPlayCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_Request_OperationResult::Succeeded,
            f"queued soft-cue play must complete Succeeded once the deferred spawn happens (got {InResult})");

        FinishSuccess();
    }
}
