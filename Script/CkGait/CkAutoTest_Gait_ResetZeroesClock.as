// Language=angelscript
class UCk_AutoTest_Gait_ResetZeroesClock : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private float32 _AmountAtReset = -1.0f;
    private float32 _PhaseAtReset = -1.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("add a gait and fly at the reference speed", n"Step_Fly");
        Add_Step_WaitUntil("amount rises above 0.9", n"Check_AmountRaised");
        Add_Step("request Reset", n"Step_Reset");
        Add_Step_WaitUntil("Reset drained", n"Check_ResetCompleted");
        Add_Step("assert the clock was zeroed", n"Step_VerifyZeroed");
        Add_Step_WaitUntil("amount rises again while still flying", n"Check_AmountRisesAgain", 0, 0.5f);
        Add_Step("finish", n"Step_Finish");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(7000.0, 30000.0, -40000.0));
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
    private void Step_Fly(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spec = FCk_Gait_Spec();
        auto Stride = Spec.Get_Stride();
        Stride.Set_AmountInterpSpeed(20.0f);
        Spec.Set_Stride(Stride);
        _F.AddGait(Spec);
        Assert_Valid(_F.Gait, "gait added to the character's entity");
        _F.Character.Fly(FVector(420.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_AmountRaised(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_Amount(_F.Gait) > 0.9f);
    }

    UFUNCTION()
    private void Step_Reset(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_gait::Request_Reset(_F.Gait, FCk_Request_Gait_Reset(), FCk_Delegate_Request_OnCompleted(this, n"OnResetCompleted"));
    }

    // The completion fires inside the request drain, right after the reset and BEFORE this frame's Update steps the clock
    // again (Update runs after HandleRequests in the same FGroup_Gameplay pass), so this is the one place the zeroed clock
    // is observable: a test-step poll only ever sees it after one more step at full speed.
    UFUNCTION()
    private void OnResetCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
        _AmountAtReset = utils_gait::Get_Amount(_F.Gait);
        _PhaseAtReset = utils_gait::Get_Phase(_F.Gait);
    }

    UFUNCTION()
    private void Check_ResetCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_Completions > 0);
    }

    UFUNCTION()
    private void Step_VerifyZeroed(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "Reset completes exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "Reset succeeded");
        Assert_Equals_Float(_AmountAtReset, 0.0f, 1.0e-6f, "amount is zero after Reset");
        Assert_Equals_Float(_PhaseAtReset, 0.0f, 1.0e-6f, "phase is zero after Reset");
    }

    UFUNCTION()
    private void Check_AmountRisesAgain(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_Amount(_F.Gait) > 0.5f);
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_ResetZeroesClock_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_ResetZeroesClock;
    default _TimeoutSeconds = 10.0f;
}
