// Language=angelscript
class UCk_AutoTest_Sway_ChildSceneNodeFollowsSwayedPose : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_SwayAutoTestFixture _F;
    private FCk_Handle_SceneNode _Child;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose sway", n"Step_Arrange");
        // Setup seeds the previous parent pose from the parent's CURRENT pose; a turn issued before Setup has run
        // would be absorbed into that seed and produce no stimulus. Setup completion is not observable, hence a settle.
        Add_Step_WaitSeconds("let Setup seed the previous parent pose", 0.1f);
        Add_Step("attach a child under the sway and turn the parent +45 deg", n"Step_Turn");
        // Gate on the channel AND on the node's composed pose: the offset reaches the node one frame after Update
        // computes it (CkSway DESIGN section 6), and the assertion reads composed poses (CkTests wait rule 3).
        Add_Step_WaitUntil("swayed pose has landed on the node", n"Check_Swayed");
        Add_Step("assert the child composes from the swayed pose", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Sway_Spec();
        Spec.Set_TeleportDistanceCm(0.0f);
        _F.Init(InHandle, Spec, FVector(13000.0, 0.0, -40000.0));
        Assert_Valid(_F.Sway, "sway composed");
    }

    UFUNCTION()
    private void Step_Turn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Child = utils_scene_node::Create(_F.Sway.As_Transform(), FTransform(FVector(10.0, 0.0, 0.0)));
        Assert_Valid(_Child, "child scene node composed under the sway");
        _F.TurnParent(45.0f);
    }

    UFUNCTION()
    private void Check_Swayed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_sway::Get_RotationOffset(_F.Sway).Yaw < -0.5
            && _F.SwayWorld().Rotator().Yaw < _F.ParentWorld().Rotator().Yaw - 0.01);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto SwayPose = _F.SwayWorld();
        // FTransform(FVector(10,0,0)) * SwayPose: identity rotation/scale, so only the location is carried through.
        const auto Expected = FTransform(SwayPose.Rotator(), SwayPose.TransformPosition(FVector(10.0, 0.0, 0.0)), SwayPose.GetScale3D());
        const auto ChildPose = utils_transform::Get_EntityCurrentTransform(_Child.As_Transform());
        Assert_True(ChildPose.Equals(Expected, 0.05), "child composes from the swayed node pose in the same frame");
        FinishSuccess();
    }
}

class ACk_AutoTest_Sway_ChildSceneNodeFollowsSwayedPose_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Sway_ChildSceneNodeFollowsSwayedPose;
    default _TimeoutSeconds = 8.0f;
}
