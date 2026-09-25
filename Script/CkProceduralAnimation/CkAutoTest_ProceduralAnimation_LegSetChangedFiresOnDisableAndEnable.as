// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_LegSetChangedFiresOnDisableAndEnable : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 80000.0, 600.0);
    private TArray<int32> _EnabledCounts;
    private TArray<int32> _TotalCounts;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated single-walker floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the walker is composed and evaluated", n"Check_Ready", 1200);
        Add_Step("bind the leg-set signal and disable leg 0", n"Step_Disable");
        Add_Step_WaitUntil("the signal reports the disable", n"Check_FirstChange");
        // Three frames of gait updates after the first fire: a repeated broadcast would land here.
        Add_Step_WaitFrames("no further change is reported while leg 0 stays disabled", 3);
        Add_Step("enable leg 0", n"Step_Enable");
        Add_Step_WaitUntil("the signal reports the enable", n"Check_SecondChange");
        Add_Step_WaitFrames("no further change is reported while every leg is enabled", 3);
        Add_Step("verify the two reported leg sets", n"Step_Verify");
        Add_Step_WaitUntil("the fixture is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"The walker could not be composed: {_Fixture.CompositionError}");
            return;
        }
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsReady());
    }

    UFUNCTION()
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Gait = _Fixture.Crawlers[0].Gait;
        utils_procedural_gait::BindTo_OnLegSetChanged(Gait, FCk_Delegate_ProceduralGait_OnLegSetChanged(this, n"OnLegSetChanged"));
        auto Leg = _Fixture.Crawlers[0].Legs[0];
        utils_procedural_leg::Request_EnableDisable(Leg, FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Disable));
    }

    UFUNCTION()
    private void OnLegSetChanged(FCk_Handle_ProceduralGait InGait, int32 InEnabledCount, int32 InTotalCount)
    {
        _EnabledCounts.Add(InEnabledCount);
        _TotalCounts.Add(InTotalCount);
    }

    UFUNCTION()
    private void Check_FirstChange(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(_EnabledCounts.Num() >= 1);
    }

    UFUNCTION()
    private void Step_Enable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_EnabledCounts.Num(), 1, "Disabling one leg reports exactly one leg-set change");
        auto Leg = _Fixture.Crawlers[0].Legs[0];
        utils_procedural_leg::Request_EnableDisable(Leg, FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Enable));
    }

    UFUNCTION()
    private void Check_SecondChange(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(_EnabledCounts.Num() >= 2);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_EnabledCounts.Num(), 2, "The signal fires exactly twice: once per enabled-set change");
        if (_EnabledCounts.Num() == 2)
        {
            Assert_Equals_Int(_EnabledCounts[0], 3, "The disable reports three enabled legs");
            Assert_Equals_Int(_TotalCounts[0], 4, "The disable reports four authored legs");
            Assert_Equals_Int(_EnabledCounts[1], 4, "The enable reports four enabled legs");
            Assert_Equals_Int(_TotalCounts[1], 4, "The enable reports four authored legs");
        }
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
