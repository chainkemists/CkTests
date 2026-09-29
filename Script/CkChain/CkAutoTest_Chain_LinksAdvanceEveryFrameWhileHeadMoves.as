// Language=angelscript
class UCk_AutoTest_Chain_LinksAdvanceEveryFrameWhileHeadMoves : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private TArray<float> _HeadX;
    private TArray<float> _LinkX;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach one link on a coarse history", n"Step_Arrange");
        Add_Step_WaitUntil("link attached", n"Check_Ready");
        Add_Step("start tween", n"Do_StartTween");
        Add_Step_WaitUntil("head past 300 cm", n"Check_HeadPast300");
        for (int32 Index = 0; Index < 6; ++Index)
        {
            Add_Step(f"sample {Index}", n"Do_Sample");
            Add_Step_WaitFrames("advance one frame", 1);
        }
        Add_Step("assert", n"Do_Assert");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, ECk_Chain_Solver::PathHistory, ECk_Chain_HistorySeed::StraightBehindHead, 0.0f, 25.0f);
        _F.Attach(100.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1));
    }

    UFUNCTION()
    private void Do_StartTween(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.StartTween(FVector(1200.0, 0.0, 0.0), 1.2f);
    }

    UFUNCTION()
    private void Check_HeadPast300(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_transform::Get_EntityCurrentLocation(_F.Head).X > 300.0);
    }

    UFUNCTION()
    private void Do_Sample(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _HeadX.Add(utils_transform::Get_EntityCurrentLocation(_F.Head).X);
        _LinkX.Add(_F.Location(0).X);
    }

    UFUNCTION()
    private void Do_Assert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_HeadX.Num() == 6 && _LinkX.Num() == 6, "six head/link samples recorded");
        for (int32 Index = 0; Index + 1 < _LinkX.Num(); ++Index)
        {
            const int32 Next = Index + 1;
            const float HeadDelta = _HeadX[Next] - _HeadX[Index];
            const float LinkDelta = _LinkX[Next] - _LinkX[Index];
            const float SpeedGap = Math::Abs(LinkDelta - HeadDelta);
            Assert_True(LinkDelta > 0.0f, f"link stalled between samples {Index} and {Next}: link moved {LinkDelta} cm while the head moved {HeadDelta} cm");
            Assert_True(SpeedGap <= 1.0f, f"link speed differs from head speed by {SpeedGap} cm at sample {Index}");
        }
        FinishSuccess();
    }
}
