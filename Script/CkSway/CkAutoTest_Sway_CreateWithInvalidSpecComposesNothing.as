// Language=angelscript
class UCk_AutoTest_Sway_CreateWithInvalidSpecComposesNothing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("create with a negative teleport distance", n"Step_Create");
        Add_Step_WaitSeconds("exclude delayed composition", 0.1f);
        Add_Step("assert no scene node was created under the parent", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Create(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(-1.0f);
        _F.Init(InHandle, Spec, FVector(2000.0, 0.0, -40000.0));
        Assert_Valid(_F.Parent, "the parent itself is valid, so only the spec can be rejected");
        Assert_Invalid(_F.Sway, "Create with an invalid spec returns an invalid handle synchronously");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Invalid(_F.Sway, "Create with an invalid spec stays uncomposed");
        Assert_Equals_Int(utils_scene_node::ForEach_SceneNode(_F.Parent, FInstancedStruct()).Num(), 0,
            "the spec is rejected before any scene node exists under the parent");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_CreateWithInvalidSpecComposesNothing_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_CreateWithInvalidSpecComposesNothing;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Sway Create rejected invalid spec");
        return Errors;
    }
}
