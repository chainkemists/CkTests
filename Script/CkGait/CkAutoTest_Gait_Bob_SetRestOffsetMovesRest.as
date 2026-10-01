// Language=angelscript
class UCk_AutoTest_Gait_Bob_SetRestOffsetMovesRest : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;
    private FCk_GaitAutoTestFixture _F;
    private FCk_Handle _Owner;
    private const FTransform _Rest = FTransform(FVector(0.0, 0.0, 64.0));
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _Result = ECk_Request_OperationResult::Failed;
    private const FTransform _NewRest = FTransform(FVector(0.0, 0.0, 90.0));

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step("spawn the test character", n"Step_Spawn");
        Add_Step_WaitUntil("character entity constructed", n"Check_EntityReady");
        Add_Step("compose a gait and a bob", n"Step_Compose");
        Add_Step_WaitSeconds("let Bob publish its rest offset", 0.1f);
        Add_Step("request a new rest offset", n"Step_SetRest");
        // No expected error is registered: a foreign-write ensure from Bob's own republish would fail this row.
        Add_Step_WaitUntil("node moves onto the new rest", n"Check_AtNewRest");
        Add_Step("assert the request succeeded once", n"Step_Verify");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Step_Spawn(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Owner = InHandle;
        _F.Spawn(this, FVector(9000.0, 31000.0, -40000.0));
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
    private void Step_SetRest(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_bob::Request_SetRestOffset(_F.Bob, FCk_Request_Bob_SetRestOffset(_NewRest),
            FCk_Delegate_Request_OnCompleted(this, n"OnCompleted"));
    }

    UFUNCTION()
    private void OnCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_Completions;
        _Result = InResult;
    }

    UFUNCTION()
    private void Check_AtNewRest(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(Math::Abs(_F.BobWorld().GetLocation().Z - (_F.RootWorld().GetLocation().Z + 90.0)) <= 0.05);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "SetRestOffset completes exactly once");
        Assert_True(_Result == ECk_Request_OperationResult::Succeeded, "SetRestOffset succeeded");
        Assert_True(utils_bob::Get_RestOffset(_F.Bob).Equals(_NewRest, 0.001), "the new rest offset is retained");
        Assert_True(_F.BobWorld().Equals(_NewRest * _F.RootWorld(), 0.05), "the node world pose is the new rest over the root");
        FinishSuccess();
    }
}

class ACk_AutoTest_Gait_Bob_SetRestOffsetMovesRest_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Gait_Bob_SetRestOffsetMovesRest;
    default _TimeoutSeconds = 10.0f;
}
