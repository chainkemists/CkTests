namespace ck_test_chain_circle
{
    mixin void AddCircleKey(UCurveFloat InCurve, float InTime, float InValue)
    {
        auto Key = InCurve.AddCurveKey(InTime, InValue);
        InCurve.SetKeyInterpMode(Key, ERichCurveInterpMode::RCIM_Linear, false);
    }
    asset FirstX of UCurveFloat
    {
        AddCircleKey(0.00000f, 0.00000f);
        AddCircleKey(0.03125f, 39.01806f);
        AddCircleKey(0.06250f, 76.53669f);
        AddCircleKey(0.09375f, 111.11405f);
        AddCircleKey(0.12500f, 141.42136f);
        AddCircleKey(0.15625f, 166.29392f);
        AddCircleKey(0.18750f, 184.77591f);
        AddCircleKey(0.21875f, 196.15706f);
        AddCircleKey(0.25000f, 200.00000f);
        AddCircleKey(0.28125f, 196.15706f);
        AddCircleKey(0.31250f, 184.77591f);
        AddCircleKey(0.34375f, 166.29392f);
        AddCircleKey(0.37500f, 141.42136f);
        AddCircleKey(0.40625f, 111.11405f);
        AddCircleKey(0.43750f, 76.53669f);
        AddCircleKey(0.46875f, 39.01806f);
        AddCircleKey(0.50000f, 0.00000f);
    }
    asset FirstY of UCurveFloat
    {
        AddCircleKey(0.00000f, 0.00000f);
        AddCircleKey(0.03125f, 3.84294f);
        AddCircleKey(0.06250f, 15.22409f);
        AddCircleKey(0.09375f, 33.70608f);
        AddCircleKey(0.12500f, 58.57864f);
        AddCircleKey(0.15625f, 88.88595f);
        AddCircleKey(0.18750f, 123.46331f);
        AddCircleKey(0.21875f, 160.98194f);
        AddCircleKey(0.25000f, 200.00000f);
        AddCircleKey(0.28125f, 239.01806f);
        AddCircleKey(0.31250f, 276.53669f);
        AddCircleKey(0.34375f, 311.11405f);
        AddCircleKey(0.37500f, 341.42136f);
        AddCircleKey(0.40625f, 366.29392f);
        AddCircleKey(0.43750f, 384.77591f);
        AddCircleKey(0.46875f, 396.15706f);
        AddCircleKey(0.50000f, 400.00000f);
    }
    asset SecondX of UCurveFloat
    {
        AddCircleKey(0.00000f, 0.00000f);
        AddCircleKey(0.03125f, -39.01806f);
        AddCircleKey(0.06250f, -76.53669f);
        AddCircleKey(0.09375f, -111.11405f);
        AddCircleKey(0.12500f, -141.42136f);
        AddCircleKey(0.15625f, -166.29392f);
        AddCircleKey(0.18750f, -184.77591f);
        AddCircleKey(0.21875f, -196.15706f);
        AddCircleKey(0.25000f, -200.00000f);
        AddCircleKey(0.28125f, -196.15706f);
        AddCircleKey(0.31250f, -184.77591f);
        AddCircleKey(0.34375f, -166.29392f);
        AddCircleKey(0.37500f, -141.42136f);
        AddCircleKey(0.40625f, -111.11405f);
        AddCircleKey(0.43750f, -76.53669f);
        AddCircleKey(0.46875f, -39.01806f);
        AddCircleKey(0.50000f, -0.00000f);
    }
    asset SecondY of UCurveFloat
    {
        AddCircleKey(0.00000f, 0.00000f);
        AddCircleKey(0.03125f, -3.84294f);
        AddCircleKey(0.06250f, -15.22409f);
        AddCircleKey(0.09375f, -33.70608f);
        AddCircleKey(0.12500f, -58.57864f);
        AddCircleKey(0.15625f, -88.88595f);
        AddCircleKey(0.18750f, -123.46331f);
        AddCircleKey(0.21875f, -160.98194f);
        AddCircleKey(0.25000f, -200.00000f);
        AddCircleKey(0.28125f, -239.01806f);
        AddCircleKey(0.31250f, -276.53669f);
        AddCircleKey(0.34375f, -311.11405f);
        AddCircleKey(0.37500f, -341.42136f);
        AddCircleKey(0.40625f, -366.29392f);
        AddCircleKey(0.43750f, -384.77591f);
        AddCircleKey(0.46875f, -396.15706f);
        AddCircleKey(0.50000f, -400.00000f);
    }
}
// Language=angelscript
class UCk_AutoTest_Chain_DistanceConstraintPreservesSegmentLengths : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private int32 _Completions = 0;
    private int32 _Samples = 0;
    private bool _Moved = false;
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("create constrained links", n"Step_Arrange");
        Add_Step_WaitUntil("initial lengths settled", n"Check_Ready");
        Add_Step("start first half-circle tween", n"Step_First");
        Add_Step_WaitUntil("motion observed", n"Check_Motion");
        Add_Step_WaitFrames("sample frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitUntil("first arc completed", n"Check_First");
        Add_Step("start second half-circle tween", n"Step_Second");
        Add_Step_WaitFrames("sample return frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample return frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample return frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample return frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitFrames("sample return frame", 1);
        Add_Step("assert segment lengths", n"Step_Sample");
        Add_Step_WaitUntil("circle completed", n"Check_Complete");
        Add_Step("verify movement and samples", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, ECk_Chain_Solver::DistanceConstraint);
        _F.Attach(100.0f);
        _F.Attach(200.0f);
        _F.Attach(300.0f);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        if (!_F.Ready(3))
        {
            Res.Set(false);
            return;
        }
        auto Previous = utils_transform::Get_EntityCurrentLocation(_F.Head);
        for (int32 Index = 0; Index < 3; ++Index)
        {
            const auto Position = _F.Location(Index);
            if (Math::Abs((Position - Previous).Size() - 100.0) > 0.1)
            {
                Res.Set(false);
                return;
            }
            Previous = Position;
        }
        Res.Set(true);
    }

    UFUNCTION()
    private void Step_First(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Tween = utils_tween::Create_TweenEntityLocation_CurveOffset(_F.Head, FCk_TweenCurveChannels(ck_test_chain_circle::FirstX, ck_test_chain_circle::FirstY, nullptr), 0.5f);
        utils_tween::BindTo_OnComplete(_F.Tween, FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void Check_Motion(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        _Moved = utils_transform::Get_EntityCurrentLocation(_F.Head).Size() > 50.0;
        Res.Set(_Moved);
    }

    UFUNCTION()
    private void Step_Sample(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Previous = utils_transform::Get_EntityCurrentLocation(_F.Head);
        for (int32 Index = 0; Index < 3; ++Index)
        {
            const auto Position = _F.Location(Index);
            Assert_Equals_Float(float32((Position - Previous).Size()), 100.0f, 0.1f, "each constrained segment remains 100cm");
            Previous = Position;
        }
        ++_Samples;
    }

    UFUNCTION()
    private void OnComplete(FCk_Handle_Tween InTween, FCk_Tween_Payload_OnComplete InPayload)
    {
        ++_Completions;
    }

    UFUNCTION()
    private void Check_First(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Completions == 1 && utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector(0.0, 400.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Second(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Tween = utils_tween::Create_TweenEntityLocation_CurveOffset(_F.Head, FCk_TweenCurveChannels(ck_test_chain_circle::SecondX, ck_test_chain_circle::SecondY, nullptr), 0.5f);
        utils_tween::BindTo_OnComplete(_F.Tween, FCk_Delegate_Tween_OnComplete(this, n"OnComplete"));
    }

    UFUNCTION()
    private void Check_Complete(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Completions == 2 && utils_transform::Get_EntityCurrentLocation(_F.Head).Equals(FVector::ZeroVector, 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_Moved, "circle stimulus genuinely moved head");
        Assert_Equals_Int(_Samples, 10, "ten frame-separated constraint samples");
        auto Previous = utils_transform::Get_EntityCurrentLocation(_F.Head);
        Assert_True(Previous.Equals(FVector::ZeroVector, 1.0), "circle endpoint returns to origin");
        for (int32 Index = 0; Index < 3; ++Index)
        {
            const auto Position = _F.Location(Index);
            Assert_Equals_Float(float32((Position - Previous).Size()), 100.0f, 0.1f, "endpoint segment length");
            Previous = Position;
        }
        FinishSuccess();
    }
}
