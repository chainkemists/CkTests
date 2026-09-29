// Language=angelscript
class UCk_AutoTest_Sway_SetRestOffsetMovesRestWithoutEnsure : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private const FTransform _NewRest = FTransform(FVector(0.0, 0.0, 30.0));
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        Add_Step_WaitSeconds("let Setup adopt the node offset", 0.1f);
        Add_Step("request a new rest offset", n"Step_SetRest");
        // No expected error is registered: a foreign-write ensure from Sway's own republish would fail this row.
        Add_Step_WaitUntil("node moves onto the new rest", n"Check_AtNewRest");
        Add_Step("assert the request succeeded once", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(15000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_SetRest(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_sway::Request_SetRestOffset(_F.Sway, FCk_Request_Sway_SetRestOffset(_NewRest),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Check_AtNewRest(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.SwayWorld().Equals(_NewRest * _F.ParentWorld(), 0.05));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "SetRestOffset completes exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "SetRestOffset succeeded");
        Assert_True(utils_sway::Get_RestOffset(_F.Sway).Equals(_NewRest, 0.001), "the new rest offset is retained");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_SetRestOffsetMovesRestWithoutEnsure_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_SetRestOffsetMovesRestWithoutEnsure;
    default _TimeoutSeconds = 8.0f;
}
