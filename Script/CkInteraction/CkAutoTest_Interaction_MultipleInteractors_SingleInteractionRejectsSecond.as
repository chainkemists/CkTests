// Language=angelscript

//============================================================================
// CK INTERACTION - AUTOMATION TEST: MULTIPLE INTERACTORS / SINGLE-INTERACTION
//============================================================================
//
// Pins the contention contract at the Request_StartInteraction level: under
// SingleInteraction policy with one interaction in flight, a second start
// from a DIFFERENT source must NOT fire OnNewInteraction. The existing
// CkAutoTest_Interaction_ConcurrentInteractionsSameTarget covers the
// Get_CanInteractWith query path; this test pins the actual request path.
//
// Setup:
//   1. Two source entities (test entity + a spawned second entity), both on
//      the same channel.
//   2. Manual target with SingleInteraction policy.
//   3. Start from source 1 (test entity). Observe OnNewInteraction once.
//   4. Start from source 2 (spawned). Wait several ticks. Assert no second
//      OnNewInteraction fires.
//============================================================================

class UCk_AutoTest_Interaction_MultipleInteractors_SingleInteractionRejectsSecond : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_InteractSource _SourceA;
    private FCk_Handle _SourceBEntity;
    private FCk_Handle_InteractTarget _Target;
    private int32 _NewInteractionCount = 0;
    private bool _SecondStartIssued = false;
    private int32 _TicksAfterSecondStart = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceAParams = FCk_Fragment_InteractSource_ParamsData();
        SourceAParams._InteractionChannel = Channel;
        _SourceA = utils_interact_source::Add(LocalHandle, SourceAParams);

        // Second source entity.
        _SourceBEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto SourceBParams = FCk_Fragment_InteractSource_ParamsData();
        SourceBParams._InteractionChannel = Channel;
        utils_interact_source::Add(_SourceBEntity, SourceBParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::ManuallyCompleted);
        TargetParams.Set_ConcurrentInteractionsPolicy(
            ECk_InteractionTarget_ConcurrentInteractionsPolicy::SingleInteraction);
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));

        // Start from source A (the test entity).
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
        _NewInteractionCount += 1;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InHandle, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        // After source A's interaction is in flight, attempt source B's start.
        if (_NewInteractionCount == 0) { return; }
        if (_SecondStartIssued == false)
        {
            _SecondStartIssued = true;
            auto Request = FCk_Try_InteractTarget_StartInteraction();
            Request.Set_InteractSource(_SourceBEntity);
            Request.Set_InteractInstigator(_SourceBEntity);
            utils_interact_target::Request_StartInteraction(_Target, Request);
            return;
        }

        _TicksAfterSecondStart += 1;
        if (_TicksAfterSecondStart < 5) { return; }

        Assert_Equals_Int(_NewInteractionCount, 1,
            "Under SingleInteraction policy with one interaction in flight, a second Request_StartInteraction from a different source must not fire OnNewInteraction");

        FinishSuccess();
    }
}
