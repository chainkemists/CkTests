// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: GET_CURRENTINTERACTIONS DURING IN-FLIGHT
//============================================================================
//
// Pins the `Get_CurrentInteractions(target)` query contract — the array
// of currently-in-flight interaction handles on a Target:
//   - Before any interaction: empty.
//   - While a Manual interaction is in flight: contains exactly one entry
//     matching the OnNewInteraction handle.
//   - After end: empty again.
//
// Complements TryGet_Interaction_ReturnsActive — TryGet looks up by source,
// Get_CurrentInteractions enumerates all active interactions on the target.
//============================================================================

class UCk_AutoTest_Interaction_Get_CurrentInteractions_DuringInFlight : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle_Interaction _Active;
    private bool _MidFlightChecked = false;
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

        // Pre-start check — no in-flight interactions.
        auto BeforeStart = utils_interact_target::Get_CurrentInteractions(_Target);
        Assert_Equals_Int(BeforeStart.Num(), 0,
            "Before any Request_StartInteraction, Get_CurrentInteractions must be empty");

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
        if (_MidFlightChecked) { return; }
        _MidFlightChecked = true;
        _Active = InInteraction;

        // Get_CurrentInteractions reads from a record that is populated by a
        // deferred processor pass — at OnNewInteraction-fire time the entry
        // isn't yet visible (DoBeginPlay asserted the record empty before the
        // start, so this is decisively false here). Wait for the entry to appear
        // rather than for a frame; the exact COUNT stays an assertion so a
        // duplicate-entry regression is reported instead of released on.
        WaitUntil(n"Check_InteractionVisible", n"OnSettled_MidFlight");
    }

    // The record is this test's own target, not a shared surface, so a count is
    // an honest reading of "mine".
    UFUNCTION()
    private void Check_InteractionVisible(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_interact_target::Get_CurrentInteractions(_Target).Num() >= 1);
    }

    // Waiting for empty is only meaningful because the mid-flight hop already
    // asserted the record held exactly 1 — that positive is what stops "empty"
    // from passing on a record that was never populated.
    UFUNCTION()
    private void Check_InteractionsCleared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_interact_target::Get_CurrentInteractions(_Target).Num() == 0);
    }

    UFUNCTION()
    private void OnSettled_MidFlight(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto MidFlight = utils_interact_target::Get_CurrentInteractions(_Target);
        Assert_Equals_Int(MidFlight.Num(), 1,
            "While one Manual interaction is in flight, Get_CurrentInteractions must report exactly 1 entry");
        if (MidFlight.Num() == 1)
        {
            Assert_True(MidFlight[0] == _Active,
                "The single in-flight entry must equal the FCk_Handle_Interaction observed in OnNewInteraction");
        }

        _EndRequested = true;
        utils_interaction::Request_EndInteraction(
            _Active,
            FCk_Request_Interaction_EndInteraction(ECk_SucceededFailed::Succeeded));
    }

    UFUNCTION()
    private void OnInteractionFinished(
        FCk_Handle_InteractTarget InTarget,
        FCk_Handle_Interaction InInteraction,
        ECk_SucceededFailed InResult)
    {
        if (IsFinished()) { return; }
        Assert_True(_EndRequested,
            "OnInteractionFinished should fire only after the explicit Request_EndInteraction");
        WaitUntil(n"Check_InteractionsCleared", n"OnSettled_AfterFinish");
    }

    UFUNCTION()
    private void OnSettled_AfterFinish(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto AfterFinish = utils_interact_target::Get_CurrentInteractions(_Target);
        Assert_Equals_Int(AfterFinish.Num(), 0,
            "After an interaction ends, Get_CurrentInteractions must return to empty");

        FinishSuccess();
    }
}
