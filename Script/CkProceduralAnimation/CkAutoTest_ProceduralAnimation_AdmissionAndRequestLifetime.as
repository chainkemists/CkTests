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

    FCk_ProceduralRig_Spec MakeChain(FCk_Handle_Transform InUpper, FCk_Handle_Transform InLower)
    {
        auto Segments = TArray<FCk_Handle_Transform>();
        Segments.Add(InUpper);
        Segments.Add(InLower);
        auto Chain = FCk_ProceduralRig_Spec();
        Chain.Set_Segments(Segments);
        return Chain;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Location = FVector(120000.0, 50000.0, 1000.0);
        auto Root = CreateTransform(InHandle, Location);
        _CancelledRoot = Root;
        auto WalkerUpper = CreateTransform(_CancelledRoot, Location);
        auto WalkerLower = CreateTransform(_CancelledRoot, Location - FVector(0.0, 0.0, 50.0));
        auto Upper = CreateTransform(_CancelledRoot, Location);
        auto Lower = CreateTransform(_CancelledRoot, Location - FVector(0.0, 0.0, 50.0));
        _Parts.Add(WalkerUpper);
        _Parts.Add(WalkerLower);
        _Parts.Add(Upper);
        _Parts.Add(Lower);

        auto Chains = TArray<FCk_ProceduralWalker_LegChain>();
        Chains.Add(FCk_ProceduralWalker_LegChain(n"Leg0", MakeChain(WalkerUpper, WalkerLower)));
        auto Walker = utils_procedural_animation::Add_Walker(Root, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait, Chains);
        Assert_True(ck::IsValid(Walker.Get_Gait()) && Walker.Get_Legs().Num() == 2,
            "The target starts with a valid walker composition");
        if (Walker.Get_Legs().Num() != 2)
        {
            return;
        }
        auto Leg = Walker.Get_Legs()[1];

        auto MissingParams = MakeChain(Upper, FCk_Handle_Transform());
        auto MissingRig = utils_procedural_rig::Add(Leg, MissingParams);
        Assert_True(ck::Is_NOT_Valid(MissingRig) && utils_procedural_rig::DoCast(Leg).IsSet() == false,
            "A chain with a missing segment rejects the whole rig without leaving a partial feature");

        auto RetiringPart = FCk_Handle(CreateTransform(_CancelledRoot, Location - FVector(0.0, 0.0, 50.0)));
        auto RetiringTransform = utils_transform::DoCastChecked(RetiringPart);
        utils_entity_lifetime::Request_DestroyEntity(RetiringPart);
        auto RetiringRig = utils_procedural_rig::Add(Leg, MakeChain(Upper, RetiringTransform));
        Assert_True(ck::Is_NOT_Valid(RetiringRig) && utils_procedural_rig::DoCast(Leg).IsSet() == false,
            "A segment already queued for destruction cannot be admitted into a new rig");

        auto DuplicateSegmentRig = utils_procedural_rig::Add(Leg, MakeChain(Upper, Upper));
        Assert_True(ck::Is_NOT_Valid(DuplicateSegmentRig) && utils_procedural_rig::DoCast(Leg).IsSet() == false,
            "A chain that repeats a segment is rejected");

        auto GoodRig = utils_procedural_rig::Add(Leg, MakeChain(Upper, Lower));
        Assert_True(ck::IsValid(GoodRig), "Corrected composition succeeds on the same leg after atomic rejection");
        auto DuplicateRig = utils_procedural_rig::Add(Leg, MakeChain(Upper, Lower));
        Assert_True(ck::Is_NOT_Valid(DuplicateRig) && utils_procedural_rig::DoCast(Leg).IsSet(),
            "Duplicate admission rejects the new feature while preserving the existing rig");

        auto Motion = utils_surface_motion::Add(Root, FCk_SurfaceMotion_Spec());
        auto SurvivorRoot = CreateTransform(InHandle, FVector(125000.0, 50000.0, 1000.0));
        _SurvivorRoot = SurvivorRoot;
        _SurvivorMotion = utils_surface_motion::Add(SurvivorRoot, FCk_SurfaceMotion_Spec());
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

// Missing, retiring, repeated and duplicate rig admissions and the invalid steering target exercise loud
// public-contract rejections. A hand-authored wrapper owns expected diagnostics; they do not belong on the
// entity script.
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
        Errors.Add("The leg must be live with no rig; the chain needs 1..8 unique live segments");
        Errors.Add("the entity must be live with surface motion, and the request needs a");
        return Errors;
    }
}
