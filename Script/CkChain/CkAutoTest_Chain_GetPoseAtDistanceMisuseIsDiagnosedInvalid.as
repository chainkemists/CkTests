// Language=angelscript
class UCk_AutoTest_Chain_GetPoseAtDistanceMisuseIsDiagnosedInvalid : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    private FCk_ChainAutoTestFixture _F;
    private FCk_ChainAutoTestFixture _Constraint;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("compose path and off-origin constraint chains", n"Step_Arrange");
        Add_Step_WaitUntil("path history seeded", n"Check_Seeded");
        Add_Step("assert misuse diagnoses and is invalid", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Arrange(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Init(InHandle);
        _Constraint.Owner = InHandle;
        _Constraint.Head = _Constraint.Spawn(FVector(200.0, 300.0, 0.0));
        _Constraint.Chain = utils_chain::Add(_Constraint.Head, FCk_Chain_Spec(ECk_Chain_Solver::DistanceConstraint));
    }

    UFUNCTION()
    private void Check_Seeded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(ck::IsValid(_F.Chain) && utils_chain::Get_NumHistorySamples(_F.Chain) >= 2);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto Constraint = utils_chain::Get_PoseAtDistance(_Constraint.Chain, 5.0f);
        Assert_True(utils_ensure::Get_EnsureCount() == EnsuresBefore + 1, "DistanceConstraint query diagnoses once");
        Assert_False(Constraint.Get_IsValid(), "DistanceConstraint chain has no path pose");
        Assert_True(Constraint.Get_Pose().Equals(FTransform::Identity, 0.001), "DistanceConstraint misuse carries the default pose, not the off-origin head pose");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto Negative = utils_chain::Get_PoseAtDistance(_F.Chain, -1.0f);
        Assert_True(utils_ensure::Get_EnsureCount() == EnsuresBefore + 1, "negative distance diagnoses once");
        Assert_False(Negative.Get_IsValid(), "negative distance is invalid");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto InvalidChain = utils_chain::Get_PoseAtDistance(FCk_Handle_Chain(), 5.0f);
        Assert_True(utils_ensure::Get_EnsureCount() == EnsuresBefore + 1, "invalid chain handle diagnoses once");
        Assert_False(InvalidChain.Get_IsValid(), "invalid chain handle is invalid");

        EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto Valid = utils_chain::Get_PoseAtDistance(_F.Chain, 5.0f);
        Assert_True(utils_ensure::Get_EnsureCount() == EnsuresBefore, "valid query diagnoses nothing");
        Assert_True(Valid.Get_IsValid(), "valid query on the same chain still answers");
        FinishSuccess();
    }
}

class ACk_AutoTest_Chain_GetPoseAtDistanceMisuseIsDiagnosedInvalid_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Chain_GetPoseAtDistanceMisuseIsDiagnosedInvalid;
    default _TimeoutSeconds = 6.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Chain Get Pose At Distance requires PathHistory solver");
        Errors.Add("Chain Get Pose At Distance requires a finite nonnegative distance");
        Errors.Add("Chain Get Pose At Distance requires a valid chain");
        return Errors;
    }
}
