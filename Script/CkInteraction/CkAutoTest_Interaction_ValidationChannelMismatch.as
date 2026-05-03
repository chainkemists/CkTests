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
// EXPECTED FAILURE — finding documented for investigation.
// Observed: Get_CanInteractWith returns CanInteractWith (success) when
// source channel != target channel. The ChannelMismatch enum value is
// never returned in this scenario. Possible causes:
//   1. Get_CanInteractWith doesn't check channels at all — channel
//      matching happens elsewhere (perhaps inside Request_StartInteraction).
//   2. Channel comparison uses the instigator handle differently than I
//      expected (passing MyEntity, which IS the source carrier, may
//      invert the comparison).
// Worth resolving via framework investigation: either ChannelMismatch
// is reachable through a different setup, or the enum value is dead
// code and the triggering condition should be documented.
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
        auto LocalHandle = InHandle;

        // Source uses the Default channel; target uses Secondary.
        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = interaction_gym_helpers::DefaultChannel();
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(
            interaction_gym_helpers::SecondaryChannel());
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));

        auto MyEntity = ck::ToEntity(this);
        auto CanResult = utils_interact_target::Get_CanInteractWith(_Target, MyEntity);
        Assert_True(CanResult == ECk_CanInteractWithResult::ChannelMismatch,
            f"Get_CanInteractWith with mismatched channels should return ChannelMismatch (got {CanResult})");

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(MyEntity);
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
