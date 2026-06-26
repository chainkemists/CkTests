// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: INSTANT COMPLETION
//============================================================================
//
// Smoke test for the interaction system's Instant completion policy:
//   1. Add an InteractSource and InteractTarget on the same entity, both
//      on the same channel, with Target's CompletionPolicy::Instant.
//   2. Bind OnNewInteraction and OnInteractionFinished on the target.
//   3. Issue Request_StartInteraction.
//   4. OnNewInteraction fires, then OnInteractionFinished fires with
//      result Succeeded.
//
// Mirrors CkInteractionGym_Instant.
//============================================================================

class UCk_AutoTest_Interaction_Instant : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _NewInteractionObserved = false;
    private bool _FinishedObserved = false;

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
        _NewInteractionObserved = true;
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }
        _FinishedObserved = true;

        Assert_True(_NewInteractionObserved,
            "OnNewInteraction should fire before OnInteractionFinished");
        Assert_True(InResult == ECk_SucceededFailed::Succeeded,
            f"Instant interaction should finish with Succeeded (got {InResult})");

        FinishSuccess();
    }
}
