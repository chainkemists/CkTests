// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: VALIDATION REJECTS BY CUSTOM PREDICATE
//============================================================================
//
// Verifies the CustomValidationFailed rejection path:
//   1. Source + Target on same entity, channel matches, target enabled.
//   2. Bind a CustomCanInteractWith delegate that returns false.
//   3. Get_CanInteractWith returns CustomValidationFailed.
//   4. Request_StartInteraction does NOT fire OnNewInteraction across
//      several follow-up ticks.
//   5. The custom predicate WAS invoked (proving the rejection went via
//      the user-supplied delegate, not some short-circuit elsewhere).
//============================================================================

class UCk_AutoTest_Interaction_ValidationCustomFails : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _NewInteractionFired = false;
    private bool _PredicateInvoked = false;
    private int32 _TicksSinceRequest = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
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
        Assert_True(CanResult == ECk_CanInteractWithResult::CustomValidationFailed,
            f"Get_CanInteractWith with custom predicate returning false should return CustomValidationFailed (got {CanResult})");
        Assert_True(_PredicateInvoked,
            "Get_CanInteractWith should invoke the custom predicate");

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(MyEntity);
        Request.Set_InteractInstigator(MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnCanInteractWith(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle InSource,
        FCk_Handle InInstigator,
        bool& OutResult)
    {
        _PredicateInvoked = true;
        OutResult = false;
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
                "OnNewInteraction should NOT fire when custom predicate returns false");
            FinishSuccess();
        }
    }
}
