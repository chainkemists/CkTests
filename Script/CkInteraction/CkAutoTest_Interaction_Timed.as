// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: TIMED COMPLETION
//============================================================================
//
// Verifies the Timed completion policy:
//   1. Source + Target on same entity, Target's CompletionPolicy::Timed
//      with InteractionDuration of 0.25s.
//   2. Request_StartInteraction.
//   3. OnNewInteraction fires immediately.
//   4. OnInteractionFinished fires AFTER ~0.25s (NOT immediately).
//   5. Result is Succeeded.
//
// We track that some delta of ticks elapses between OnNewInteraction and
// OnInteractionFinished — the Timed policy must not auto-resolve in the
// same frame as the start.
//
// Mirrors CkInteractionGym_Timed.
//============================================================================

class UCk_AutoTest_Interaction_Timed : UCk_AutoTest_Base
{
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private bool _NewInteractionObserved = false;
    private int32 _TicksSinceNew = 0;
    private bool _FinishedObserved = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Timed);
        TargetParams.Set_InteractionDuration(FCk_Time(0.25f));
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
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (_NewInteractionObserved && !_FinishedObserved)
        {
            _TicksSinceNew++;
        }
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
        Assert_True(_TicksSinceNew >= 1,
            f"Timed interaction should not finish in the same frame as start (ticks elapsed: {_TicksSinceNew})");
        Assert_True(InResult == ECk_SucceededFailed::Succeeded,
            f"Timed interaction should finish with Succeeded (got {InResult})");

        FinishSuccess();
    }
}
