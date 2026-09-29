// Language=angelscript
class UCk_AutoTest_Sway_CreateWithInvalidParentComposesNothing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_Handle_Sway _Sway;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("create with invalid parent", n"Step_Create");
        Add_Step_WaitSeconds("exclude delayed composition", 0.1f);
        Add_Step("assert nothing composed", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Create(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        auto Invalid = FCk_Handle_Transform();
        _Sway = utils_sway::Create(Invalid, FTransform(), Spec);
        Assert_Invalid(_Sway, "Create with an invalid parent returns an invalid handle synchronously");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Invalid(_Sway, "Create with an invalid parent stays uncomposed");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_CreateWithInvalidParentComposesNothing_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_CreateWithInvalidParentComposesNothing;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Sway Create rejected invalid parent");
        return Errors;
    }
}
