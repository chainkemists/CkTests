// Language=angelscript

//============================================================================
// CK PROBE — AUTOMATION TEST: RECONFIGURE REJECTS BAKED-FIELD CHANGES
//============================================================================
//
// Request_Reconfigure re-applies only the live-read params subset. A request
// whose ProbeName/MotionType/MotionQuality/StartingState differ from the
// current params targets state that was baked into the Jolt body (or is
// construction-time identity) at Add — it must be rejected LOUDLY and
// atomically: completion fires Failed, and NO field of the params (not even
// the live-read ones riding the same request) is applied.
//============================================================================

class UCk_AutoTest_Probe_Reconfigure_RejectsBakedFieldChange : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 5.0f;

    private FCk_Handle_Probe _Probe;
    private bool _Completed = false;
    private ECk_Request_OperationResult _Result;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;
        auto ParentEntity = utils_entity_lifetime::Request_CreateEntity(Self);
        auto ParentTransform = utils_transform::Add(ParentEntity, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto ProbeTag = utils_gameplay_tag::ResolveGameplayTag(n"AutoTest.Probe.GetName.SpecificValue");
        auto Params = FCk_Fragment_Probe_ParamsData(ProbeTag);
        auto DebugInfo = FCk_Probe_DebugInfo();
        _Probe = utils_probe::Add_Box(ParentTransform, FVector(25.0f, 25.0f, 25.0f), Params, DebugInfo);

        auto Retuned = FCk_Fragment_Probe_ParamsData(ProbeTag);
        Retuned.Set_MotionType(ECk_MotionType::Kinematic);
        Retuned.Set_ResponsePolicy(ECk_ProbeResponse_Policy::Silent);
        auto ProbeLocal = _Probe;
        utils_probe::Request_Reconfigure(ProbeLocal, FCk_Request_Probe_Reconfigure(Retuned),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));

        Add_Step_WaitUntil("the request completes", n"Check_Completed");
        Add_Step("the rejection is atomic — nothing was applied", n"Step_AssertRejected");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Completed = true;
        _Result = InResult;
    }

    UFUNCTION()
    private void Check_Completed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Completed);
    }

    UFUNCTION()
    private void Step_AssertRejected(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Result == ECk_Request_OperationResult::Failed,
            "a baked-field change must complete as Failed");
        Assert_True(utils_probe::Get_MotionType(_Probe) == ECk_MotionType::Static,
            "the baked MotionType must be untouched");
        Assert_True(utils_probe::Get_ResponsePolicy(_Probe) == ECk_ProbeResponse_Policy::Notify,
            "rejection is atomic — the live-read fields riding the same request must NOT be applied");
    }
}

class ACk_AutoTest_Probe_Reconfigure_RejectsBakedFieldChange_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Probe_Reconfigure_RejectsBakedFieldChange;

    // The rejection is a deliberate CK ensure (Error log); whitelist it so the automation framework
    // doesn't fail the test on its own expected output.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        Out.Add("Probe Reconfigure on");
        return Out;
    }
}
