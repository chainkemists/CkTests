// Language=angelscript
class UCk_AutoTest_RotateTowards_InstantModeSnapsAndFiresReached : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private int32 _ReachedCount = 0;
    private float _FirstObservedYaw = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose an Instant turret with its target 90 deg to the right", n"Step_Arrange");
        Add_Step_WaitUntil("turret reports at target", n"Check_AtTarget");
        Add_Step("assert it had snapped to the target when first observed at target", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = _F.Make_DefaultSpec();
        auto Tunables = Spec.Get_Tunables();
        Tunables.Set_Mode(ECk_RotateTowards_Mode::Instant);
        Spec.Set_Tunables(Tunables);

        _F.Init(InHandle, Spec, FVector(24000.0, 0.0, -40000.0));
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
        if (utils_rotate_towards::Get_IsAtTarget(_F.RotateTowards) == false)
        {
            Res.Set(false);
            return;
        }
        _FirstObservedYaw = _F.TurretRotation().Yaw;
        Res.Set(true);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(CkRotateTowardsAutoTest::Is_Near(_FirstObservedYaw, 90.0, 0.01),
            f"yaw {_FirstObservedYaw} is within 0.01 deg of 90 on the first observation at target");
        Assert_Equals_Int(_ReachedCount, 1, "OnTargetReached fired exactly once");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_InstantModeSnapsAndFiresReached_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_InstantModeSnapsAndFiresReached;
    default _TimeoutSeconds = 8.0f;
}
