// Language=angelscript
class UCk_AutoTest_Gait_FlyingVelocityRaisesAmountAndAdvancesPhase : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private float32 _FirstPhase = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("add a gait and fly at the reference speed", n"Step_Fly");
        Add_Step_WaitUntil("amount rises above 0.9", n"Check_AmountRaised");
        Add_Step("assert the speed ratio and record the phase", n"Step_VerifyRatio");
        Add_Step_WaitSeconds("let the stride clock turn", 0.1f);
        Add_Step("assert the phase advanced", n"Step_VerifyPhase");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(4000.0, 30000.0, -40000.0));
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
    private void Step_Fly(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Gait_Spec();
        auto Stride = Spec.Get_Stride();
        Stride.Set_AmountInterpSpeed(20.0f);
        Spec.Set_Stride(Stride);
        _F.AddGait(Spec);
        Assert_Valid(_F.Gait, "gait added to the character's entity");
        _F.Character.Fly(FVector(420.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_AmountRaised(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_Amount(_F.Gait) > 0.9f);
    }

    UFUNCTION()
    private void Step_VerifyRatio(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_gait::Get_SpeedRatio(_F.Gait), 1.0f, 0.05f, "420 cm/s is the default reference speed");
        _FirstPhase = utils_gait::Get_Phase(_F.Gait);
    }

    UFUNCTION()
    private void Step_VerifyPhase(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        // Wrap-aware: the phase lives in [0, 2pi) and one 0.1 s window at full cadence turns it by ~1 rad.
        auto Delta = utils_gait::Get_Phase(_F.Gait) - _FirstPhase;
        if (Delta < 0.0f)
        {
            Delta += 6.2831853f;
        }

        Assert_True(Delta > 0.1f, f"phase advanced by {Delta} rad over 0.1 s");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_FlyingVelocityRaisesAmountAndAdvancesPhase_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_FlyingVelocityRaisesAmountAndAdvancesPhase;
    default _TimeoutSeconds = 10.0f;
}
