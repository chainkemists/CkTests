// Language=angelscript
class UCk_AutoTest_Sway_UpdateSpecInvalidNotEnqueued : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private float _OriginalFrequencyHz = 0.0f;
    private float _OriginalLateralCmFromYawRate = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        Add_Step("request a spec with a zero location frequency", n"Step_Reject");
        Add_Step_WaitSeconds("observe the rejection window", 0.1f);
        Add_Step("assert the spec is unchanged", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(10000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_Reject(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Current = utils_sway::Get_Spec(_F.Sway);
        _OriginalFrequencyHz = Current.Get_Location().Get_FrequencyHz();
        _OriginalLateralCmFromYawRate = Current.Get_LateralCmFromYawRate();

        auto Invalid = FCk_Sway_Spec();
        Invalid.Set_TeleportDistanceCm(0.0f);
        Invalid.Set_LateralCmFromYawRate(_OriginalLateralCmFromYawRate + 1.0f);
        auto Location = Invalid.Get_Location();
        Location.Set_FrequencyHz(0.0f);
        Invalid.Set_Location(Location);
        utils_sway::Request_UpdateSpec(_F.Sway, FCk_Request_Sway_UpdateSpec(Invalid),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 1, "invalid UpdateSpec completes synchronously");
        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued, "invalid UpdateSpec is not enqueued");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Spec = utils_sway::Get_Spec(_F.Sway);
        Assert_Equals_Int(_Completions, 1, "completion exactly once");
        Assert_True(Spec.Get_Location().Get_FrequencyHz() == _OriginalFrequencyHz, "location frequency unchanged");
        Assert_True(Spec.Get_LateralCmFromYawRate() == _OriginalLateralCmFromYawRate, "couplings unchanged");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_UpdateSpecInvalidNotEnqueued_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_UpdateSpecInvalidNotEnqueued;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Sway UpdateSpec rejected invalid spec");
        return Errors;
    }
}
