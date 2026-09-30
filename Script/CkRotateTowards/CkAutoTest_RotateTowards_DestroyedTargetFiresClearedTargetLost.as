// Language=angelscript
class UCk_AutoTest_RotateTowards_DestroyedTargetFiresClearedTargetLost : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private int32 _ClearedCount = 0;
    private FCk_Handle_Transform _ClearedPrevious;
    private ECk_RotateTowards_ClearReason _ClearedReason = ECk_RotateTowards_ClearReason::Requested;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose a turret turning towards its target", n"Step_Arrange");
        Add_Step_WaitSeconds("turn part of the way", 0.3f);
        Add_Step("destroy the target mid-turn", n"Step_Destroy");
        Add_Step_WaitUntil("OnTargetCleared fires", n"Check_Cleared");
        Add_Step("assert the loss is reported as TargetLost", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, _F.Make_DefaultSpec(), FVector(44000.0, 0.0, -40000.0));
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
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_F.Target);
    }

    UFUNCTION()
    private void Check_Cleared(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_ClearedCount >= 1);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_ClearedCount, 1, "OnTargetCleared fired exactly once");
        Assert_True(_ClearedReason == ECk_RotateTowards_ClearReason::TargetLost, "the clear reason is TargetLost");
        Assert_True(ck::Is_NOT_Valid(_ClearedPrevious), "the previous target handle is dead");
        Assert_False(utils_rotate_towards::Get_HasTarget(_F.RotateTowards), "no target after the loss");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_DestroyedTargetFiresClearedTargetLost_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_DestroyedTargetFiresClearedTargetLost;
    default _TimeoutSeconds = 8.0f;
}
