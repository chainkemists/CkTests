// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: ON-INTERACTION-FINISHED PAYLOAD SHAPE
//============================================================================
//
// Pins the FCk_Delegate_InteractTarget_OnInteractionFinished call shape:
//   - 3 args: (FCk_Handle_InteractTarget, FCk_Handle_Interaction, ECk_SucceededFailed)
//   - Target arg equals the target the delegate was bound on.
//   - Interaction arg equals the FCk_Handle_Interaction observed in
//     OnNewInteraction (same entity carried through start → finish).
//   - Result is Succeeded for an Instant-policy interaction with no
//     validator rejections.
//
// Uses Instant completion so the test can verify the full payload on a
// single result fire.
//============================================================================

class UCk_AutoTest_Interaction_OnInteractionFinished_PayloadShape : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle_Interaction _CapturedFromNewInteraction;
    private bool _NewObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_InteractSource_Spec();
        SourceParams._InteractionChannel = Channel;
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_InteractTarget_Spec(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));
        utils_interact_target::BindTo_OnInteractionFinished(
            _Target,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished"));

        auto MyEntity = ck::ToEntity(this);
        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(MyEntity);
        Request.Set_InteractInstigator(MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request);
    }

    UFUNCTION()
    private void OnNewInteraction(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction)
    {
        _NewObserved = true;
        _CapturedFromNewInteraction = InInteraction;
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(_NewObserved,
            "OnNewInteraction must fire before OnInteractionFinished to pin the captured handle");
        Assert_True(InTarget == _Target,
            "OnInteractionFinished payload Target should equal the InteractTarget the delegate was bound on");
        Assert_True(InInteraction == _CapturedFromNewInteraction,
            "OnInteractionFinished payload Interaction handle should equal the one observed in OnNewInteraction");
        Assert_True(InResult == ECk_SucceededFailed::Succeeded,
            f"Instant-policy interaction with no validator rejection should finish Succeeded (got {InResult})");

        FinishSuccess();
    }
}
