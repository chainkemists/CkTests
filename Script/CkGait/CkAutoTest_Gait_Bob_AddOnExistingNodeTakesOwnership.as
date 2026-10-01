// Language=angelscript
class UCk_AutoTest_Gait_Bob_AddOnExistingNodeTakesOwnership : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private const FTransform _Rest = FTransform(FVector(0.0, 0.0, 64.0));
    private FCk_Handle_SceneNode _Node;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("create a scene node at an offset and add Bob to it", n"Step_Arrange");
        Add_Step_WaitSeconds("let the resting gait tick", 0.2f);
        Add_Step("assert the node rests at its adopted offset", n"Step_VerifyRest");
        Add_Step("add Bob to the same node again", n"Step_AddAgain");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(2000.0, 31000.0, -40000.0));
        if (ck::Is_NOT_Valid(_F.Character))
        {
            return;
        }

        utils_pending_entity_script::Promise_OnConstructed(_F.Character.PendingEntity,
            FCk_Delegate_EntityScript_Constructed(this, n"OnEntityReady"));
    }

    UFUNCTION()
    private void OnEntityReady(FCk_Handle_EntityScript InEntityScript)
    {
        if (IsFinished())
        {
            return;
        }

        _F.Ready(_Owner, InEntityScript);
    }

    UFUNCTION()
    private void Check_EntityReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_F.Entity) && ck::IsValid(_F.Root));
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto GaitSpec = FCk_Gait_Spec();
        auto Stride = GaitSpec.Get_Stride();
        Stride.Set_AmountInterpSpeed(20.0f);
        GaitSpec.Set_Stride(Stride);
        _F.AddGait(GaitSpec);
        Assert_Valid(_F.Gait, "gait added to the character's entity");

        _Node = utils_scene_node::Create(_F.Root, _Rest);
        Assert_Valid(_Node, "scene node composed");
        _F.Bob = utils_bob::Add(_Node, Make_DemoSpec());
        Assert_Valid(_F.Bob, "Add returns a valid bob handle");
        Assert_True(utils_bob::Get_RestOffset(_F.Bob).Equals(_Rest, 0.001), "the node's current offset becomes the rest offset");
    }

    // Vertical 6 cm, lateral 4 cm, no lag, no breath: every observable offset comes from the stride or the spring.
    private FCk_Bob_Spec Make_DemoSpec() const
    {
        auto Spec = FCk_Bob_Spec();
        Spec.Set_Gait(_F.Gait);
        Spec.Set_Stride(FCk_Bob_StrideParams(6.0f, 4.0f));
        Spec.Set_LagRate(0.0f);
        Spec.Set_BreathCm(0.0f);
        return Spec;
    }

    UFUNCTION()
    private void Step_VerifyRest(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(_F.BobWorld().Equals(_Rest * _F.RootWorld(), 0.05), "the node world pose is the rest offset over the root");
    }

    UFUNCTION()
    private void Step_AddAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Again = utils_bob::Add(_Node, Make_DemoSpec());
        Assert_Invalid(Again, "a second Add on a bob node returns an invalid handle");
        Assert_True(utils_bob::Get_RestOffset(_F.Bob).Equals(_Rest, 0.001), "the rejected Add leaves the first bob untouched");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_Bob_AddOnExistingNodeTakesOwnership_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_Bob_AddOnExistingNodeTakesOwnership;
    default _TimeoutSeconds = 10.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("already a bob node");
        return Errors;
    }
}
