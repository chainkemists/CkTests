// Language=angelscript
class UCk_AutoTest_RotateTowards_AddWithSelfTargetIsRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("add with the turret as its own target", n"Step_Add");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Add(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.InitWorld(InHandle, FVector(16000.0, 0.0, -40000.0));
        auto Spec = _F.Make_DefaultSpec();
        Spec.Set_Target(_F.Turret);
        _F.RotateTowards = utils_rotate_towards::Add(_F.Turret, Spec);
        Assert_Invalid(_F.RotateTowards, "Add targeting the entity itself returns an invalid handle");
        Assert_False(utils_rotate_towards::DoCast(_F.Turret).IsSet(), "nothing was composed onto the turret");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_AddWithSelfTargetIsRejected_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_AddWithSelfTargetIsRejected;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("an entity cannot target itself");
        return Errors;
    }
}
