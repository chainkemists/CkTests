// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_SteeringRequestRejects : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 68000.0, 1000.0);
    private FCk_Handle _Body;
    private TArray<ECk_Request_OperationResult> _Results;

    void RequestAndAssertRejected(FCk_Handle_SurfaceMotion InMotion, FCk_Request_SurfaceMotion_Steering InRequest,
        const FString& InCase)
    {
        auto ResultsBefore = _Results.Num();
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        utils_surface_motion::Request_Steering(InMotion, InRequest, FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Results.Num() - ResultsBefore, 1, f"{InCase}: the completion delegate fires exactly once");
        if (_Results.Num() > ResultsBefore)
        {
            Assert_True(_Results.Last() == ECk_Request_OperationResult::Failed_NotEnqueued,
                f"{InCase}: the request completes Failed_NotEnqueued");
        }
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Owner = InHandle;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        auto Body = utils_transform::Add(Entity, FTransform(_Origin), ECk_Replication::DoesNotReplicate);
        _Body = Body;
        auto Motion = utils_surface_motion::Add(Body, FCk_SurfaceMotion_Spec());
        Assert_True(ck::IsValid(Motion), "Precondition: the body has surface motion");

        auto NaN = Math::Sqrt(-1.0);
        auto NaNDirection = FVector(NaN, 0.0, 0.0);
        Assert_True(NaNDirection.ContainsNaN(), "Precondition: the direction carries a NaN");
        RequestAndAssertRejected(Motion, FCk_Request_SurfaceMotion_Steering(NaNDirection, 100.0f), "NaN direction");
        RequestAndAssertRejected(Motion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, -1.0f), "Negative speed");
        RequestAndAssertRejected(Motion, FCk_Request_SurfaceMotion_Steering(FVector::ZeroVector, 100.0f),
            "Zero direction while moving");

        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        auto ResultsBefore = _Results.Num();
        utils_surface_motion::Request_Steering(Motion, FCk_Request_SurfaceMotion_Steering(FVector::ZeroVector, 0.0f),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Results.Num() - ResultsBefore, 0, "Positive control: a valid stop request is enqueued, not completed");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: no ensure fires");

        utils_entity_lifetime::Request_DestroyEntity(_Body);
        RequestAndAssertRejected(Motion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, 100.0f),
            "Owner tagged for destruction");

        Add_Step_WaitUntil("the body is gone and the queued stop request has completed", n"Check_Destroyed");
        Add_Step("verify every completion", n"Step_CheckResults");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Results.Add(InResult);
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_Body) && _Results.Num() == 5);
    }

    UFUNCTION()
    private void Step_CheckResults(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto NotEnqueued = 0;
        for (auto Result : _Results)
        {
            NotEnqueued += Result == ECk_Request_OperationResult::Failed_NotEnqueued ? 1 : 0;
        }
        Assert_Equals_Int(NotEnqueued, 4, "The four rejected requests each completed Failed_NotEnqueued once");
        Assert_True(_Results.Last() == ECk_Request_OperationResult::Failed_Cancelled,
            "The stop request queued before the destroy completes Failed_Cancelled at teardown");
    }
}

class ACk_AutoTest_ProceduralAnimation_SteeringRequestRejects_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 6.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_SteeringRequestRejects");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("the entity must be live with surface motion, and the request needs a");
        return Errors;
    }
}
