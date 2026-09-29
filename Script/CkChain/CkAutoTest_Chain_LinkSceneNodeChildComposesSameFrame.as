// Language=angelscript
class UCk_AutoTest_Chain_LinkSceneNodeChildComposesSameFrame : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_Handle_SceneNode _Child;
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("attach link with scene child", n"Step_Arrange");
        Add_Step_WaitUntil("initial link and child settled", n"Check_Ready");
        Add_Step("move head", n"Step_Move");
        Add_Step_WaitUntil("assert child in first moved-link observation", n"Check_Moved");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _F.Attach(100.0f);
        _Child = utils_scene_node::Create(_F.Links[0], FTransform(FRotator::ZeroRotator, FVector(0.0, 50.0, 0.0), FVector::OneVector));
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.Ready(1) && _F.Location(0).Equals(FVector(-100.0, 0.0, 0.0), 1.0) && utils_transform::Get_EntityCurrentLocation(_Child.As_Transform()).Equals(FVector(-100.0, 50.0, 0.0), 1.0));
    }

    UFUNCTION()
    private void Step_Move(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Move(FVector(500.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_Moved(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        if (!_F.Location(0).Equals(FVector(400.0, 0.0, 0.0), 1.0))
        {
            Res.Set(false);
            return;
        }
        const auto LinkPose = utils_transform::Get_EntityCurrentTransform(_F.Links[0]);
        const auto Expected = LinkPose.TransformPosition(FVector(0.0, 50.0, 0.0));
        Assert_True(utils_transform::Get_EntityCurrentLocation(_Child.As_Transform()).Equals(Expected, 1.0), "child composes in same first observation as solved link");
        Res.Set(true);
        FinishSuccess();
    }
}
