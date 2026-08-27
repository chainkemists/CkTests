// Language=angelscript

//============================================================================
// CK INTERACTION - AUTOMATION TEST: DESTROY TARGET MID-INTERACTION
//============================================================================
//
// Pins the destroy-mid-interaction contract on a Timed interaction:
//   - Target lives on its OWN entity (destroying it must not cascade into
//     the test entity or the source).
//   - Start a Timed interaction (0.5s duration).
//   - At ~0.1s into the duration, destroy the target's entity.
//   - The SURVIVING source must still hear OnInteractionFinished with
//     ECk_SucceededFailed::Failed.
//
// This is the destroy path CkAutoTest_Interaction_TimedInterruptedByCancel
// deliberately routed around ("target destruction would leak the
// interaction"). The interaction entity dies in the cascade; its EndPlay
// processor is responsible for broadcasting the Failed outcome.
//============================================================================

class UCk_AutoTest_Interaction_DestroyTargetMidInteraction_SourceHearsFailed : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle _MyEntity;
    private FCk_Handle _TargetOwner;
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _DestroyRequested = false;

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

        // Target on its OWN entity - destroying it must not touch the source
        // or the test entity.
        _TargetOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Timed);
        TargetParams.Set_InteractionDuration(FCk_Time(0.5f));
        _Target = utils_interact_target::Add(_TargetOwner, TargetParams);

        utils_interact_source::BindTo_OnInteractionFinished(
            _Source,
            FCk_Delegate_InteractSource_OnInteractionFinished(this, n"OnSourceHeardFinished"));
        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));

        // The SOURCE FEATURE handle, not its owner: the target's handler silently skips arming the
        // source listener when the passed handle lacks the InteractSource feature.
        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(_Source);
        Request.Set_InteractInstigator(_MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request);
    }

    UFUNCTION()
    private void OnNewInteraction(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction)
    {
        if (_DestroyRequested) { return; }

        // Destroy after a short delay - well before the 0.5s Timed duration
        // would naturally complete.
        System::SetTimer(this, n"DoDestroyTarget", 0.1f, false);
    }

    UFUNCTION()
    private void DoDestroyTarget()
    {
        if (IsFinished()) { return; }
        if (_DestroyRequested) { return; }
        _DestroyRequested = true;

        utils_entity_lifetime::Request_DestroyEntity(_TargetOwner);
    }

    UFUNCTION()
    private void OnSourceHeardFinished(
        FCk_Handle_InteractSource InSource,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed SucceededFailed)
    {
        if (IsFinished()) { return; }

        Assert_True(_DestroyRequested,
            "Source must not hear Finished before the destroy (a Timed 0.5s interaction cannot complete by 0.1s)");
        Assert_True(SucceededFailed == ECk_SucceededFailed::Failed,
            f"Destroy-mid-interaction must finish as Failed (got {SucceededFailed})");

        FinishSuccess();
    }
}
