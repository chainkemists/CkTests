// Language=angelscript
class UCk_AutoTest_Gait_AddTwiceRejected : UCk_AutoTest_Base
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
        Add_Step("add a second gait to the same entity", n"Step_AddAgain");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(2000.0, 30000.0, -40000.0));
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
    private void Step_AddAgain(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Gait_Spec();
        auto Stride = Spec.Get_Stride();
        Stride.Set_AmountInterpSpeed(20.0f);
        Spec.Set_Stride(Stride);
        const auto Again = utils_gait::Add(_F.Entity, Spec);
        Assert_Invalid(Again, "a second Add on a gait entity returns an invalid handle");
        Assert_Valid(_F.Gait, "the first gait stays valid");
        Assert_True(utils_gait::Get_IsEnabled(_F.Gait), "the first gait stays enabled");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_AddTwiceRejected_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_AddTwiceRejected;
    default _TimeoutSeconds = 10.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("already a gait");
        return Errors;
    }
}
