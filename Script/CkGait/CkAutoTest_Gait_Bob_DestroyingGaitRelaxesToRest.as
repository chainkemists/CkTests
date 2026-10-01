// Language=angelscript
class UCk_AutoTest_Gait_Bob_DestroyingGaitRelaxesToRest : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private const FTransform _Rest = FTransform(FVector(0.0, 0.0, 64.0));

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("compose a gait and a bob", n"Step_Compose");
        Add_Step("fly at the reference speed", n"Step_Fly");
        Add_Step_WaitUntil("bob offset is visible", n"Check_OffsetVisible");
        Add_Step("destroy the character (and with it the gait)", n"Step_Destroy");
        Add_Step_WaitUntil("bob node relaxes onto its rest", n"Check_AtRest");
        Add_Step("assert the bob survived at rest", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(8000.0, 31000.0, -40000.0));
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
    private void Step_Compose(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto GaitSpec = FCk_Gait_Spec();
        auto Stride = GaitSpec.Get_Stride();
        Stride.Set_AmountInterpSpeed(20.0f);
        GaitSpec.Set_Stride(Stride);
        _F.AddGait(GaitSpec);
        Assert_Valid(_F.Gait, "gait added to the character's entity");

        _F.CreateBob(_Rest, Make_DemoSpec());
        Assert_Valid(_F.Bob, "bob node created under the root");
    }

    // Vertical 6 cm, lateral 4 cm, no lag, no breath: every observable offset comes from the stride or the spring.
    private FCk_Bob_Spec Make_DemoSpec() const
    {
        auto Spec = FCk_Bob_Spec();
        Spec.Set_Stride(FCk_Bob_StrideParams(6.0f, 4.0f));
        Spec.Set_LagRate(0.0f);
        Spec.Set_BreathCm(0.0f);
        return Spec;
    }

    UFUNCTION()
    private void Step_Fly(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Character.Fly(FVector(420.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_OffsetVisible(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_bob::Get_BobOffset(_F.Bob).GetLocation().Size() > 1.0);
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.DestroyCharacter();
    }

    UFUNCTION()
    private void Check_AtRest(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.BobWorld().Equals(_Rest * _F.RootWorld(), 0.05));
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // The gait handle may linger as a dead handle; what matters is that the bob node outlives it and rests.
        Assert_True(FCk_Handle(_F.Bob).Is_Bob(), "the bob node is still a bob after its gait was destroyed");
        Assert_True(_F.BobWorld().Equals(_Rest * _F.RootWorld(), 0.05), "the bob node rests at its rest offset over the root");
        Assert_True(utils_bob::Get_BobOffset(_F.Bob).GetLocation().Size() < 0.05, "the bob offset relaxed to zero");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_Bob_DestroyingGaitRelaxesToRest_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_Bob_DestroyingGaitRelaxesToRest;
    default _TimeoutSeconds = 10.0f;
}
