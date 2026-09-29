// Language=angelscript
class UCk_AutoTest_Chain_LinksTrailHeadAlongStraightLine : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private bool _TweenComplete = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach two trailing links", n"Step_Arrange");
        Add_Step_WaitUntil("roster ready", n"Check_Ready");
        Add_Step("tween head through straight line", n"Step_Move");
        Add_Step_WaitUntil("tween completes", n"Check_Tween");
        Add_Step_WaitUntil("links reach final placement", n"Check_Placed");
        Add_Step("assert straight trail", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
        _F.Attach(200.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(2));
    }

    UFUNCTION()
    private void Step_Move(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TweenComplete = false;
        _F.StartTween(FVector(1000.0, 0.0, 0.0));
        utils_tween::BindTo_OnComplete(_F.Tween, FCk_Delegate_Tween_OnComplete(this, n"OnTweenComplete"));
    }

    UFUNCTION()
    private void OnTweenComplete(FCk_Handle_Tween InTween, FCk_Tween_Payload_OnComplete InPayload)
    {
        _TweenComplete = true;
    }

    UFUNCTION()
    private void Check_Tween(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_TweenComplete);
    }

    UFUNCTION()
    private void Check_Placed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Location(0).Equals(FVector(900.0, 0.0, 0.0), 1.0) && _F.Location(1).Equals(FVector(800.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_TweenComplete, "tween completion observed");
        Assert_True(_F.Location(0).Equals(FVector(900.0, 0.0, 0.0), 1.0), "first link trails by100");
        Assert_True(_F.Location(1).Equals(FVector(800.0, 0.0, 0.0), 1.0), "second link trails by200");
        FinishSuccess();
    }
}
