// Language=angelscript
class UCk_AutoTest_Chain_HoldUntilCoveredKeepsAuthoredPoseUntilReached : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FTransform _AuthoredPose;
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach uncovered authored link", n"Step_Arrange");
        Add_Step_WaitUntil("roster ready", n"Check_Ready");
        Add_Step("write head100", n"Step_First");
        Add_Step_WaitUntil("head100 settled", n"Check_First");
        Add_Step_WaitSeconds("observe uncovered hold", 0.1f);
        Add_Step("assert authored full pose and write head400", n"Step_Second");
        Add_Step_WaitUntil("head400 and covered link settled", n"Check_Placed");
        Add_Step("assert covered path", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, ECk_Chain_Solver::PathHistory, ECk_Chain_HistorySeed::HoldUntilCovered);
        _F.Attach(300.0f);
        _AuthoredPose = utils_transform::Get_EntityCurrentTransform(_F.Links[0]);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1));
    }

    UFUNCTION()
    private void Step_First(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.Location(0).Equals(FVector(0.0, 500.0, 0.0), 0.01), "authored starting location");
        _F.Move(FVector(100.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_First(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector(100.0, 0.0, 0.0), 0.01));
    }

    UFUNCTION()
    private void Step_Second(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_transform::Get_EntityCurrentTransform(_F.Links[0]).Equals(_AuthoredPose, 0.01), "uncovered link retains authored full pose");
        _F.Move(FVector(400.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_Placed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector(400.0, 0.0, 0.0), 0.01) && _F.Location(0).Equals(FVector(100.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.Location(0).Equals(FVector(100.0, 0.0, 0.0), 1.0), "covered link enters recorded path");
        FinishSuccess();
    }
}
