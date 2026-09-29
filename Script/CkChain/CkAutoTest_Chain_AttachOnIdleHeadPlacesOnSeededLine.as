// Language=angelscript
class UCk_AutoTest_Chain_AttachOnIdleHeadPlacesOnSeededLine : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach beside idle head", n"Step_Arrange");
        Add_Step_WaitUntil("seed placement observed", n"Check_Placed");
        Add_Step("assert seeded line", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(150.0f);
    }

    UFUNCTION()
    private void Check_Placed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1) && _F.Location(0).Equals(FVector(-150.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.Location(0).Equals(FVector(-150.0, 0.0, 0.0), 1.0), "idle link placed behind head");
        Assert_True(utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector::ZeroVector, 0.01), "head never moved");
        FinishSuccess();
    }
}
