// Language=angelscript
class UCk_AutoTest_Sway_ForeignOffsetWriteIsReportedAndOverridden : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        Add_Step_WaitSeconds("let the sway settle into ownership of its offset", 0.1f);
        Add_Step("write the sway node offset from outside Sway", n"Step_ForeignWrite");
        Add_Step_WaitSeconds("let Sway detect and overwrite the foreign offset", 0.2f);
        Add_Step("assert Sway reclaimed its offset", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(12000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_ForeignWrite(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_scene_node::Request_UpdateOffset(_F.Sway.As_SceneNode(),
            FCk_Request_SceneNode_UpdateRelativeTransform(FTransform(FVector(50.0, 0.0, 0.0))));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_sway::Get_SwayOffset(_F.Sway).Equals(FTransform(), 0.02), "Sway's spring offset is identity after the overwrite");
        Assert_True(_F.SwayWorld().Equals(_F.ParentWorld(), 0.05), "the node rests on the parent again");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_ForeignOffsetWriteIsReportedAndOverridden_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_ForeignOffsetWriteIsReportedAndOverridden;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("offset was written by something other than Sway");
        return Errors;
    }
}
