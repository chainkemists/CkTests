// Language=angelscript
class UCk_AutoTest_RotateTowards_DisableHoldsThenEnableResumes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a disabled turret with a target", n"Step_Arrange");
        // Negative window; the enabled turn asserted at the end proves the same turret would have moved.
        Add_Step_WaitSeconds("window in which a disabled turret must not turn", 0.3f);
        Add_Step("assert the yaw held, then enable", n"Step_VerifyHeldThenEnable");
        Add_Step_WaitUntil("turret reports at target", n"Check_AtTarget");
        Add_Step("assert it turned to face the target", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = _F.Make_DefaultSpec();
        Spec.Set_StartingState(ECk_EnableDisable::Disable);
        _F.Init(InHandle, Spec, FVector(56000.0, 0.0, -40000.0));
        Assert_Valid(_F.RotateTowards, "rotate-towards composed");
        Assert_False(utils_rotate_towards::Get_IsEnabled(_F.RotateTowards), "the starting state is Disable");
    }

    UFUNCTION()
    private void Step_VerifyHeldThenEnable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Yaw = _F.TurretRotation().Yaw;
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, 0.0, 0.05), f"disabled yaw {Yaw} held at 0");
        utils_rotate_towards::Request_EnableDisable(_F.RotateTowards,
            FCk_Request_RotateTowards_EnableDisable(ECk_EnableDisable::Enable));
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
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, 90.0, 1.0), f"yaw {Yaw} is within 1 deg of 90 after enabling");
        Assert_True(utils_rotate_towards::Get_IsEnabled(_F.RotateTowards), "enabled");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_DisableHoldsThenEnableResumes_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_DisableHoldsThenEnableResumes;
    default _TimeoutSeconds = 8.0f;
}
