// Language=angelscript
class UCk_AutoTest_RotateTowards_AddTwiceIsRejected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    private FCk_RotateTowardsAutoTestFixture _F;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose rotate-towards, then add it a second time", n"Step_AddTwice");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_AddTwice(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle, _F.Make_DefaultSpec(), FVector(8000.0, 0.0, -40000.0));
        Assert_Valid(_F.RotateTowards, "the first Add composes");

        auto Spec = _F.Make_DefaultSpec();
        Spec.Set_Target(_F.Target);
        const auto Second = utils_rotate_towards::Add(_F.Turret, Spec);
        Assert_Invalid(Second, "a second Add on the same transform returns an invalid handle");
        Assert_True(utils_rotate_towards::DoCast(_F.Turret).IsSet(), "the first composition survives the rejected second Add");
        Assert_True(utils_rotate_towards::Get_Target(_F.RotateTowards) == _F.Target, "the first composition keeps its target");
        FinishSuccess();
    }
}

class ACk_AutoTest_RotateTowards_AddTwiceIsRejected_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_RotateTowards_AddTwiceIsRejected;
    default _TimeoutSeconds = 8.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("already rotates towards a target");
        return Errors;
    }
}
