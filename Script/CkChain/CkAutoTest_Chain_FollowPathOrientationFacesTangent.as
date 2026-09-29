// Language=angelscript
class UCk_AutoTest_Chain_FollowPathOrientationFacesTangent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private bool _TweenComplete = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach corner-path link", n"Step_Arrange");
        Add_Step_WaitUntil("roster ready", n"Check_Ready");
        Add_Step("tween +X", n"Step_FirstLeg");
        Add_Step_WaitUntil("first tween completes", n"Check_Tween");
        Add_Step("tween +Y", n"Step_SecondLeg");
        Add_Step_WaitUntil("second tween completes", n"Check_Tween");
        Add_Step_WaitUntil("corner placement observed", n"Check_Placed");
        Add_Step("assert corner contract", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(300.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1));
    }

    UFUNCTION()
    private void Step_FirstLeg(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TweenComplete = false;
        _F.StartTween(FVector(500.0, 0.0, 0.0));
        utils_tween::BindTo_OnComplete(_F.Tween, FCk_Delegate_Tween_OnComplete(this, n"OnTweenComplete"));
    }

    UFUNCTION()
    private void Step_SecondLeg(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TweenComplete = false;
        _F.StartTween(FVector(500.0, 500.0, 0.0));
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
        Res.Set(_F.Location(0).Equals(FVector(500.0, 200.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(float32(utils_transform::Get_EntityCurrentRotation(_F.Links[0]).Yaw), 90.0f, 1.0f, "FollowPath faces +Y tangent");
        FinishSuccess();
    }
}
