// Language=angelscript
class UCk_AutoTest_Chain_AddWithInvalidParamsComposesNothing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attempt invalid spacing", n"Step_Arrange");
        Add_Step_WaitSeconds("exclude delayed composition", 0.1f);
        Add_Step("assert no record or chain", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Owner = InHandle;
        _F.Head = _F.Spawn(FVector::ZeroVector);
        auto Params = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        Params.Set_SampleSpacingCm(0.0f);
        _F.Chain = utils_chain::Add(_F.Head, Params);
        Assert_Invalid(_F.Chain, "invalid Add returns invalid chain synchronously");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_chain::Has_Any(_F.Head), "invalid Add leaves no chain record on head");
        Assert_Invalid(_F.Chain, "invalid Add remains uncomposed");
        FinishSuccess();
    }
}

class ACk_AutoTest_Chain_AddWithInvalidParamsComposesNothing_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Chain_AddWithInvalidParamsComposesNothing;
    default _TimeoutSeconds = 6.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Chain Add rejected invalid parameters");
        return Errors;
    }
}

