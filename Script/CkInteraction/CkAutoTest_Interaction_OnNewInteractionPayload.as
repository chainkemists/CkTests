// Language=angelscript

//============================================================================
// CK INTERACTION — AUTOMATION TEST: ON-NEW-INTERACTION PAYLOAD VALUES
//============================================================================
//
// Extends the Instant smoke test by reading the Interaction handle's
// payload values AFTER the OnNewInteraction signal fires:
//
//   - Get_InteractionSource     should equal the test entity (passed as
//                                source in Try_StartInteraction)
//   - Get_InteractionInstigator should equal the test entity
//   - Get_InteractionChannel    should equal the channel configured on
//                                Source/Target (DefaultChannel)
//   - Get_InteractionTarget     should equal the test entity (target lives
//                                on the same entity in this fixture)
//
// Pinning these prevents a regression where the signal fires but the
// Interaction handle's payload routes the wrong source/instigator/channel
// (which a "signal-fired" smoke test would not catch).
//
// IMPORTANT — SIGNAL/FRAGMENT ORDERING:
//   OnNewInteraction fires before the Interaction fragments are fully
//   populated on the new entity (verified empirically). Reading the
//   payload synchronously inside the callback hits Has<FFragment_Interaction_Params>=false
//   ensures. The robust pattern is to capture the handle in the callback,
//   then tick-poll until utils_interaction::Has(handle) reports true,
//   then assert.
//============================================================================

class UCk_AutoTest_Interaction_OnNewInteractionPayload : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 3.0f;

    private FCk_Handle_InteractSource _Source;
    private FCk_Handle_InteractTarget _Target;
    private FCk_Handle_Interaction _Interaction;
    private bool _SignalFired = false;
    private bool _Asserted = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto Channel = interaction_gym_helpers::DefaultChannel();

        auto SourceParams = FCk_InteractSource_Spec();
        SourceParams._InteractionChannel = Channel;
        _Source = utils_interact_source::Add(LocalHandle, SourceParams);

        auto TargetParams = FCk_InteractTarget_Spec(Channel);
        TargetParams.Set_CompletionPolicy(ECk_Interaction_CompletionPolicy::Instant);
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
        if (_SignalFired) { return; }
        _SignalFired = true;
        _Interaction = InInteraction;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        if (_Asserted) { return; }
        if (_SignalFired == false) { return; }

        // Wait for the Interaction fragments to be populated (at least one
        // tick after OnNewInteraction fires, observed empirically).
        if (utils_interaction::Has(FCk_Handle(_Interaction)) == false) { return; }

        _Asserted = true;
        auto MyEntity = ck::ToEntity(this);
        auto ExpectedChannel = interaction_gym_helpers::DefaultChannel();

        auto Source = utils_interaction::Get_InteractionSource(_Interaction);
        auto Instigator = utils_interaction::Get_InteractionInstigator(_Interaction);
        auto Target = utils_interaction::Get_InteractionTarget(_Interaction);
        auto Channel = utils_interaction::Get_InteractionChannel(_Interaction);

        Assert_True(utils_handle::IsEqual(Source, MyEntity),
            "Interaction Source should equal the test entity (passed as InteractSource in Try_StartInteraction)");
        Assert_True(utils_handle::IsEqual(Instigator, MyEntity),
            "Interaction Instigator should equal the test entity");
        Assert_True(utils_handle::IsEqual(Target, FCk_Handle(_Target)),
            "Interaction Target should equal the InteractTarget child entity (utils_interact_target::Add creates a typed child entity; Get_InteractionTarget returns that child, not the host entity)");
        Assert_True(Channel == ExpectedChannel,
            "Interaction Channel should equal the configured DefaultChannel");

        FinishSuccess();
    }
}
