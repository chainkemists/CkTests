// Language=angelscript
class UCk_AutoTest_RotateTowards_SceneNodeChildRotatesViaOffset : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;
    private FCk_Handle_SceneNode _Node;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose rotate-towards on a scene node parented to the turret", n"Step_Arrange");
        Add_Step_WaitUntil("scene node reports at target", n"Check_AtTarget");
        // The offset request enqueued on the reaching frame drains at the start of the next frame (DESIGN section 5), so
        // the world-pose assertion gates on its own stage (CkTests wait rule 3).
        Add_Step_WaitUntil("scene node world yaw reaches 90", n"Check_NodeFacesTarget");
        Add_Step("assert the node turned and its parent did not", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.InitWorld(InHandle, FVector(60000.0, 0.0, -40000.0));
        _Node = utils_scene_node::Create(_F.Turret, FTransform());
        Assert_Valid(_Node, "scene node created under the turret");

        auto Spec = _F.Make_DefaultSpec();
        Spec.Set_Target(_F.Target);
        _F.RotateTowards = utils_rotate_towards::Add(_Node.As_Transform(), Spec);
        Assert_Valid(_F.RotateTowards, "rotate-towards composed on the scene node");
    }

    UFUNCTION()
    private void Check_AtTarget(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_rotate_towards::Get_IsAtTarget(_F.RotateTowards));
    }

    UFUNCTION()
    private void Check_NodeFacesTarget(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(CkRotateTowardsAutoTest::Is_Near(NodeYaw(), 90.0, 1.0));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Yaw = NodeYaw();
        const auto TurretYaw = _F.TurretRotation().Yaw;
        Assert_True(CkRotateTowardsAutoTest::Is_Near(Yaw, 90.0, 1.0), f"node world yaw {Yaw} is within 1 deg of 90");
        Assert_True(CkRotateTowardsAutoTest::Is_Near(TurretYaw, 0.0, 0.05), f"parent turret yaw {TurretYaw} untouched");
        FinishSuccess();
    }

    private float NodeYaw() const
    {
        return utils_transform::Get_EntityCurrentRotation(_Node.As_Transform()).Yaw;
    }
}

class ACk_AutoTest_RotateTowards_SceneNodeChildRotatesViaOffset_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_SceneNodeChildRotatesViaOffset;
    default _TimeoutSeconds = 8.0f;
}
