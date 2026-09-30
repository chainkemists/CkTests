// Language=angelscript
class UCk_AutoTest_RotateTowards_AddWithInvalidHandleComposesNothing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("add onto an invalid transform handle", n"Step_Add");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Add(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RotateTowards = utils_rotate_towards::Add(FCk_Handle_Transform(), _F.Make_DefaultSpec());
        Assert_Invalid(RotateTowards, "Add onto an invalid transform returns an invalid handle");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_AddWithInvalidHandleComposesNothing_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_AddWithInvalidHandleComposesNothing;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("RotateTowards Add rejected invalid transform");
        return Errors;
    }
}
