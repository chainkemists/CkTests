// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: VALIDATION REJECTS CHANNEL MISMATCH
//============================================================================
//
// Verifies the ChannelMismatch rejection path:
//   1. Source on the Default channel.
//   2. Target on the Secondary channel (different from source).
//   3. Get_CanInteractWith returns ChannelMismatch.
//   4. Request_StartInteraction does NOT fire OnNewInteraction across
//      several follow-up ticks.
//
// Pairs with the existing ValidationAllows / ValidationTargetDisabled /
// ValidationCustomFails tests to cover the full rejection enum surface
// that's reachable without exotic setup.
//
// RESOLUTION:
// The library's channel check at CkInteractTarget_Utils.cpp:156-163 only
// runs when UCk_Utils_InteractSource_UE::Cast(InSource) succeeds — i.e.,
// when InSource refers to the entity that owns the InteractSource fragment.
// utils_interact_source::Add(carrier, ...) creates a CHILD entity that holds
// the fragment; the carrier itself does NOT have FFragment_InteractSource_Params.
// Passing the carrier (MyEntity) to Get_CanInteractWith therefore makes the
// Cast return invalid, the channel branch is skipped, and the function falls
// through to CanInteractWith.
//
// The fix is to pass _Source (the typed handle for the source sub-entity)
// instead — both to Get_CanInteractWith and to the StartInteraction request.
// Cast now succeeds, channels are compared (Default vs Secondary), and the
// ChannelMismatch path returns as designed.
//============================================================================

class UCk_AutoTest_Interaction_ValidationChannelMismatch : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _NewInteractionFired = false;
    private int32 _TicksSinceRequest = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Source uses the Default channel; target uses Secondary.
        auto SourceParams = FCk_InteractSource_Spec();
        SourceParams._InteractionChannel = interaction_gym_helpers::DefaultChannel();
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_InteractTarget_Spec(
            interaction_gym_helpers::SecondaryChannel());
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));

        // Pass _Source (the typed source handle) so the library's Cast<InteractSource>
        // succeeds and the channel-mismatch branch runs. MyEntity is the carrier; the
        // source fragment lives on a child entity that utils_interact_source::Add created.
        FCk_Handle SourceHandle = _Source;
        auto MyEntity = ck::ToEntity(this);
        auto CanResult = utils_interact_target::Get_CanInteractWith(_Target, SourceHandle);
        Assert_True(CanResult == ECk_CanInteractWithResult::ChannelMismatch,
            f"Get_CanInteractWith with mismatched channels should return ChannelMismatch (got {CanResult})");

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(SourceHandle);
        Request.Set_InteractInstigator(MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnNewInteraction(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction)
    {
        _NewInteractionFired = true;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _TicksSinceRequest++;
        if (_TicksSinceRequest >= 5)
        {
            Assert_True(!_NewInteractionFired,
                "OnNewInteraction should NOT fire when source and target channels differ");
            FinishSuccess();
        }
    }
}
