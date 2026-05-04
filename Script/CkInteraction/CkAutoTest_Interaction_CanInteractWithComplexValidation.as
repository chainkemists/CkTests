// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: CAN-INTERACT-WITH COMPLEX VALIDATION
//============================================================================
//
// Existing ValidationCustomFails covers a flat "always-false" predicate.
// This test pins the contract for state-dependent validation: the predicate
// alternates between Allow and Deny based on the test's own state, and we
// observe both branches behave correctly within one test run.
//
// Two scenarios in sequence:
//   Phase 1: predicate state = Deny -> Get_CanInteractWith returns
//            CustomValidationFailed; Request_StartInteraction does NOT
//            fire OnNewInteraction within the settle window.
//   Phase 2: predicate state = Allow -> Get_CanInteractWith returns
//            CanInteractWith; Request_StartInteraction fires OnNewInteraction.
//
// Verifies the predicate is re-invoked per Get_CanInteractWith call (not
// cached) and that its return value flips behavior at runtime.
//============================================================================

class UCk_AutoTest_Interaction_CanInteractWithComplexValidation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _PredicateAllowsCurrentResult = false;
    private bool _Phase1NewInteractionFired = false;
    private bool _Phase2NewInteractionFired = false;
    private int32 _Phase = 0;
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

        // Phase 1: predicate denies.
        _Phase = 1;
        _PredicateAllowsCurrentResult = false;
        auto MyEntity = ck::ToEntity(this);

        auto CanResult_Deny = utils_interact_target::Get_CanInteractWith(_Target, MyEntity);
        Assert_True(CanResult_Deny == ECk_CanInteractWithResult::CustomValidationFailed,
            f"Phase 1 (predicate=Deny): Get_CanInteractWith should return CustomValidationFailed (got {CanResult_Deny})");

        auto Request1 = FCk_Try_InteractTarget_StartInteraction();
        Request1.Set_InteractSource(MyEntity);
        Request1.Set_InteractInstigator(MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request1);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnCanInteractWith(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle InSource,
        FCk_Handle InInstigator,
        bool& OutResult)
    {
        OutResult = _PredicateAllowsCurrentResult;
    }

    UFUNCTION()
    private void OnNewInteraction(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction)
    {
        if (_Phase == 1) { _Phase1NewInteractionFired = true; }
        if (_Phase == 2) { _Phase2NewInteractionFired = true; }
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _TicksSinceRequest++;

        if (_Phase == 1 && _TicksSinceRequest >= 5)
        {
            // Phase 1 settle: predicate denied; OnNewInteraction must NOT have fired.
            Assert_True(_Phase1NewInteractionFired == false,
                "Phase 1 (predicate=Deny): OnNewInteraction must not fire when predicate returns false");

            // Phase 2: flip predicate to allow, fire again.
            _Phase = 2;
            _TicksSinceRequest = 0;
            _PredicateAllowsCurrentResult = true;

            auto MyEntity = ck::ToEntity(this);
            auto CanResult_Allow = utils_interact_target::Get_CanInteractWith(_Target, MyEntity);
            Assert_True(CanResult_Allow == ECk_CanInteractWithResult::CanInteractWith,
                f"Phase 2 (predicate=Allow): Get_CanInteractWith should return CanInteractWith (got {CanResult_Allow})");

            auto Request2 = FCk_Try_InteractTarget_StartInteraction();
            Request2.Set_InteractSource(MyEntity);
            Request2.Set_InteractInstigator(MyEntity);
            utils_interact_target::Request_StartInteraction(_Target, Request2);
            return;
        }

        if (_Phase == 2 && _Phase2NewInteractionFired)
        {
            Assert_True(_Phase2NewInteractionFired,
                "Phase 2 (predicate=Allow): OnNewInteraction must fire when predicate returns true");
            FinishSuccess();
        }
    }
}
