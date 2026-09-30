// Language=angelscript
class UCk_AutoTest_RotateTowards_AddWithInvalidTunablesComposesNothing : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("add with a negative yaw turn rate", n"Step_Add");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Add(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = _F.Make_DefaultSpec();
        auto Tunables = Spec.Get_Tunables();
        auto Yaw = Tunables.Get_Yaw();
        Yaw.Set_TurnRateDegPerSec(-1.0f);
        Tunables.Set_Yaw(Yaw);
        Spec.Set_Tunables(Tunables);

        _F.Init(InHandle, Spec, FVector(12000.0, 0.0, -40000.0));
        Assert_Valid(_F.Turret, "the turret itself is valid, so only the tunables can be rejected");
        Assert_Invalid(_F.RotateTowards, "Add with invalid tunables returns an invalid handle");
        Assert_False(utils_rotate_towards::DoCast(_F.Turret).IsSet(), "nothing was composed onto the turret");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_AddWithInvalidTunablesComposesNothing_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_AddWithInvalidTunablesComposesNothing;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("RotateTowards Add rejected invalid tunables");
        return Errors;
    }
}
