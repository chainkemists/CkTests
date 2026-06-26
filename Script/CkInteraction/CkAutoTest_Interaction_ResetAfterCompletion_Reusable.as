// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: RESET AFTER COMPLETION — REUSABLE
//============================================================================
//
// Pins the contract that a Target with the default ConcurrentInteractionsPolicy
// (SingleInteraction) can be interacted with AGAIN immediately after the
// previous interaction completes — no leaked "still busy" state on the
// target's interaction fragment.
//
// Setup uses Instant completion so each interaction resolves in one tick:
//   1. Start interaction #1 → OnNewInteraction → OnInteractionFinished.
//   2. From inside the first OnInteractionFinished, queue interaction #2.
//   3. Observe OnNewInteraction and OnInteractionFinished a SECOND time.
//   4. Test succeeds when the second cycle completes cleanly (same Target,
//      different Interaction handles).
//
// A regression that left the target in a "occupied" state after completion
// (e.g. didn't disconnect the interaction record) would make the second
// Request_StartInteraction silently fail; this test catches that.
//============================================================================

class UCk_AutoTest_Interaction_ResetAfterCompletion_Reusable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle_Interaction _FirstInteraction;
    private FCk_Handle_Interaction _SecondInteraction;
    private int32 _NewObservedCount = 0;
    private int32 _FinishedObservedCount = 0;

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

        QueueStart();
    }

    private void QueueStart()
    {
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
        _NewObservedCount += 1;
        if (_NewObservedCount == 1)      { _FirstInteraction  = InInteraction; }
        else if (_NewObservedCount == 2) { _SecondInteraction = InInteraction; }
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }
        _FinishedObservedCount += 1;

        Assert_True(InResult == ECk_SucceededFailed::Succeeded,
            f"Cycle {_FinishedObservedCount} should finish Succeeded (got {InResult})");

        if (_FinishedObservedCount == 1)
        {
            // First cycle done — kick off the second.
            QueueStart();
            return;
        }

        // Second cycle done — verify both observations look right.
        Assert_Equals_Int(_NewObservedCount, 2,
            "Exactly two OnNewInteraction fires expected across the two cycles");
        Assert_True(_SecondInteraction != _FirstInteraction,
            "Second interaction should be a distinct entity from the first (target reset cleanly)");

        FinishSuccess();
    }
}
