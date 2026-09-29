// Language=angelscript
class UCk_AutoTest_Sway_AddOnAnchorDrivenNodeFollowsAnchorMotion : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private ACk_SwayAutoTest_AnchorHelper _Helper;
    private float _ObservedPitch = 0.0f;
    private float _ObservedPitchRate = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("anchor a scene node to an actor component and add Sway to it", n"Step_Arrange");
        // Setup seeds the previous driver pose from the anchor's CURRENT pose; a pitch issued before Setup has run
        // would be absorbed into that seed and produce no stimulus. Setup completion is not observable, hence a settle.
        Add_Step_WaitSeconds("let Setup seed the previous driver pose", 0.1f);
        Add_Step("pitch the anchor actor +45 deg in one frame", n"Step_Pitch");
        Add_Step_WaitUntil("rotation channel lags opposite the pitch", n"Check_Lagging");
        Add_Step("assert the lag was driven by the anchor's pitch rate", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.InitParent(InHandle, FVector(16000.0, 0.0, -40000.0));
        _Helper = Cast<ACk_SwayAutoTest_AnchorHelper>(SpawnActor(
            ACk_SwayAutoTest_AnchorHelper, _F.Origin, FRotator::ZeroRotator));
        if (ck::Is_NOT_Valid(_Helper))
        {
            FinishFailure("Failed to spawn the anchor helper actor");
            return;
        }

        _F.Node = utils_scene_node::CreateAndAttachToUnrealComponent(_F.Parent, _Helper.SceneRoot, FTransform());
        Assert_Valid(_F.Node, "anchor-driven scene node composed");

        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Sway = utils_sway::Add(_F.Node, Spec);
        Assert_Valid(_F.Sway, "Add on an anchor-driven node returns a valid sway handle");
    }

    UFUNCTION()
    private void Step_Pitch(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Helper.SetActorRotation(FRotator(45.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_Lagging(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto Pitch = utils_sway::Get_RotationOffset(_F.Sway).Pitch;
        if (Pitch >= -0.05)
        {
            Res.Set(false);
            return;
        }
        // Captured at the moment of the first observation: the stimulus is only set on the frame the anchor moved.
        _ObservedPitch = Pitch;
        _ObservedPitchRate = utils_sway::Get_LastStimulus(_F.Sway).Get_AngularVelocityDeg().Y;
        Res.Set(true);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_ObservedPitch < -0.05, f"pitch offset {_ObservedPitch} lags opposite the anchor's pitch");
        Assert_True(_ObservedPitchRate > 0.0, f"stimulus pitch rate {_ObservedPitchRate} is positive for a +45 deg anchor pitch");
        _Helper.DestroyActor();
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_AddOnAnchorDrivenNodeFollowsAnchorMotion_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_AddOnAnchorDrivenNodeFollowsAnchorMotion;
    default _TimeoutSeconds = 8.0f;
}
