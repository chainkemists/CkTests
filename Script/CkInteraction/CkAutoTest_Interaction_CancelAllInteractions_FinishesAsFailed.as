// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: CANCEL ALL INTERACTIONS FIRES FINISHED
//============================================================================
//
// Pins the broadcast contract on the no-source bulk cancel:
//   - Start a Timed interaction (1.0s duration).
//   - Mid-flight, call Request_CancelAllInteractions (no source argument).
//   - OnInteractionFinished on the target fires with Failed for the
//     in-flight interaction.
//
// Companion to CkAutoTest_Interaction_TimedInterruptedByCancel which
// exercises the per-source Request_CancelInteraction path. Both Cancel
// verbs must funnel through Request_EndInteraction and broadcast
// InteractTarget_OnInteractionFinished — silent destroy would be a
// consistency bug.
//============================================================================

class UCk_AutoTest_Interaction_CancelAllInteractions_FinishesAsFailed : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle _MyEntity;
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _CancelRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        _MyEntity = LocalHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Timed);
        TargetParams.Set_InteractionDuration(FCk_Time(1.0f));
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));
        utils_interact_target::BindTo_OnInteractionFinished(
            _Target,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished"));

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(_MyEntity);
        Request.Set_InteractInstigator(_MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request);
    }

    UFUNCTION()
    private void OnNewInteraction(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction)
    {
        if (_CancelRequested) { return; }
        System::SetTimer(this, n"DoCancelAll", 0.1f, false);
    }

    UFUNCTION()
    private void DoCancelAll()
    {
        if (IsFinished()) { return; }
        if (_CancelRequested) { return; }
        _CancelRequested = true;

        utils_interact_target::Request_CancelAllInteractions(_Target);
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(_CancelRequested,
            "OnInteractionFinished should fire only after Request_CancelAllInteractions (the Timed duration would not have completed in time)");
        Assert_True(InResult == ECk_SucceededFailed::Failed,
            f"A cancelled-via-CancelAll Timed interaction must finish with Failed (got {InResult})");

        FinishSuccess();
    }
}
