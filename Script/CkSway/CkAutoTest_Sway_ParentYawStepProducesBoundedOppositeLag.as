// Language=angelscript
class UCk_AutoTest_Sway_ParentYawStepProducesBoundedOppositeLag : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private float _ObservedYaw = 0.0f;
    private float _ObservedYawRate = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway with a 6 deg rotation clamp", n"Step_Arrange");
        // Setup seeds the previous parent pose from the parent's CURRENT pose; a turn issued before Setup has run
        // would be absorbed into that seed and produce no stimulus. Setup completion is not observable, hence a settle.
        Add_Step_WaitSeconds("let Setup seed the previous parent pose", 0.1f);
        Add_Step("turn the parent +45 deg in one frame", n"Step_Turn");
        Add_Step_WaitUntil("rotation channel lags opposite the turn", n"Check_Lagging");
        Add_Step("assert the lag is bounded and driven by a positive yaw rate", n"Step_VerifyChannel");
        // CkSway DESIGN section 6: the offset computed in frame N reaches the node's composed pose in frame N+1, so the
        // world-pose assertion gates on its own stage instead of the channel's (CkTests wait rule 3).
        Add_Step_WaitUntil("sway node world yaw trails the parent's", n"Check_Composed");
        Add_Step("finish", n"Step_Finish");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        auto Rotation = Spec.Get_Rotation();
        Rotation.Set_Max(FVector(6.0, 6.0, 6.0));
        Spec.Set_Rotation(Rotation);
        _F.Init(InHandle, Spec, FVector(4000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_Turn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.TurnParent(45.0f);
    }

    UFUNCTION()
    private void Check_Lagging(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto Yaw = utils_sway::Get_RotationOffset(_F.Sway).Yaw;
        if (Yaw >= -0.05)
        {
            Res.Set(false);
            return;
        }
        // Captured at the moment of the first observation: the stimulus is only set on the frame the parent moved.
        _ObservedYaw = Yaw;
        _ObservedYawRate = utils_sway::Get_LastStimulus(_F.Sway).Get_AngularVelocityDeg().Z;
        Res.Set(true);
    }

    UFUNCTION()
    private void Step_VerifyChannel(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_ObservedYaw >= -6.001, f"yaw offset {_ObservedYaw} stays inside the 6 deg clamp");
        Assert_True(_ObservedYawRate > 0.0, f"stimulus yaw rate {_ObservedYawRate} is positive for a +45 deg turn");
    }

    UFUNCTION()
    private void Check_Composed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.SwayWorld().Rotator().Yaw < _F.ParentWorld().Rotator().Yaw - 0.01);
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_ParentYawStepProducesBoundedOppositeLag_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_ParentYawStepProducesBoundedOppositeLag;
    default _TimeoutSeconds = 8.0f;
}
