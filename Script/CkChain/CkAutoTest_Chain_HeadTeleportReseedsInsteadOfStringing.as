// Language=angelscript
class UCk_AutoTest_Chain_HeadTeleportReseedsInsteadOfStringing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _Teleports = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach teleport follower", n"Step_Arrange");
        Add_Step_WaitUntil("seed placement ready", n"Check_Ready");
        Add_Step("teleport and rotate head", n"Step_Teleport");
        Add_Step_WaitUntil("teleport reseed observed", n"Check_Reseeded");
        Add_Step_WaitSeconds("exclude repeated teleport signal", 0.1f);
        Add_Step("assert reseeded basis", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, ECk_Chain_Solver::PathHistory, ECk_Chain_HistorySeed::StraightBehindHead, 500.0f);
        _F.Attach(100.0f);
        utils_chain::BindTo_OnHeadTeleported(_F.Chain, FCk_Delegate_Chain_OnHeadTeleported(this, n"OnTeleported"));
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1) && _F.Location(0).Equals(FVector(-100.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Teleport(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Rotating the jump differentiates reseeding from the old +X chord.
        utils_transform::Request_SetTransform(_F.Head, FCk_Request_Transform_SetTransform(FTransform(FRotator(0.0, 90.0, 0.0), FVector(2000.0, 0.0, 0.0), FVector::OneVector)));
    }

    UFUNCTION()
    private void OnTeleported(FCk_Handle_Chain InChain, FCk_Chain_Payload_HeadTeleported InPayload)
    {
        Assert_True(InChain == _F.Chain, "teleport signal identifies chain");
        Assert_True(InPayload.Get_To().Equals(FVector(2000.0, 0.0, 0.0), 1.0), "teleport destination payload");
        ++_Teleports;
    }

    UFUNCTION()
    private void Check_Reseeded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Teleports > 0 && _F.Location(0).Equals(FVector(2000.0, -100.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Teleports, 1, "one teleport signal");
        Assert_True(_F.Location(0).Equals(FVector(2000.0, -100.0, 0.0), 1.0), "follower uses new head-forward seed");
        Assert_False(_F.Location(0).Equals(FVector(1900.0, 0.0, 0.0), 1.0), "old chord is discarded");
        FinishSuccess();
    }
}
