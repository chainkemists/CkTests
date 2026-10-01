// Language=angelscript
class UCk_AutoTest_Gait_Bob_UpdateSpecInvalidNotEnqueued : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private const FTransform _Rest = FTransform(FVector(0.0, 0.0, 64.0));
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private float _OriginalVerticalCm = 0.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("compose a gait and a bob", n"Step_Compose");
        Add_Step("request a spec with intensity 2", n"Step_Reject");
        Add_Step_WaitSeconds("observe the rejection window", 0.1f);
        Add_Step("assert the spec is unchanged", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(7000.0, 31000.0, -40000.0));
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
    private void Step_Reject(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _OriginalVerticalCm = utils_bob::Get_Spec(_F.Bob).Get_Stride().Get_VerticalCm();

        auto Invalid = Make_DemoSpec();
        Invalid.Set_Gait(_F.Gait);
        auto InvalidStride = Invalid.Get_Stride();
        InvalidStride.Set_VerticalCm(_OriginalVerticalCm + 3.0f);
        Invalid.Set_Stride(InvalidStride);
        Invalid.Set_Intensity(2.0f);
        utils_bob::Request_UpdateSpec(_F.Bob, FCk_Request_Bob_UpdateSpec(Invalid),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
        Assert_Equals_Int(_Completions, 1, "invalid UpdateSpec completes synchronously");
        Assert_True(_Result == ECk_Request_OperationResult::Failed_NotEnqueued, "invalid UpdateSpec is not enqueued");
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "completion exactly once");
        Assert_True(utils_bob::Get_Spec(_F.Bob).Get_Stride().Get_VerticalCm() == _OriginalVerticalCm, "vertical amplitude unchanged");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_Bob_UpdateSpecInvalidNotEnqueued_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_Bob_UpdateSpecInvalidNotEnqueued;
    default _TimeoutSeconds = 10.0f;
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Errors;
        Errors.Add("Bob UpdateSpec rejected invalid spec");
        return Errors;
    }
}
