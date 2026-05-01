// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: MANUAL COMPLETION (SUCCESS)
//============================================================================
//
// Verifies ManuallyCompleted policy with explicit Succeeded end:
//   1. Source + Target on same entity, Target's CompletionPolicy::ManuallyCompleted.
//   2. Request_StartInteraction.
//   3. OnNewInteraction fires; capture the FCk_Handle_Interaction.
//   4. Manual interactions do NOT auto-finish — wait several ticks to
//      confirm OnInteractionFinished hasn't fired.
//   5. Issue Request_EndInteraction with Succeeded.
//   6. OnInteractionFinished fires with Succeeded.
//
// Mirrors CkInteractionGym_Manual's success path.
//============================================================================

class UCk_AutoTest_Interaction_ManualSuccess : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle_Interaction _ActiveInteraction;
    private bool _NewInteractionObserved = false;
    private int32 _TicksSinceNew = 0;
    private bool _EndRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::ManuallyCompleted);
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));
        utils_interact_target::BindTo_OnInteractionFinished(
            _Target,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished"));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));

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
        _NewInteractionObserved = true;
        _ActiveInteraction = InInteraction;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (!_NewInteractionObserved) { return; }
        if (_EndRequested) { return; }

        _TicksSinceNew++;
        if (_TicksSinceNew >= 3)
        {
            // Confirmed manual interaction did not auto-finish; now issue
            // the explicit end request.
            _EndRequested = true;
            utils_interaction::Request_EndInteraction(
                _ActiveInteraction,
                FCk_Request_Interaction_EndInteraction(ECk_SucceededFailed::Succeeded));
        }
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(_EndRequested,
            "OnInteractionFinished should NOT fire on Manual policy before Request_EndInteraction is issued");
        Assert_True(InResult == ECk_SucceededFailed::Succeeded,
            f"Manual interaction ended with Succeeded should report Succeeded (got {InResult})");

        FinishSuccess();
    }
}
