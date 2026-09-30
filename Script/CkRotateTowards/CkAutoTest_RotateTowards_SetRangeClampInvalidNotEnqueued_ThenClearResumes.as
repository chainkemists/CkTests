// Language=angelscript
class UCk_AutoTest_RotateTowards_SetRangeClampInvalidNotEnqueued_ThenClearResumes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Succeeded;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a turret clamped to +-30 deg yaw", n"Step_Arrange");
        Add_Step_WaitUntil("turret reports at target on the range edge", n"Check_AtTarget");
        Add_Step("reject a clamp with no axis enabled, then clear the clamp", n"Step_RejectThenClear");
        Add_Step_WaitUntil("turret turns on to face the target", n"Check_FacesTarget");
        Add_Step("assert the clamp is gone", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.InitWorld(InHandle, FVector(52000.0, 0.0, -40000.0));
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
    private void Step_RejectThenClear(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Yaw = _F.TurretRotation().Yaw;
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, 30.0, 1.0), f"yaw {Yaw} rests on the +30 edge");

        utils_rotate_towards::Request_SetRangeClamp(_F.RotateTowards,
            FCk_Request_RotateTowards_SetRangeClamp(FCk_RotateTowards_RangeClamp()),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 1, "the rejected SetRangeClamp completes synchronously");
        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued, "a clamp with no axis enabled is not enqueued");

        utils_rotate_towards::Request_ClearRangeClamp(_F.RotateTowards, FCk_Request_RotateTowards_ClearRangeClamp());
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Check_FacesTarget(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(CkRotateTowardsAutoTest::Is_Near(_F.TurretRotation().Yaw, 90.0, 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_False(utils_rotate_towards::Get_HasRangeClamp(_F.RotateTowards), "ClearRangeClamp removed the clamp");
        Assert_Equals_Int(_Completions, 1, "the rejected request completed exactly once");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_SetRangeClampInvalidNotEnqueued_ThenClearResumes_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_SetRangeClampInvalidNotEnqueued_ThenClearResumes;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("no axis enabled; use Request_ClearRangeClamp");
        return Errors;
    }
}
