// Language=angelscript
class UCk_AutoTest_Sway_DisableRelaxesAndIgnoresMotion : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private float _TurnedYaw = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway and request Disable", n"Step_Arrange");
        Add_Step_WaitSeconds("let the Disable request drain", 0.1f);
        Add_Step("turn the parent +60 deg", n"Step_Turn");
        // Negative window (CkTests wait rule 1): the positives are the Succeeded completion and the parent's turn.
        Add_Step_WaitSeconds("observe the disabled sway through the turn", 0.3f);
        Add_Step("assert disabled sway ignored the turn", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(7000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
        utils_sway::Request_EnableDisable(_F.Sway, FCk_Request_Sway_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Step_Turn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _TurnedYaw = _F.ParentWorld().Rotator().Yaw + 60.0;
        _F.TurnParent(60.0f);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "Disable completes exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "Disable succeeded");
        Assert_True(Math::Abs(_F.ParentWorld().Rotator().Yaw - _TurnedYaw) < 0.01, "the parent actually turned");
        Assert_False(utils_sway::Get_IsEnabled(_F.Sway), "sway reports disabled");
        Assert_True(utils_sway::Get_IsSettled(_F.Sway), "disabled sway stays settled through the turn");
        Assert_True(utils_sway::Get_SwayOffset(_F.Sway).Equals(FTransform(), 0.02), "disabled sway offset stays identity");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_DisableRelaxesAndIgnoresMotion_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_DisableRelaxesAndIgnoresMotion;
    default _TimeoutSeconds = 8.0f;
}
