// Language=angelscript
class UCk_AutoTest_Sway_ResetSnapsToRest : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        // Setup seeds the previous parent pose from the parent's CURRENT pose; a turn issued before Setup has run
        // would be absorbed into that seed and produce no stimulus. Setup completion is not observable, hence a settle.
        Add_Step_WaitSeconds("let Setup seed the previous parent pose", 0.1f);
        Add_Step("turn the parent +45 deg", n"Step_Turn");
        Add_Step_WaitUntil("spring clearly displaced", n"Check_Displaced");
        Add_Step("request Reset", n"Step_Reset");
        Add_Step_WaitSeconds("let the Reset drain", 0.05f);
        Add_Step("assert the sway snapped to rest", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(8000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_Turn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.TurnParent(45.0f);
    }

    UFUNCTION()
    private void Check_Displaced(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_sway::Get_RotationOffset(_F.Sway).Yaw < -0.5);
    }

    UFUNCTION()
    private void Step_Reset(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_sway::Request_Reset(_F.Sway, FCk_Request_Sway_Reset(), FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "Reset completes exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "Reset succeeded");
        Assert_True(utils_sway::Get_IsSettled(_F.Sway), "sway is settled after Reset");
        Assert_True(utils_sway::Get_SwayOffset(_F.Sway).Equals(FTransform(), 0.001), "offset is identity after Reset");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_ResetSnapsToRest_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_ResetSnapsToRest;
    default _TimeoutSeconds = 8.0f;
}
