// Language=angelscript

//============================================================================
// CK PROBE - AUTOMATION TEST: REQUEST ENABLE/DISABLE FLIPS STATE
//============================================================================
//
// Pins the Request_EnableDisable round-trip: a probe Added with the
// default StartingState (Enable) reports Enabled, and a subsequent
// Request_EnableDisable(Disable) flips the state observed via
// Get_IsEnabledDisabled. Re-enabling restores the Enable state.
//
// The state observation goes through the request processor, so we use
// A named wait after each Request_EnableDisable lets the deferred
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
        WaitUntil(n"Check_Enabled", n"OnAfterInitialSettle");
    }

    // Each Request_EnableDisable is deferred; the state actually flipping is the
    // settling event. The two flips after the first are decisive rather than
    // satisfied-on-arrival because the preceding wait guarantees the OPPOSITE
    // state is in place when the request is issued.
    UFUNCTION()
    private void Check_Enabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Enable);
    }

    UFUNCTION()
    private void Check_Disabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Disable);
    }

    UFUNCTION()
    private void Check_ReEnabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Enable);
    }

    UFUNCTION()
    private void OnAfterInitialSettle(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Enable,
            "Probe with default StartingState should report Enable after the initial setup pass");

        utils_probe::Request_EnableDisable(_Probe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Disable));

        WaitUntil(n"Check_Disabled", n"OnAfterDisable");
    }

    UFUNCTION()
    private void OnAfterDisable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(utils_probe::Get_IsEnabledDisabled(_Probe) == ECk_EnableDisable::Disable,
            "After Request_EnableDisable(Disable), Get_IsEnabledDisabled should report Disable");

        utils_probe::Request_EnableDisable(_Probe,
            FCk_Request_Probe_EnableDisable(ECk_EnableDisable::Enable));

        WaitUntil(n"Check_ReEnabled", n"OnAfterReEnable");
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
