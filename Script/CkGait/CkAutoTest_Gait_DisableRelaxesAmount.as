// Language=angelscript
class UCk_AutoTest_Gait_DisableRelaxesAmount : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private int32 _LandingsAtDisable = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("add a gait and fly at the reference speed", n"Step_Fly");
        Add_Step_WaitUntil("amount rises above 0.9", n"Check_AmountRaised");
        Add_Step("disable the gait", n"Step_Disable");
        Add_Step_WaitUntil("amount relaxes below 0.05", n"Check_AmountRelaxed");
        Add_Step("assert disabled, then fall", n"Step_VerifyDisabledAndFall");
        // Negative window (the landing must not count): the positive is the character really falling, asserted above.
        Add_Step_WaitSeconds("stay airborne while disabled", 0.1f);
        Add_Step("land", n"Step_Land");
        Add_Step_WaitSeconds("observe the landing window", 0.1f);
        Add_Step("assert no landing was counted", n"Step_VerifyNoLanding");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(6000.0, 30000.0, -40000.0));
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
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _LandingsAtDisable = utils_gait::Get_LandingCount(_F.Gait);
        utils_gait::Request_EnableDisable(_F.Gait, FCk_Request_Gait_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Check_AmountRelaxed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_Amount(_F.Gait) < 0.05f);
    }

    UFUNCTION()
    private void Step_VerifyDisabledAndFall(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "Disable completes exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "Disable succeeded");
        Assert_False(utils_gait::Get_IsEnabled(_F.Gait), "gait reports disabled");
        _F.Character.Fall(600.0f);
        Assert_True(_F.Character.CharacterMovement.IsFalling(), "the character's movement component really falls");
    }

    UFUNCTION()
    private void Step_Land(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Character.Land();
    }

    UFUNCTION()
    private void Step_VerifyNoLanding(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(utils_gait::Get_LandingCount(_F.Gait), _LandingsAtDisable, "a disabled gait counts no landing");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_DisableRelaxesAmount_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_DisableRelaxesAmount;
    default _TimeoutSeconds = 10.0f;
}
