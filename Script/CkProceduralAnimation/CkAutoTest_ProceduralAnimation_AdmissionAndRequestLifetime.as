// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_AdmissionAndRequestLifetime : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    default _AutoStageOriginField = false;
    private FCk_Handle _CancelledRoot;
    private FCk_Handle _SurvivorRoot;
    private FCk_Handle_SurfaceMotion _SurvivorMotion;
    private TArray<FCk_Handle_Transform> _Parts;
    private int32 _CancelledCompletions = 0;
    private int32 _SurvivorCompletions = 0;
    private int32 _RejectedCompletions = 0;

    FCk_Handle_Transform CreateTransform(FCk_Handle InOwner, FVector InPosition)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        return utils_transform::Add(Entity, FTransform(InPosition), ECk_Replication::DoesNotReplicate);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        _CancelledRoot = CreateTransform(InHandle, FVector(120000.0, 50000.0, 1000.0));
        auto GaitLegs = TArray<FCk_ProceduralGait_Leg>();
        auto RigLegs = TArray<FCk_ProceduralRig_Leg>();
        for (auto Index = 0; Index < 2; Index++)
        {
            auto Side = Index == 0 ? -1.0 : 1.0;
            auto Id = FName(f"Leg{Index}");
            auto GaitLeg = FCk_ProceduralGait_Leg();
            GaitLeg.Set_Id(Id);
            GaitLeg.Set_HipLocal(FVector(0.0, Side * 30.0, 0.0));
            GaitLeg.Set_RestFootLocal(FVector(0.0, Side * 100.0, -65.0));
            GaitLeg.Set_PhaseOffset(Index == 0 ? 0.0f : 0.5f);
            GaitLegs.Add(GaitLeg);
            auto Leg = FCk_ProceduralRig_Leg();
            Leg.Set_Id(Id);
            Leg.Set_Upper(CreateTransform(_CancelledRoot, FVector(120000.0, 50000.0, 1000.0)));
            Leg.Set_Lower(CreateTransform(_CancelledRoot, FVector(120000.0, 50000.0, 950.0)));
            _Parts.Add(Leg.Get_Upper());
            _Parts.Add(Leg.Get_Lower());
            RigLegs.Add(Leg);
        }
        auto GaitParams = FCk_Fragment_ProceduralGait_ParamsData();
        GaitParams.Set_Legs(GaitLegs);
        auto Gait = utils_procedural_gait::Add(_CancelledRoot, GaitParams);
        Assert_True(ck::IsValid(Gait), "The target starts with a valid gait composition");

        auto BadLegs = RigLegs;
        BadLegs[1].Set_Lower(FCk_Handle_Transform());
        auto BadParams = FCk_Fragment_ProceduralRig_ParamsData();
        BadParams.Set_Legs(BadLegs);
        auto BadRig = utils_procedural_rig::Add(_CancelledRoot, BadParams);
        Assert_True(ck::Is_NOT_Valid(BadRig) && utils_procedural_rig::Has(_CancelledRoot) == false,
            "A malformed second leg rejects the whole rig without leaving a partial feature");

        auto RetiringPart = FCk_Handle(CreateTransform(_CancelledRoot, FVector(120000.0, 50000.0, 950.0)));
        auto RetiringTransform = utils_transform::DoCastChecked(RetiringPart);
        utils_entity_lifetime::Request_DestroyEntity(RetiringPart);
        BadLegs = RigLegs;
        BadLegs[1].Set_Lower(RetiringTransform);
        BadParams.Set_Legs(BadLegs);
        auto RetiringRig = utils_procedural_rig::Add(_CancelledRoot, BadParams);
        Assert_True(ck::Is_NOT_Valid(RetiringRig) && utils_procedural_rig::Has(_CancelledRoot) == false,
            "A required part already queued for destruction cannot be admitted into a new rig");

        auto GoodParams = FCk_Fragment_ProceduralRig_ParamsData();
        GoodParams.Set_Legs(RigLegs);
        auto GoodRig = utils_procedural_rig::Add(_CancelledRoot, GoodParams);
        Assert_True(ck::IsValid(GoodRig), "Corrected composition succeeds on the same entity after atomic rejection");
        auto DuplicateRig = utils_procedural_rig::Add(_CancelledRoot, GoodParams);
        Assert_True(ck::Is_NOT_Valid(DuplicateRig) && utils_procedural_rig::Has(_CancelledRoot),
            "Duplicate admission rejects the new feature while preserving the existing rig");

        auto Motion = utils_surface_motion::Add(_CancelledRoot, FCk_Fragment_SurfaceMotion_ParamsData());
        _SurvivorRoot = CreateTransform(InHandle, FVector(125000.0, 50000.0, 1000.0));
        _SurvivorMotion = utils_surface_motion::Add(_SurvivorRoot, FCk_Fragment_SurfaceMotion_ParamsData());
        Assert_True(ck::IsValid(Motion) && ck::IsValid(_SurvivorMotion), "Both request targets have a surface-motion feature");

        // These two calls occur on the same stack before the request processor can drain.
        utils_surface_motion::Request_Steering(Motion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, 100.0f),
            FCk_Delegate_Request_OnCompleted(this, n"OnCancelled"));
        utils_entity_lifetime::Request_DestroyEntity(_CancelledRoot);

        auto InvalidMotion = FCk_Handle_SurfaceMotion();
        utils_surface_motion::Request_Steering(InvalidMotion, FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, 0.0f),
            FCk_Delegate_Request_OnCompleted(this, n"OnRejected"));
        Assert_Equals_Int(_RejectedCompletions, 1, "Invalid-handle rejection completes synchronously exactly once");

        Add_Step_WaitUntil("queued request cancels and its full owner subtree retires", n"Check_Cancelled");
        Add_Step("enqueue positive request after teardown", n"Step_RequestSurvivor");
        Add_Step_WaitUntil("surviving target drains its first request", n"Check_FirstSurvivor");
        Add_Step("enqueue another positive request on a later drain", n"Step_RequestSurvivor");
        Add_Step_WaitUntil("surviving target drains its second request", n"Check_SecondSurvivor");
        Add_Step("verify counts after two later successful drains", n"Step_CheckCounts");
        Add_Step_WaitUntil("surviving owner is destroyed", n"Check_SurvivorDestroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnCancelled(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _CancelledCompletions++;
        Assert_True(InRequestOwner == _CancelledRoot, "Cancellation reports the destroyed request owner");
        Assert_True(InResult == ECk_Request_OperationResult::Failed_Cancelled,
            "Destroy-before-drain terminates with Failed_Cancelled");
    }

    UFUNCTION()
    private void OnRejected(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RejectedCompletions++;
        Assert_True(InResult == ECk_Request_OperationResult::Failed_NotEnqueued,
            "Invalid-handle steering cannot enter the request queue");
    }

    UFUNCTION()
    private void OnSurvivor(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _SurvivorCompletions++;
        Assert_True(InRequestOwner == _SurvivorRoot && InResult == ECk_Request_OperationResult::Succeeded,
            "A live target still completes requests successfully after another target is destroyed");
    }

    UFUNCTION()
    private void Check_Cancelled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Gone = ck::Is_NOT_Valid(_CancelledRoot);
        for (auto Part : _Parts)
        {
            Gone = Gone && ck::Is_NOT_Valid(Part);
        }
        auto Result = OutResult;
        Result.Set(_CancelledCompletions > 0 && Gone);
    }

    UFUNCTION()
    private void Step_RequestSurvivor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_surface_motion::Request_Steering(_SurvivorMotion,
            FCk_Request_SurfaceMotion_Steering(FVector::ForwardVector, 0.0f),
            FCk_Delegate_Request_OnCompleted(this, n"OnSurvivor"));
    }

    UFUNCTION()
    private void Check_FirstSurvivor(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_SurvivorCompletions >= 1);
    }

    UFUNCTION()
    private void Check_SecondSurvivor(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_SurvivorCompletions >= 2);
    }

    UFUNCTION()
    private void Step_CheckCounts(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_CancelledCompletions, 1, "Cancelled work never completes twice, including later request pumps");
        Assert_Equals_Int(_RejectedCompletions, 1, "Rejected work never leaks into a later drain");
        Assert_Equals_Int(_SurvivorCompletions, 2, "Both later positive-control requests executed exactly once");
        utils_entity_lifetime::Request_DestroyEntity(_SurvivorRoot);
    }

    UFUNCTION()
    private void Check_SurvivorDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_SurvivorRoot));
    }
}

// Malformed, retiring-part and duplicate admissions exercise loud public-contract rejections.
// A hand-authored wrapper owns expected diagnostics; they do not belong on the entity script.
class ACk_AutoTest_ProceduralAnimation_AdmissionAndRequestLifetime_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 8.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_AdmissionAndRequestLifetime");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("Procedural rig admission requires unit root scale, unique owned transform parts and matching stable gait leg IDs.");
        Errors.Add("Procedural rig needs a live gait/transform entity with no existing rig feature.");
        return Errors;
    }
}
