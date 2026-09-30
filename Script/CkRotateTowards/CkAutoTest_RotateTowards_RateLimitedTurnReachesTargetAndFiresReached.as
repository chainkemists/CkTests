// Language=angelscript
class UCk_AutoTest_RotateTowards_RateLimitedTurnReachesTargetAndFiresReached : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private int32 _ReachedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a 90 deg/s turret with its target 90 deg to the right", n"Step_Arrange");
        Add_Step_WaitSeconds("turn for 0.3 s", 0.3f);
        Add_Step("assert the turret is part way round and not yet at target", n"Step_VerifyTurning");
        Add_Step_WaitUntil("turret reaches its target", n"Check_AtTarget");
        Add_Step("assert it faces the target and OnTargetReached fired once", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, _F.Make_DefaultSpec(), FVector(20000.0, 0.0, -40000.0));
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
    private void Step_VerifyTurning(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Yaw = _F.TurretRotation().Yaw;
        Assert_True(Yaw > 5.0 && Yaw < 60.0, f"yaw {Yaw} is part way round after 0.3 s at 90 deg/s");
        Assert_False(utils_rotate_towards::Get_IsAtTarget(_F.RotateTowards), "not at target while turning");
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
        const auto RemainingYaw = utils_rotate_towards::Get_RemainingRotation(_F.RotateTowards).Yaw;
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, 90.0, 1.0), f"yaw {Yaw} is within 1 deg of 90");
        Assert_Equals_Int(_ReachedCount, 1, "OnTargetReached fired exactly once");
        Assert_True(Math::Abs(RemainingYaw) <= 1.0, f"remaining yaw {RemainingYaw} is within the tolerance");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_RateLimitedTurnReachesTargetAndFiresReached_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_RateLimitedTurnReachesTargetAndFiresReached;
    default _TimeoutSeconds = 8.0f;
}
