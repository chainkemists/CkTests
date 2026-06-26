// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: MANUAL COMPLETION (FAIL)
//============================================================================
//
// Verifies ManuallyCompleted policy with explicit Failed end:
//   1. Same setup as ManualSuccess.
//   2. Request_EndInteraction with Failed (instead of Succeeded).
//   3. OnInteractionFinished fires with Failed.
//
// This is the partner test to ManualSuccess — together they verify the
// SucceededFailed parameter actually flows through to the finish callback,
// not silently coerced to Succeeded.
//============================================================================

class UCk_AutoTest_Interaction_ManualFail : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle_Interaction _ActiveInteraction;
    private bool _NewInteractionObserved = false;
    private bool _EndRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
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
        if (!_NewInteractionObserved || _EndRequested) { return; }

        _EndRequested = true;
        utils_interaction::Request_EndInteraction(
            _ActiveInteraction,
            FCk_Request_Interaction_EndInteraction(ECk_SucceededFailed::Failed));
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult == ECk_SucceededFailed::Failed,
            f"Manual interaction ended with Failed should report Failed (got {InResult})");

        FinishSuccess();
    }
}
