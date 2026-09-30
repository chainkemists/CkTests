// Language=angelscript
class UCk_AutoTest_RotateTowards_AllAxesLockedReachesImmediately : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private int32 _ReachedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a turret with all three axes locked", n"Step_Arrange");
        Add_Step_WaitUntil("turret reports at target", n"Check_AtTarget");
        Add_Step("assert it never moved and OnTargetReached fired once", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = _F.Make_DefaultSpec();
        auto Tunables = Spec.Get_Tunables();
        auto Locked = Tunables.Get_Yaw();
        Locked.Set_Mode(ECk_RotateTowards_AxisMode::Locked);
        Tunables.Set_Pitch(Locked);
        Tunables.Set_Yaw(Locked);
        Tunables.Set_Roll(Locked);
        Spec.Set_Tunables(Tunables);

        _F.Init(InHandle, Spec, FVector(32000.0, 0.0, -40000.0));
        Assert_Valid(_F.RotateTowards, "rotate-towards composed");
        utils_rotate_towards::BindTo_OnTargetReached(_F.RotateTowards,
            FCk_Delegate_RotateTowards_OnTargetReached(this, n"OnTargetReached"));
    }

    UFUNCTION()
    private void OnTargetReached(FCk_Handle_RotateTowards InHandle, FCk_Handle_Transform InTarget)
    {
        ++_ReachedCount;
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
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, 0.0, 0.01), f"yaw {Yaw} never moved from 0");
        Assert_Equals_Int(_ReachedCount, 1, "OnTargetReached fired exactly once for a fully locked turret");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_AllAxesLockedReachesImmediately_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_AllAxesLockedReachesImmediately;
    default _TimeoutSeconds = 8.0f;
}
