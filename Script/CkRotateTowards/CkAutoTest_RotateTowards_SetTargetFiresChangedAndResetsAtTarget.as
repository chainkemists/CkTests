// Language=angelscript
class UCk_AutoTest_RotateTowards_SetTargetFiresChangedAndResetsAtTarget : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private FCk_Handle_Transform _Second;
    private int32 _ChangedCount = 0;
    private FCk_Handle_Transform _ChangedNew;
    private FCk_Handle_Transform _ChangedPrevious;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a turret facing its first target", n"Step_Arrange");
        Add_Step_WaitUntil("turret reaches its first target", n"Check_AtTarget");
        Add_Step("retarget to a second target behind the turret", n"Step_Retarget");
        Add_Step_WaitUntil("AtTarget clears on the retarget", n"Check_NotAtTarget");
        Add_Step("request the same target again", n"Step_RepeatRetarget");
        // A repeat SetTarget is a no-op: a positive OnTargetChanged was already observed above, so an unchanged count
        // over this window is meaningful (CkTests wait rule 1).
        Add_Step_WaitSeconds("window for a spurious second OnTargetChanged", 0.2f);
        Add_Step("assert OnTargetChanged fired once with the new and previous targets", n"Step_VerifyChanged");
        Add_Step_WaitUntil("turret turns to face the second target", n"Check_FacesSecond");
        Add_Step("finish", n"Step_Finish");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, _F.Make_DefaultSpec(), FVector(36000.0, 0.0, -40000.0));
        Assert_Valid(_F.RotateTowards, "rotate-towards composed");
    }

    UFUNCTION()
    private void Check_AtTarget(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_rotate_towards::Get_IsAtTarget(_F.RotateTowards));
    }

    UFUNCTION()
    private void Step_Retarget(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_rotate_towards::BindTo_OnTargetChanged(_F.RotateTowards,
            FCk_Delegate_RotateTowards_OnTargetChanged(this, n"OnTargetChanged"));
        _Second = utils_transform::Create(_F.Root, FTransform(_F.Origin + FVector(-1000.0, 0.0, 0.0)), ECk_Replication::DoesNotReplicate);
        utils_rotate_towards::Request_SetTarget(_F.RotateTowards, FCk_Request_RotateTowards_SetTarget(_Second));
    }

    UFUNCTION()
    private void OnTargetChanged(FCk_Handle_RotateTowards InHandle, FCk_Handle_Transform InNewTarget, FCk_Handle_Transform InPreviousTarget)
    {
        ++_ChangedCount;
        _ChangedNew = InNewTarget;
        _ChangedPrevious = InPreviousTarget;
    }

    UFUNCTION()
    private void Check_NotAtTarget(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_rotate_towards::Get_IsAtTarget(_F.RotateTowards) == false);
    }

    UFUNCTION()
    private void Step_RepeatRetarget(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_rotate_towards::Request_SetTarget(_F.RotateTowards, FCk_Request_RotateTowards_SetTarget(_Second));
    }

    UFUNCTION()
    private void Step_VerifyChanged(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_ChangedCount, 1, "OnTargetChanged fired once; the repeat SetTarget is a no-op");
        Assert_True(_ChangedNew == _Second, "OnTargetChanged carries the new target");
        Assert_True(_ChangedPrevious == _F.Target, "OnTargetChanged carries the previous target");
        Assert_True(utils_rotate_towards::Get_Target(_F.RotateTowards) == _Second, "Get_Target returns the second target");
    }

    UFUNCTION()
    private void Check_FacesSecond(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(CkRotateTowardsAutoTest::Is_Near(_F.TurretRotation().Yaw, 180.0, 1.0));
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_SetTargetFiresChangedAndResetsAtTarget_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_SetTargetFiresChangedAndResetsAtTarget;
    default _TimeoutSeconds = 8.0f;
}
