// Language=angelscript
class UCk_AutoTest_Chain_LateHeadWriteConvergesWithinTwoFrames : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private bool _IssuedLate = false;
    private int64 _LateFrame = 0;
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("prepare late-write probe", n"Step_Arrange");
        Add_Step_WaitUntil("follower settled", n"Check_Ready");
        Add_Step("issue first head write", n"Step_Move");
        Add_Step_WaitUntil("assert convergence deadline", n"Check_Converged");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1) && _F.Location(0).Equals(FVector(-100.0, 0.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Move(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_transform::BindTo_OnUpdate(_F.Head, FCk_Delegate_Transform_OnUpdate(this, n"OnHeadUpdate"));
        _F.Move(FVector(500.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void OnHeadUpdate(FCk_Handle_Transform InHead, FTransform InTransform)
    {
        if (_IssuedLate || !InTransform.GetLocation().Equals(FVector(500.0, 0.0, 0.0), 1.0))
        {
            return;
        }
        _IssuedLate = true;
        _LateFrame = utils_time::Get_FrameCounter();
        _F.Move(FVector(800.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_Converged(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        if (!_IssuedLate)
        {
            Res.Set(false);
            return;
        }
        const auto Elapsed = utils_time::Get_FrameCounter() - _LateFrame;
        const auto Converged = utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector(800.0, 0.0, 0.0), 1.0) && _F.Location(0).Equals(FVector(700.0, 0.0, 0.0), 1.0);
        if (Elapsed > 2 && !Converged)
        {
            Assert_True(false, "late head write must converge within two frames");
            FinishFailure("late head write did not converge within two frames");
            Res.Set(true);
            return;
        }
        if (Converged)
        {
            Assert_True(Elapsed <= 2, "observed convergence within two frames");
            FinishSuccess();
        }
        Res.Set(Converged);
    }
}
