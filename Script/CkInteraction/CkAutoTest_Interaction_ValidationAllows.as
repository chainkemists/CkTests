// Language=angelscript

//============================================================================
// CK INTERACTION - AUTOMATION TEST: VALIDATION ALLOWS
//============================================================================
//
// Happy-path test for the validation contract:
//   1. Source + Target on same entity, channel matches, target enabled,
//      custom CanInteractWith delegate returns true.
//   2. Get_CanInteractWith returns CanInteractWith (synchronous predicate).
//   3. Request_StartInteraction proceeds to fire OnNewInteraction.
//
// Mirrors CkInteractionGym_Validation's "expect OK" auto-step. Acts as the
// happy-path partner to the two rejection tests (TargetDisabled,
// CustomValidationFailed) which verify the enum branches.
//============================================================================

class UCk_AutoTest_Interaction_ValidationAllows : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _NewInteractionObserved = false;

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
        TargetParams.Set_CustomCanInteractWithDynamic(
            FCk_Delegate_InteractTarget_CanInteractWith(this, n"OnCanInteractWith"));
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));

        auto MyEntity = ck::ToEntity(this);
        auto CanResult = utils_interact_target::Get_CanInteractWith(_Target, MyEntity);
        Assert_True(CanResult == ECk_CanInteractWithResult::CanInteractWith,
            f"Get_CanInteractWith on enabled+allowed target should return CanInteractWith (got {CanResult})");

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(MyEntity);
        Request.Set_InteractInstigator(MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request);
    }

    UFUNCTION()
    private void OnCanInteractWith(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle InSource,
        FCk_Handle InInstigator,
        bool& OutResult)
    {
        OutResult = true;
    }

    UFUNCTION()
    private void OnNewInteraction(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction)
    {
        if (IsFinished()) { return; }
        _NewInteractionObserved = true;
        Assert_True(true, "OnNewInteraction should fire when validation passes");
        FinishSuccess();
    }
}
