// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: TRYGET_INTERACTION RETURNS ACTIVE
//============================================================================
//
// Pins the `TryGet_Interaction(target, source)` query contract:
//   - Before any interaction starts: returns an invalid handle.
//   - While a Manual-policy interaction is in flight: returns a valid handle
//     matching the FCk_Handle_Interaction observed in OnNewInteraction.
//   - After the interaction is explicitly ended: returns an invalid handle
//     again (the in-flight entry has been removed).
//
// Uses Manual completion so the in-flight window is observable across
// multiple ticks rather than auto-resolving in one frame.
//============================================================================

class UCk_AutoTest_Interaction_TryGet_Interaction_ReturnsActive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle _MyEntity;
    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle_Interaction _Active;
    private bool _MidFlightChecked = false;
    private bool _EndRequested = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;
        _MyEntity = LocalHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_Fragment_InteractSource_ParamsData();
        SourceParams._InteractionChannel = Channel;
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_Fragment_InteractTarget_ParamsData(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::ManuallyCompleted);
        _Target = utils_interact_target::Add(LocalHandle, TargetParams);

        // Pre-start check — no interaction yet, TryGet must report invalid.
        auto BeforeStart = utils_interact_target::TryGet_Interaction(_Target, _MyEntity);
        Assert_True(ck::Is_NOT_Valid(BeforeStart),
            "Before any Request_StartInteraction, TryGet_Interaction must return an invalid handle");

        utils_interact_target::BindTo_OnNewInteraction(
            _Target,
            FCk_Delegate_InteractTarget_OnNewInteraction(this, n"OnNewInteraction"));
        utils_interact_target::BindTo_OnInteractionFinished(
            _Target,
            FCk_Delegate_InteractTarget_OnInteractionFinished(this, n"OnInteractionFinished"));

        auto Request = FCk_Try_InteractTarget_StartInteraction();
        Request.Set_InteractSource(_MyEntity);
        Request.Set_InteractInstigator(_MyEntity);
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

        // TryGet_Interaction reads from a source->interaction record that is
        // populated by a deferred processor pass — at OnNewInteraction-fire
        // time, the record isn't yet visible. Wait one frame before querying.
        WaitOneFrame(n"OnSettled_MidFlight");
    }

    UFUNCTION()
    private void OnSettled_MidFlight(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto MidFlight = utils_interact_target::TryGet_Interaction(_Target, _MyEntity);
        Assert_True(ck::IsValid(MidFlight),
            "While an interaction is in flight, TryGet_Interaction must return a valid handle");
        Assert_True(MidFlight == _Active,
            "TryGet_Interaction must return the same FCk_Handle_Interaction observed in OnNewInteraction");

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
        WaitOneFrame(n"OnSettled_AfterFinish");
    }

    UFUNCTION()
    private void OnSettled_AfterFinish(
        FCk_Handle_Timer InTimer,
        FCk_Chrono InChrono,
        FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto AfterFinish = utils_interact_target::TryGet_Interaction(_Target, _MyEntity);
        Assert_True(ck::Is_NOT_Valid(AfterFinish),
            "After an interaction is ended, TryGet_Interaction must return an invalid handle");

        FinishSuccess();
    }
}
