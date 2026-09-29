// Language=angelscript
class UCk_AutoTest_Sway_UpdateSpecChangesResponse : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private float _TurnedYaw = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway and request an all-zero-gain spec", n"Step_Arrange");
        Add_Step_WaitSeconds("let the UpdateSpec request drain", 0.05f);
        Add_Step("turn the parent +60 deg", n"Step_Turn");
        // Negative window (CkTests wait rule 1): the positives are the Succeeded completion, the replaced spec and the turn.
        Add_Step_WaitSeconds("observe the zero-gain sway through the turn", 0.3f);
        Add_Step("assert the new spec suppressed the response", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(9000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");

        auto ZeroGains = FCk_Sway_Spec();
        ZeroGains.Set_TeleportDistanceCm(0.0f);
        ZeroGains.Set_RotationFromAngularVelocity(FVector::ZeroVector);
        ZeroGains.Set_LocationFromLinearVelocity(FVector::ZeroVector);
        ZeroGains.Set_LateralCmFromYawRate(0.0f);
        ZeroGains.Set_VerticalCmFromPitchRate(0.0f);
        ZeroGains.Set_RollDegFromLateralVelocity(0.0f);
        ZeroGains.Set_PitchDegFromForwardVelocity(0.0f);
        utils_sway::Request_UpdateSpec(_F.Sway, FCk_Request_Sway_UpdateSpec(ZeroGains),
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
        Assert_Equals_Int(_Completions, 1, "UpdateSpec completes exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "UpdateSpec succeeded");
        Assert_True(utils_sway::Get_Spec(_F.Sway).Get_LateralCmFromYawRate() == 0.0, "the replaced spec is retained");
        Assert_True(Math::Abs(_F.ParentWorld().Rotator().Yaw - _TurnedYaw) < 0.01, "the parent actually turned");
        Assert_True(utils_sway::Get_SwayOffset(_F.Sway).Equals(FTransform(), 0.02), "zero gains produce no offset");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_UpdateSpecChangesResponse_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_UpdateSpecChangesResponse;
    default _TimeoutSeconds = 8.0f;
}
