// Language=angelscript
class UCk_AutoTest_Chain_GetPoseAtDistanceUncoveredIsInvalid : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FVector _HeadLocation = FVector(200.0, 300.0, 0.0);
    private bool _EmptyWasInvalid = false;
    private bool _EmptyPoseWasDefault = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose hold chain off the origin and query before setup", n"Step_Arrange");
        Add_Step_WaitUntil("history seeded", n"Check_Seeded");
        Add_Step("assert uncovered and covered queries", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Owner = InHandle;
        _F.Head = _F.Spawn(_HeadLocation);
        auto Spec = FCk_Chain_Spec(ECk_Chain_Solver::PathHistory);
        Spec.Set_HistorySeed(ECk_Chain_HistorySeed::HoldUntilCovered);
        _F.Chain = utils_chain::Add(_F.Head, Spec);
        auto Empty = utils_chain::Get_PoseAtDistance(_F.Chain, 5.0f);
        _EmptyWasInvalid = !Empty.Get_IsValid();
        _EmptyPoseWasDefault = Empty.Get_Pose().Equals(FTransform::Identity, 0.001);
    }

    UFUNCTION()
    private void Check_Seeded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_F.Chain) && utils_chain::Get_NumHistorySamples(_F.Chain) >= 2);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_EmptyWasInvalid, "empty history is unavailable");
        Assert_True(_EmptyPoseWasDefault, "empty history carries the default pose, not the off-origin head pose");

        auto Uncovered = utils_chain::Get_PoseAtDistance(_F.Chain, 500.0f);
        Assert_False(Uncovered.Get_IsValid(), "HoldUntilCovered distance behind the seed is unavailable");
        Assert_True(Uncovered.Get_Pose().Equals(FTransform::Identity, 0.001), "uncovered result carries the default pose, not the head pose");

        auto Covered = utils_chain::Get_PoseAtDistance(_F.Chain, 5.0f);
        Assert_True(Covered.Get_IsValid(), "distance inside the seed is available");
        Assert_True(Covered.Get_Pose().GetLocation().Equals(_HeadLocation - FVector(5.0, 0.0, 0.0), 0.01), "covered pose lies on the seeded line behind the head");
        FinishSuccess();
    }
}
