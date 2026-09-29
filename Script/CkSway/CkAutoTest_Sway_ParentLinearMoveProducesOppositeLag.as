// Language=angelscript
class UCk_AutoTest_Sway_ParentLinearMoveProducesOppositeLag : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private float _ObservedX = 0.0f;
    private float _ObservedVelocityX = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        // Setup seeds the previous parent pose from the parent's CURRENT pose; a move issued before Setup has run
        // would be absorbed into that seed and produce no stimulus. Setup completion is not observable, hence a settle.
        Add_Step_WaitSeconds("let Setup seed the previous parent pose", 0.1f);
        Add_Step("move the parent +300 cm on X in one frame", n"Step_Move");
        Add_Step_WaitUntil("location channel lags opposite the move", n"Check_Lagging");
        Add_Step("assert the lag is bounded and driven by a positive X velocity", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(5000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_Move(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.MoveParent(FVector(300.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_Lagging(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto X = utils_sway::Get_LocationOffset(_F.Sway).X;
        if (X >= -0.05)
        {
            Res.Set(false);
            return;
        }
        // Captured at the moment of the first observation: the stimulus is only set on the frame the parent moved.
        _ObservedX = X;
        _ObservedVelocityX = utils_sway::Get_LastStimulus(_F.Sway).Get_LinearVelocity().X;
        Res.Set(true);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto MaxX = utils_sway::Get_Spec(_F.Sway).Get_Location().Get_Max().X;
        Assert_True(_ObservedX >= -MaxX - 0.001, f"X offset {_ObservedX} stays inside the {MaxX} cm clamp");
        Assert_True(_ObservedVelocityX > 0.0, f"stimulus X velocity {_ObservedVelocityX} is positive for a +X move");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_ParentLinearMoveProducesOppositeLag_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_ParentLinearMoveProducesOppositeLag;
    default _TimeoutSeconds = 8.0f;
}
