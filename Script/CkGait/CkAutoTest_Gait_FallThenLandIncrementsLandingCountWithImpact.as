// Language=angelscript
class UCk_AutoTest_Gait_FallThenLandIncrementsLandingCountWithImpact : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("add a gait", n"Step_AddGait");
        Add_Step("fall at 600 cm/s", n"Step_Fall");
        Add_Step_WaitUntil("gait samples airborne", n"Check_Airborne");
        Add_Step("land", n"Step_Land");
        Add_Step_WaitUntil("gait counts one landing", n"Check_Landed");
        Add_Step("assert the impact speed", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(5000.0, 30000.0, -40000.0));
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
    private void Step_AddGait(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Gait_Spec();
        auto Stride = Spec.Get_Stride();
        Stride.Set_AmountInterpSpeed(20.0f);
        Spec.Set_Stride(Stride);
        _F.AddGait(Spec);
        Assert_Valid(_F.Gait, "gait added to the character's entity");
    }

    UFUNCTION()
    private void Step_Fall(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_gait::Get_LandingCount(_F.Gait), 0, "no landing before the fall");
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
    private void Check_Landed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_LandingCount(_F.Gait) == 1);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Impact = utils_gait::Get_LastLandImpactSpeed(_F.Gait);
        Assert_True(Impact >= 540.0f && Impact <= 660.0f, f"landing impact {Impact} cm/s is the 600 cm/s fall speed within 10%");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_FallThenLandIncrementsLandingCountWithImpact_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_FallThenLandIncrementsLandingCountWithImpact;
    default _TimeoutSeconds = 10.0f;
}
