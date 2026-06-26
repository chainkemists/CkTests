// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: TIMED INTERRUPTED BY CANCEL
//============================================================================
//
// Pins the cancel-mid-flight contract on a Timed interaction:
//   - Start a Timed interaction (0.5s duration).
//   - At ~0.1s into the duration, issue Request_CancelInteraction.
//   - OnInteractionFinished fires with ECk_SucceededFailed::Failed
//     (NOT Succeeded — the timer didn't reach its goal).
//
// This is the audit's "TimedInterruptedMidway" gap, simplified to use the
// CkInteraction-native Cancel path rather than destroying the target entity
// (target destruction would leak the interaction; Cancel is the supported
// interrupt verb).
//============================================================================

class UCk_AutoTest_Interaction_TimedInterruptedByCancel : UCk_AutoTest_Base
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
        TargetParams.Set_InteractionDuration(FCk_Time(0.5f));
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

        // Cancel after a short delay — well before the 0.5s Timed duration
        // would naturally complete.
        System::SetTimer(this, n"DoCancel", 0.1f, false);
    }

    UFUNCTION()
    private void DoCancel()
    {
        if (IsFinished()) { return; }
        if (_CancelRequested) { return; }
        _CancelRequested = true;

        auto CancelRequest = FCk_Request_InteractTarget_CancelInteraction(_MyEntity);
        utils_interact_target::Request_CancelInteraction(_Target, CancelRequest);
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(_CancelRequested,
            "OnInteractionFinished should fire only after Request_CancelInteraction (the Timed duration would not have completed in time)");
        Assert_True(InResult == ECk_SucceededFailed::Failed,
            f"A cancelled Timed interaction must finish with Failed (got {InResult})");

        FinishSuccess();
    }
}
