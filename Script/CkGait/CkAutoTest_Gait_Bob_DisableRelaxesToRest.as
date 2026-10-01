// Language=angelscript
class UCk_AutoTest_Gait_Bob_DisableRelaxesToRest : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private const FTransform _Rest = FTransform(FVector(0.0, 0.0, 64.0));
    private int32 _DisableCompletions = 0;
    private ECk_Request_OperationResult _DisableResult = ECk_Request_OperationResult::Failed;
    private int32 _EnableCompletions = 0;
    private ECk_Request_OperationResult _EnableResult = ECk_Request_OperationResult::Failed;
    private float64 _WindowStartSeconds = 0.0;
    private float _MaxSpringAfterEnable = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("compose a gait and a bob", n"Step_Compose");
        Add_Step("fly at the reference speed", n"Step_Fly");
        Add_Step_WaitUntil("bob offset is visible", n"Check_OffsetVisible");
        Add_Step("disable the bob", n"Step_Disable");
        Add_Step_WaitUntil("bob node relaxes onto its rest", n"Check_AtRest");
        Add_Step("assert disabled, then fall", n"Step_VerifyDisabledAndFall");
        Add_Step_WaitUntil("gait samples airborne", n"Check_Airborne");
        Add_Step("land", n"Step_Land");
        Add_Step_WaitUntil("gait counts the landing while the bob is disabled", n"Check_GaitLanded");
        Add_Step("enable the bob with the character at rest", n"Step_Enable");
        Add_Step_WaitUntil("Enable drained", n"Check_Enabled");
        // Negative window (the stale landing must NOT kick): sampled every poll for 0.3 s of game time.
        Add_Step_WaitUntil("watch the spring for 0.3 s after enabling", n"Check_SpringWindowElapsed");
        Add_Step("assert the spring never moved", n"Step_VerifyNoKick");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(6000.0, 31000.0, -40000.0));
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
    private void Step_Compose(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto GaitSpec = FCk_Gait_Spec();
        auto Stride = GaitSpec.Get_Stride();
        Stride.Set_AmountInterpSpeed(20.0f);
        GaitSpec.Set_Stride(Stride);
        _F.AddGait(GaitSpec);
        Assert_Valid(_F.Gait, "gait added to the character's entity");

        _F.CreateBob(_Rest, Make_DemoSpec());
        Assert_Valid(_F.Bob, "bob node created under the root");
    }

    // Vertical 6 cm, lateral 4 cm, no lag, no breath: every observable offset comes from the stride or the spring.
    private FCk_Bob_Spec Make_DemoSpec() const
    {
        auto Spec = FCk_Bob_Spec();
        Spec.Set_Stride(FCk_Bob_StrideParams(6.0f, 4.0f));
        Spec.Set_LagRate(0.0f);
        Spec.Set_BreathCm(0.0f);
        return Spec;
    }

    UFUNCTION()
    private void Step_Fly(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Character.Fly(FVector(420.0, 0.0, 0.0));
    }

    UFUNCTION()
    private void Check_OffsetVisible(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_bob::Get_BobOffset(_F.Bob).GetLocation().Size() > 1.0);
    }

    UFUNCTION()
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_bob::Request_EnableDisable(_F.Bob, FCk_Request_Bob_EnableDisable(ECk_EnableDisable::Disable),
            FCk_Delegate_Request_OnCompleted(this, n"OnDisableCompleted"));
    }

    UFUNCTION()
    private void OnDisableCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_DisableCompletions;
        _DisableResult = InResult;
    }

    UFUNCTION()
    private void Check_AtRest(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_F.BobWorld().Equals(_Rest * _F.RootWorld(), 0.05));
    }

    UFUNCTION()
    private void Step_VerifyDisabledAndFall(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_DisableCompletions, 1, "Disable completes exactly once");
        Assert_True(_DisableResult == ECk_Request_OperationResult::Succeeded, "Disable succeeded");
        Assert_False(utils_bob::Get_IsEnabled(_F.Bob), "bob reports disabled");
        Assert_Equals_Int(utils_gait::Get_LandingCount(_F.Gait), 0, "no landing before the fall");
        _F.Character.Fall(600.0f);
    }

    UFUNCTION()
    private void Check_Airborne(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_LastMotion(_F.Gait).Get_Footing() == ECk_Gait_Footing::Airborne);
    }

    UFUNCTION()
    private void Step_Land(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _F.Character.Land();
    }

    UFUNCTION()
    private void Check_GaitLanded(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_gait::Get_LandingCount(_F.Gait) == 1);
    }

    UFUNCTION()
    private void Step_Enable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_bob::Request_EnableDisable(_F.Bob, FCk_Request_Bob_EnableDisable(ECk_EnableDisable::Enable),
            FCk_Delegate_Request_OnCompleted(this, n"OnEnableCompleted"));
    }

    UFUNCTION()
    private void OnEnableCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_EnableCompletions;
        _EnableResult = InResult;
    }

    UFUNCTION()
    private void Check_Enabled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        const auto Drained = _EnableCompletions > 0;
        if (Drained)
        {
            _WindowStartSeconds = System::GetGameTimeInSeconds();
        }

        Res.Set(Drained);
    }

    UFUNCTION()
    private void Check_SpringWindowElapsed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        _MaxSpringAfterEnable = Math::Max(_MaxSpringAfterEnable, Math::Abs(utils_bob::Get_SpringOffset(_F.Bob)));
        Res.Set(System::GetGameTimeInSeconds() - _WindowStartSeconds >= 0.3);
    }

    UFUNCTION()
    private void Step_VerifyNoKick(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_EnableCompletions, 1, "Enable completes exactly once");
        Assert_True(_EnableResult == ECk_Request_OperationResult::Succeeded, "Enable succeeded");
        Assert_True(utils_bob::Get_IsEnabled(_F.Bob), "bob reports enabled");
        Assert_Equals_Int(utils_gait::Get_LandingCount(_F.Gait), 1, "the gait still holds the landing counted while disabled");
        Assert_True(_MaxSpringAfterEnable < 0.05f,
            f"the landing counted while disabled did not kick the spring on re-enable (max |spring| {_MaxSpringAfterEnable} cm)");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_Bob_DisableRelaxesToRest_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_Bob_DisableRelaxesToRest;
    default _TimeoutSeconds = 10.0f;
}
