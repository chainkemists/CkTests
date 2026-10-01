// Language=angelscript
class UCk_AutoTest_Gait_AtRestAmountIsZeroAndPhaseIdles : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("add a gait to the resting character", n"Step_AddGait");
        // Negative window for Amount (it must stay 0); the phase advancing is the positive that the clock ticked.
        Add_Step_WaitSeconds("let the resting gait tick", 0.5f);
        Add_Step("assert zero amount, an idling phase and grounded footing", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(3000.0, 30000.0, -40000.0));
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
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Float(utils_gait::Get_Amount(_F.Gait), 0.0f, 1.0e-6f, "amount stays zero at rest");
        const auto Phase = utils_gait::Get_Phase(_F.Gait);
        Assert_True(Phase > 0.1f, f"phase {Phase} idles forward at rest");
        Assert_True(utils_gait::Get_LastMotion(_F.Gait).Get_Footing() == ECk_Gait_Footing::Grounded,
            "flying with zero velocity samples as grounded");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_AtRestAmountIsZeroAndPhaseIdles_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_AtRestAmountIsZeroAndPhaseIdles;
    default _TimeoutSeconds = 10.0f;
}
