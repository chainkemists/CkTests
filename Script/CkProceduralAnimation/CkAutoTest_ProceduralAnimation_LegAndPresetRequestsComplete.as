// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_LegAndPresetRequestsComplete : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;
    default _AutoStageOriginField = false;
    private FVector _Origin = FVector(120000.0, 85000.0, 1000.0);
    private FCk_Handle _SucceedingRoot;
    private FCk_Handle _CancelledRoot;
    private FCk_Handle_ProceduralLeg _DisabledLeg;
    private FCk_Handle_ProceduralLeg _DetachedLeg;
    private FCk_Handle_ProceduralGait _RetunedGait;
    private FCk_Handle _CancelledEnableDisableLeg;
    private FCk_Handle _CancelledDetachLeg;
    private TArray<ECk_Request_OperationResult> _EnableDisableResults;
    private TArray<ECk_Request_OperationResult> _DetachResults;
    private TArray<ECk_Request_OperationResult> _ApplyPresetResults;

    FCk_Handle_Transform CreateTransform(FCk_Handle InOwner, FVector InPosition)
    {
        auto Owner = InOwner;
        auto Entity = utils_entity_lifetime::Request_CreateEntity(Owner);
        Entity.Request_OverrideToSelf();
        return utils_transform::Add(Entity, FTransform(InPosition), ECk_Replication::DoesNotReplicate);
    }

    FCk_Request_ProceduralGait_ApplyPreset MakeSlowPresetRequest()
    {
        UCk_ProceduralGait_Data SlowPreset = ck::ProceduralGym_GaitSlow;
        return FCk_Request_ProceduralGait_ApplyPreset(SlowPreset.Get_Timing(), SlowPreset.Get_Step(), SlowPreset.Get_Probe());
    }

    int32 CountResults(const TArray<ECk_Request_OperationResult>& InResults, ECk_Request_OperationResult InResult) const
    {
        auto Count = 0;
        for (auto Result : InResults)
        {
            Count += Result == InResult ? 1 : 0;
        }
        return Count;
    }

    void AssertRejected(const TArray<ECk_Request_OperationResult>& InResults, int32 InResultsBefore, int32 InEnsuresBefore,
        const FString& InCase)
    {
        Assert_Equals_Int(InResults.Num() - InResultsBefore, 1, f"{InCase}: the completion delegate fires exactly once");
        if (InResults.Num() > InResultsBefore)
        {
            Assert_True(InResults.Last() == ECk_Request_OperationResult::Failed_NotEnqueued,
                f"{InCase}: the request completes Failed_NotEnqueued");
        }
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - InEnsuresBefore, 1, f"{InCase}: exactly one ensure fires");
    }

    void AssertCompletedOnce(const TArray<ECk_Request_OperationResult>& InResults, const FString& InRequest)
    {
        Assert_Equals_Int(InResults.Num(), 3, f"{InRequest}: the rejected, drained and cancelled requests complete three times in total");
        Assert_Equals_Int(CountResults(InResults, ECk_Request_OperationResult::Failed_NotEnqueued), 1,
            f"{InRequest}: the invalid-handle request completes Failed_NotEnqueued once");
        Assert_Equals_Int(CountResults(InResults, ECk_Request_OperationResult::Succeeded), 1,
            f"{InRequest}: the live request completes Succeeded once after the drain");
        Assert_Equals_Int(CountResults(InResults, ECk_Request_OperationResult::Failed_Cancelled), 1,
            f"{InRequest}: the request whose owner was destroyed before the drain completes Failed_Cancelled once");
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto InvalidLeg = FCk_Handle_ProceduralLeg();
        auto InvalidGait = FCk_Handle_ProceduralGait();

        auto ResultsBefore = _EnableDisableResults.Num();
        auto EnsuresBefore = utils_ensure::Get_EnsureCount();
        utils_procedural_leg::Request_EnableDisable(InvalidLeg, FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableDisableCompleted"));
        AssertRejected(_EnableDisableResults, ResultsBefore, EnsuresBefore, "Request_EnableDisable on an invalid leg");

        ResultsBefore = _DetachResults.Num();
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        utils_procedural_leg::Request_Detach(InvalidLeg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned),
            FCk_Delegate_Request_OnCompleted(this, n"OnDetachCompleted"));
        AssertRejected(_DetachResults, ResultsBefore, EnsuresBefore, "Request_Detach on an invalid leg");

        ResultsBefore = _ApplyPresetResults.Num();
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        utils_procedural_gait::Request_ApplyPreset(InvalidGait, MakeSlowPresetRequest(),
            FCk_Delegate_Request_OnCompleted(this, n"OnApplyPresetCompleted"));
        AssertRejected(_ApplyPresetResults, ResultsBefore, EnsuresBefore, "Request_ApplyPreset on an invalid gait");

        auto NoChains = TArray<FCk_ProceduralWalker_LegChain>();
        auto SucceedingRoot = CreateTransform(InHandle, _Origin);
        _SucceedingRoot = SucceedingRoot;
        auto SucceedingWalker = utils_procedural_animation::Add_Walker(SucceedingRoot, ck::ProceduralGym_Rig4, ck::ProceduralGym_Gait, NoChains);
        auto CancelledRoot = CreateTransform(InHandle, _Origin + FVector(0.0, 500.0, 0.0));
        _CancelledRoot = CancelledRoot;
        auto CancelledWalker = utils_procedural_animation::Add_Walker(CancelledRoot, ck::ProceduralTest_SideRig, ck::ProceduralGym_Gait, NoChains);
        Assert_True(ck::IsValid(SucceedingWalker.Get_Gait()) && SucceedingWalker.Get_Legs().Num() == 4,
            "Precondition: the succeeding walker is composed with four legs");
        Assert_True(ck::IsValid(CancelledWalker.Get_Gait()) && CancelledWalker.Get_Legs().Num() == 2,
            "Precondition: the cancelled walker is composed with two legs");
        if (SucceedingWalker.Get_Legs().Num() != 4 || CancelledWalker.Get_Legs().Num() != 2)
        {
            return;
        }

        _DisabledLeg = SucceedingWalker.Get_Legs()[0];
        _DetachedLeg = SucceedingWalker.Get_Legs()[1];
        _RetunedGait = SucceedingWalker.Get_Gait();
        auto CompletionsBefore = _EnableDisableResults.Num() + _DetachResults.Num() + _ApplyPresetResults.Num();
        EnsuresBefore = utils_ensure::Get_EnsureCount();
        utils_procedural_leg::Request_EnableDisable(_DisabledLeg, FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableDisableCompleted"));
        utils_procedural_leg::Request_Detach(_DetachedLeg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned),
            FCk_Delegate_Request_OnCompleted(this, n"OnDetachCompleted"));
        utils_procedural_gait::Request_ApplyPreset(_RetunedGait, MakeSlowPresetRequest(),
            FCk_Delegate_Request_OnCompleted(this, n"OnApplyPresetCompleted"));

        // Each owner is destroyed on the same stack as its enqueue, before any request processor can drain.
        auto CancelledEnableDisableLeg = CancelledWalker.Get_Legs()[0];
        auto CancelledDetachLeg = CancelledWalker.Get_Legs()[1];
        auto CancelledGait = CancelledWalker.Get_Gait();
        _CancelledEnableDisableLeg = FCk_Handle(CancelledEnableDisableLeg);
        _CancelledDetachLeg = FCk_Handle(CancelledDetachLeg);
        utils_procedural_leg::Request_EnableDisable(CancelledEnableDisableLeg,
            FCk_Request_ProceduralLeg_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableDisableCompleted"));
        utils_procedural_leg::Request_Detach(CancelledDetachLeg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned),
            FCk_Delegate_Request_OnCompleted(this, n"OnDetachCompleted"));
        utils_procedural_gait::Request_ApplyPreset(CancelledGait, MakeSlowPresetRequest(),
            FCk_Delegate_Request_OnCompleted(this, n"OnApplyPresetCompleted"));
        utils_entity_lifetime::Request_DestroyEntity(_CancelledEnableDisableLeg);
        utils_entity_lifetime::Request_DestroyEntity(_CancelledDetachLeg);
        utils_entity_lifetime::Request_DestroyEntity(_CancelledRoot);

        Assert_Equals_Int(_EnableDisableResults.Num() + _DetachResults.Num() + _ApplyPresetResults.Num() - CompletionsBefore, 0,
            "Positive control: live requests are enqueued, not completed synchronously");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - EnsuresBefore, 0, "Positive control: enqueueing on live owners fires no ensure");

        Add_Step_WaitUntil("the live requests drain and the destroyed owners' requests are cancelled", n"Check_Drained");
        Add_Step("verify each request completed once per case and the drained requests took effect", n"Step_VerifyDrained");
        Add_Step_WaitUntil("the succeeding walker is destroyed", n"Check_SucceedingDestroyed");
        Add_Step("verify no request completed again during the later teardown", n"Step_VerifyExactlyOnce");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void OnEnableDisableCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _EnableDisableResults.Add(InResult);
    }

    UFUNCTION()
    private void OnDetachCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _DetachResults.Add(InResult);
    }

    UFUNCTION()
    private void OnApplyPresetCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _ApplyPresetResults.Add(InResult);
    }

    UFUNCTION()
    private void Check_Drained(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Succeeded = CountResults(_EnableDisableResults, ECk_Request_OperationResult::Succeeded) > 0
            && CountResults(_DetachResults, ECk_Request_OperationResult::Succeeded) > 0
            && CountResults(_ApplyPresetResults, ECk_Request_OperationResult::Succeeded) > 0;
        auto Cancelled = CountResults(_EnableDisableResults, ECk_Request_OperationResult::Failed_Cancelled) > 0
            && CountResults(_DetachResults, ECk_Request_OperationResult::Failed_Cancelled) > 0
            && CountResults(_ApplyPresetResults, ECk_Request_OperationResult::Failed_Cancelled) > 0;
        auto Gone = ck::Is_NOT_Valid(_DetachedLeg) && ck::Is_NOT_Valid(_CancelledRoot)
            && ck::Is_NOT_Valid(_CancelledEnableDisableLeg) && ck::Is_NOT_Valid(_CancelledDetachLeg);
        auto Result = OutResult;
        Result.Set(Succeeded && Cancelled && Gone);
    }

    UFUNCTION()
    private void Step_VerifyDrained(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        AssertCompletedOnce(_EnableDisableResults, "Request_EnableDisable");
        AssertCompletedOnce(_DetachResults, "Request_Detach");
        AssertCompletedOnce(_ApplyPresetResults, "Request_ApplyPreset");
        Assert_True(ck::IsValid(_DisabledLeg) && utils_procedural_leg::Get_EnableDisable(_DisabledLeg) != ECk_EnableDisable::Enable,
            "The drained enable/disable request left its leg disabled");
        Assert_True(ck::IsValid(_RetunedGait) && utils_procedural_gait::Get_Status(_RetunedGait) != ECk_ProceduralAnimation_Status::Failed,
            "The retuned gait is still live and has not failed");
        utils_entity_lifetime::Request_DestroyEntity(_SucceedingRoot);
    }

    UFUNCTION()
    private void Check_SucceedingDestroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(ck::Is_NOT_Valid(_SucceedingRoot) && ck::Is_NOT_Valid(_DisabledLeg));
    }

    UFUNCTION()
    private void Step_VerifyExactlyOnce(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_EnableDisableResults.Num(), 3, "Request_EnableDisable completions never repeat through a later teardown");
        Assert_Equals_Int(_DetachResults.Num(), 3, "Request_Detach completions never repeat through a later teardown");
        Assert_Equals_Int(_ApplyPresetResults.Num(), 3, "Request_ApplyPreset completions never repeat through a later teardown");
    }
}

// The invalid-handle cases exercise loud public-contract rejections. A hand-authored wrapper owns expected
// diagnostics; they do not belong on the entity script.
class ACk_AutoTest_ProceduralAnimation_LegAndPresetRequestsComplete_Actor : ACk_AutoTestRunner
{
    default _TimeoutSeconds = 8.0f;

    UFUNCTION(BlueprintOverride)
    TSubclassOf<UCk_EntityScript_UE> Get_TestEntityScriptClass() const
    {
        auto Path = FSoftClassPath("/Script/Angelscript.Ck_AutoTest_ProceduralAnimation_LegAndPresetRequestsComplete");
        TSubclassOf<UCk_EntityScript_UE> ResolvedClass;
        ResolvedClass = Path.TryLoadClass();
        return ResolvedClass;
    }

    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        auto Errors = TArray<FString>();
        Errors.Add("it must be a live leg entity.");
        Errors.Add("the gait must be live and the preset well-formed and within the leg count.");
        return Errors;
    }
}
