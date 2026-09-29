// Language=angelscript
class UCk_AutoTest_Sway_RestPoseIsRestOverParent : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private const FTransform _Rest =FTransform(FVector(60.0, 25.0, -20.0));

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway with a rest offset on a still parent", n"Step_Arrange");
        Add_Step_WaitSeconds("let the still parent tick", 0.2f);
        Add_Step("assert the node rests at the rest offset over the parent", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(3000.0, 0.0, -40000.0), _Rest);
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.SwayWorld().Equals(_Rest * _F.ParentWorld(), 0.01), "sway node world pose is the rest offset over the parent at rest");
        Assert_True(utils_sway::Get_IsSettled(_F.Sway), "sway is settled at rest");
        Assert_True(utils_sway::Get_SwayOffset(_F.Sway).Equals(FTransform(), 0.001), "spring offset is identity at rest");
        Assert_True(utils_sway::Get_RestOffset(_F.Sway).Equals(_Rest, 0.001), "the rest offset is the one passed to Create");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_RestPoseIsRestOverParent_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_RestPoseIsRestOverParent;
    default _TimeoutSeconds = 8.0f;
}
