// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: CONCURRENT INTERACTIONS, SAME TARGET
//============================================================================
//
// Pins the contract of `_ConcurrentInteractionsPolicy` on InteractTarget:
//
//   - SingleInteraction:    a second start while one is in flight should
//                            be rejected (Get_CanInteractWith returns
//                            TargetRejectedSecondInteraction or AlreadyExists,
//                            not CanInteractWith).
//
// For this test we use the Manual completion policy so the first interaction
// stays in flight until we explicitly end it. While in flight, we attempt a
// second start with a different InteractSource handle and assert rejection.
//
// (MultipleInteractions semantics — both proceed in parallel — would require
// two distinct source entities + two simultaneous OnNewInteraction observers,
// which is doable but doubles the fixture setup. SingleInteraction
// rejection is the load-bearing half: it's what gates the gameplay
// invariant that a target can't be hijacked while in use.)
//============================================================================

class UCk_AutoTest_Interaction_ConcurrentInteractionsSameTarget : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle _SecondSourceEntity;
    private bool _FirstInteractionStarted = false;
    private bool _SecondAttemptResolved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        // Spawn a second source entity for the concurrent attempt.
        _SecondSourceEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto SecondSourceParams = FCk_Fragment_InteractSource_ParamsData();
        SecondSourceParams._InteractionChannel = Channel;
        utils_interact_source::Add(_SecondSourceEntity, SecondSourceParams);

        // Target uses Manual policy so the first interaction stays in flight.
        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::ManuallyCompleted);
        TargetParams.Set_ConcurrentInteractionsPolicy(
            ECk_InteractionTarget_ConcurrentInteractionsPolicy::SingleInteraction);
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));

        auto MyEntity = ck::ToEntity(this);
        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(MyEntity);
        Request.Set_InteractInstigator(MyEntity);
        utils_interact_target::Request_StartInteraction(_Target, Request);

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnNewInteraction(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction)
    {
        _FirstInteractionStarted = true;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        if (_FirstInteractionStarted == false) { return; }
        if (_SecondAttemptResolved) { return; }
        _SecondAttemptResolved = true;

        // First interaction is in flight on a Manual target. Now ask
        // Get_CanInteractWith with a DIFFERENT source. Under SingleInteraction,
        // the second attempt must be rejected.
        auto CanResult = utils_interact_target::Get_CanInteractWith(_Target, _SecondSourceEntity);
        Assert_True(CanResult != ECk_CanInteractWithResult::CanInteractWith,
            f"Under SingleInteraction policy with one interaction in flight, a second source must be rejected (got {CanResult})");

        FinishSuccess();
    }
}
