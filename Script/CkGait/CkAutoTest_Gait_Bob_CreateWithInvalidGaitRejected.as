// Language=angelscript
class UCk_AutoTest_Gait_Bob_CreateWithInvalidGaitRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("create a bob with an invalid gait", n"Step_Create");
        Add_Step_WaitSeconds("exclude delayed composition", 0.1f);
        Add_Step("assert nothing was composed under the root", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(1000.0, 31000.0, -40000.0));
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
    private void Step_Create(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Valid(_F.Root, "the parent itself is valid, so only the gait can be rejected");
        auto Spec = FCk_Bob_Spec();
        Spec.Set_Gait(FCk_Handle_Gait());
        Spec.Set_Stride(FCk_Bob_StrideParams(6.0f, 4.0f));
        Spec.Set_LagRate(0.0f);
        Spec.Set_BreathCm(0.0f);
        _F.Bob = utils_bob::Create(_F.Root, FTransform(), Spec);
        Assert_Invalid(_F.Bob, "Create with an invalid gait returns an invalid handle synchronously");
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Invalid(_F.Bob, "Create with an invalid gait stays uncomposed");
        Assert_Equals_Int(utils_scene_node::ForEach_SceneNode(_F.Root, FInstancedStruct()).Num(), 0,
            "the gait is rejected before any scene node exists under the parent");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_Bob_CreateWithInvalidGaitRejected_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_Bob_CreateWithInvalidGaitRejected;
    default _TimeoutSeconds = 10.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Bob Create rejected invalid gait");
        return Errors;
    }
}
