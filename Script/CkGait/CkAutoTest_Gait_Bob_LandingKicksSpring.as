// Language=angelscript
class UCk_AutoTest_Gait_Bob_LandingKicksSpring : UCk_AutoTest_Base
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
        Add_Step("fall at 600 cm/s", n"Step_Fall");
        Add_Step_WaitUntil("gait samples airborne", n"Check_Airborne");
        Add_Step("land", n"Step_Land");
        Add_Step_WaitUntil("landing kicks the spring down", n"Check_Kicked");
        Add_Step_WaitUntil("spring returns to rest", n"Check_Settled");
        Add_Step("finish", n"Step_Finish");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(5000.0, 31000.0, -40000.0));
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
    private void Step_Fall(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Character.Fall(600.0f);
    }

    UFUNCTION()
    private void Check_Airborne(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_LastMotion(_F.Gait).Get_Footing() == ECk_Gait_Footing::Airborne);
    }

    UFUNCTION()
    private void Step_Land(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Character.Land();
    }

    UFUNCTION()
    private void Check_Kicked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_bob::Get_SpringOffset(_F.Bob) < -0.5f);
    }

    UFUNCTION()
    private void Check_Settled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::Abs(utils_bob::Get_SpringOffset(_F.Bob)) < 0.05f);
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_Bob_LandingKicksSpring_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_Bob_LandingKicksSpring;
    default _TimeoutSeconds = 10.0f;
}
