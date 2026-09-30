// Language=angelscript
class UCk_AutoTest_RotateTowards_RangeClampLimitsYaw : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a turret clamped to +-30 deg yaw about a rest line straight ahead", n"Step_Arrange");
        Add_Step_WaitUntil("turret reports at target", n"Check_AtTarget");
        Add_Step("assert it stopped at the +30 deg range edge", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.InitWorld(InHandle, FVector(48000.0, 0.0, -40000.0));
        auto Spec = _F.Make_DefaultSpec();
        Spec.Set_Target(_F.Target);
        Spec.Set_RangeClamp(CkRotateTowardsAutoTest::Make_YawClamp(_F.RestPoint, -30.0f, 30.0f));
        _F.RotateTowards = utils_rotate_towards::Add(_F.Turret, Spec);
        Assert_Valid(_F.RotateTowards, "rotate-towards composed");
    }

    UFUNCTION()
    private void Check_AtTarget(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_rotate_towards::Get_IsAtTarget(_F.RotateTowards));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Yaw = _F.TurretRotation().Yaw;
        const auto DesiredYaw = utils_rotate_towards::Get_DesiredRotation(_F.RotateTowards).Yaw;
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, 30.0, 1.0), f"yaw {Yaw} is within 1 deg of the +30 edge");
        Assert_True(utils_rotate_towards::Get_HasRangeClamp(_F.RotateTowards), "the range clamp is present");
        Assert_True(CkRotateTowardsAutoTest::Is_Near(DesiredYaw, 30.0, 0.5), f"desired yaw {DesiredYaw} is clamped to 30");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_RangeClampLimitsYaw_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_RangeClampLimitsYaw;
    default _TimeoutSeconds = 8.0f;
}
