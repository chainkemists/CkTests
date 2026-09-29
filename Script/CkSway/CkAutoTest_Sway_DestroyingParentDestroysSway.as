// Language=angelscript
class UCk_AutoTest_Sway_DestroyingParentDestroysSway : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        Add_Step("destroy the parent", n"Step_Destroy");
        Add_Step_WaitSeconds("let the destruction pipeline run", 0.1f);
        Add_Step("assert the sway went with its parent", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(11000.0, 0.0, -40000.0));
        // Positive precondition (CkTests wait rule 1) for the validity negatives below.
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_lifetime::Request_DestroyEntity(_F.Parent);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(ck::Is_NOT_Valid(_F.Sway), "the sway node is destroyed with its parent");
        Assert_True(ck::Is_NOT_Valid(_F.Parent), "the parent is destroyed");
        Assert_True(ck::IsValid(_F.Root), "the root survives");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_DestroyingParentDestroysSway_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_DestroyingParentDestroysSway;
    default _TimeoutSeconds = 8.0f;
}
