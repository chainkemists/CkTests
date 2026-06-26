// Language=angelscript

//============================================================================
// CK PROBE — AUTOMATION TEST: REQUEST ENABLE/DISABLE FLIPS STATE
//============================================================================
//
// Pins the Request_EnableDisable round-trip: a probe Added with the
// default StartingState (Enable) reports Enabled, and a subsequent
// Request_EnableDisable(Disable) flips the state observed via
// Get_IsEnabledDisabled. Re-enabling restores the Enable state.
//
// The state observation goes through the request processor, so we use
// WaitOneFrame after each Request_EnableDisable to let the deferred
// state mutation land before reading.
//============================================================================

class UCk_AutoTest_Probe_Request_EnableDisable_StateFlips : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 4.0f;

    private FCk_Handle_Probe _Probe;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;
        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto ProbeParams = FCk_Fragment_Probe_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.EnableDisable.Roundtrip"));
        _Probe = utils_probe::Add_Box(ParentTransform, FVector(30.0f, 30.0f, 30.0f), ProbeParams, FCk_Probe_DebugInfo());

        // The default StartingState is Enable; verify after one settle so
        // the request processor has applied StartingState into Current.
        WaitOneFrame(n"OnAfterInitialSettle");
    }

    UFUNCTION()
    private void OnAfterInitialSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Enable,
            "Probe with default StartingState should report Enable after the initial setup pass");

        utils_probe::Request_EnableDisable(_Probe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Disable));

        WaitOneFrame(n"OnAfterDisable");
    }

    UFUNCTION()
    private void OnAfterDisable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Disable,
            "After Request_EnableDisable(Disable), Get_IsEnabledDisabled should report Disable");

        utils_probe::Request_EnableDisable(_Probe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Enable));

        WaitOneFrame(n"OnAfterReEnable");
    }

    UFUNCTION()
    private void OnAfterReEnable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Enable,
            "After Request_EnableDisable(Enable), Get_IsEnabledDisabled should report Enable again");

        FinishSuccess();
    }
}
