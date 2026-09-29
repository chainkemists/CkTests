// Language=angelscript
class UCk_AutoTest_Sway_SettlesAfterParentStops : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        // Setup seeds the previous parent pose from the parent's CURRENT pose; a turn issued before Setup has run
        // would be absorbed into that seed and produce no stimulus. Setup completion is not observable, hence a settle.
        Add_Step_WaitSeconds("let Setup seed the previous parent pose", 0.1f);
        Add_Step("turn the parent +45 deg and stop", n"Step_Turn");
        // Positive precondition (CkTests wait rule 1): "settled" is also true if the spring never moved.
        Add_Step_WaitUntil("spring displaced by the turn", n"Check_Displaced");
        Add_Step_WaitSeconds("parent stays still", 0.1f);
        Add_Step_WaitUntil("spring settles back to rest", n"Check_Settled");
        // The node's composed pose trails Get_Offset by one frame (CkSway DESIGN section 6); gate on that stage.
        Add_Step_WaitUntil("node pose rejoins the parent", n"Check_Rejoined");
        Add_Step("assert the offset returned to identity", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(6000.0, 0.0, -40000.0));
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
        Res.Set(utils_sway::Get_RotationOffset(_F.Sway).Yaw < -0.05);
    }

    UFUNCTION()
    private void Check_Settled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_sway::Get_IsSettled(_F.Sway));
    }

    UFUNCTION()
    private void Check_Rejoined(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.SwayWorld().Equals(_F.ParentWorld(), 0.05));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_sway::Get_SwayOffset(_F.Sway).Equals(FTransform(), 0.02), "settled offset is identity");
        Assert_True(_F.SwayWorld().Equals(_F.ParentWorld(), 0.05), "settled node rests on the parent");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_SettlesAfterParentStops_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_SettlesAfterParentStops;
    default _TimeoutSeconds = 8.0f;
}
