// Language=angelscript
class UCk_AutoTest_RotateTowards_ClearTargetFiresClearedRequested : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private int32 _ClearedCount = 0;
    private FCk_Handle_Transform _ClearedPrevious;
    private ECk_RotateTowards_ClearReason _ClearedReason = ECk_RotateTowards_ClearReason::TargetLost;
    private float _YawAfterClear = 0.0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a turret turning towards its target", n"Step_Arrange");
        Add_Step_WaitSeconds("turn part of the way", 0.3f);
        Add_Step("clear the target mid-turn", n"Step_Clear");
        Add_Step_WaitUntil("OnTargetCleared fires", n"Check_Cleared");
        Add_Step("capture the yaw the turret holds", n"Step_Capture");
        // Negative window: the capture above proves the turret had been turning, so an unchanged yaw here is a hold.
        Add_Step_WaitSeconds("window in which a cleared turret must not turn", 0.3f);
        Add_Step("assert the clear payload and that the yaw held", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, _F.Make_DefaultSpec(), FVector(40000.0, 0.0, -40000.0));
        Assert_Valid(_F.RotateTowards, "rotate-towards composed");
        utils_rotate_towards::BindTo_OnTargetCleared(_F.RotateTowards,
            FCk_Delegate_RotateTowards_OnTargetCleared(this, n"OnTargetCleared"));
    }

    UFUNCTION()
    private void OnTargetCleared(FCk_Handle_RotateTowards InHandle, FCk_Handle_Transform InPreviousTarget, ECk_RotateTowards_ClearReason InReason)
    {
        ++_ClearedCount;
        _ClearedPrevious = InPreviousTarget;
        _ClearedReason = InReason;
    }

    UFUNCTION()
    private void Step_Clear(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_rotate_towards::Request_ClearTarget(_F.RotateTowards, FCk_Request_RotateTowards_ClearTarget());
    }

    UFUNCTION()
    private void Check_Cleared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ClearedCount >= 1);
    }

    UFUNCTION()
    private void Step_Capture(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _YawAfterClear = _F.TurretRotation().Yaw;
        Assert_True(_YawAfterClear > 5.0, f"yaw {_YawAfterClear} shows the turret was turning before the clear");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Yaw = _F.TurretRotation().Yaw;
        Assert_Equals_Int(_ClearedCount, 1, "OnTargetCleared fired exactly once");
        Assert_True(_ClearedReason == ECk_RotateTowards_ClearReason::Requested, "the clear reason is Requested");
        Assert_True(_ClearedPrevious == _F.Target, "the previous target is the cleared target");
        Assert_False(utils_rotate_towards::Get_HasTarget(_F.RotateTowards), "no target after the clear");
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, _YawAfterClear, 0.05), f"yaw {Yaw} held at {_YawAfterClear}");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_ClearTargetFiresClearedRequested_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_ClearTargetFiresClearedRequested;
    default _TimeoutSeconds = 8.0f;
}
