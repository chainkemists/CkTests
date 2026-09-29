// Language=angelscript
class UCk_AutoTest_Sway_AddOnExistingNodeTakesOwnership : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private const FTransform _Rest = FTransform(FVector(60.0, 25.0, -20.0));

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("create a scene node at an offset and add Sway to it", n"Step_Arrange");
        Add_Step_WaitSeconds("let the still parent tick", 0.2f);
        Add_Step("assert the node rests at its adopted offset", n"Step_VerifyRest");
        Add_Step("add Sway to the same node again", n"Step_AddAgain");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.InitParent(InHandle, FVector(14000.0, 0.0, -40000.0));
        _F.Node = utils_scene_node::Create(_F.Parent, _Rest);
        Assert_Valid(_F.Node, "scene node composed");

        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Sway = utils_sway::Add(_F.Node, Spec);
        Assert_Valid(_F.Sway, "Add returns a valid sway handle");
        Assert_True(utils_sway::Get_RestOffset(_F.Sway).Equals(_Rest, 0.001), "the node's current offset becomes the rest offset");
    }

    UFUNCTION()
    private void Step_VerifyRest(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_sway::Get_IsSettled(_F.Sway), "sway is settled on a still parent");
        Assert_True(_F.SwayWorld().Equals(_Rest * _F.ParentWorld(), 0.02), "the node world pose is the rest offset over the parent");
    }

    UFUNCTION()
    private void Step_AddAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        const auto Again = utils_sway::Add(_F.Node, Spec);
        Assert_Invalid(Again, "a second Add on a sway node returns an invalid handle");
        Assert_True(utils_sway::Get_RestOffset(_F.Sway).Equals(_Rest, 0.001), "the rejected Add leaves the first sway untouched");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_AddOnExistingNodeTakesOwnership_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_AddOnExistingNodeTakesOwnership;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("already a sway node");
        return Errors;
    }
}
