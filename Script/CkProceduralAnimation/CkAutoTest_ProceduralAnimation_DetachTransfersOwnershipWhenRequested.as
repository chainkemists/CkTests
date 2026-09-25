// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_DetachTransfersOwnershipWhenRequested : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 75000.0, 600.0);
    private float _PhaseStart = 0.0;
    private int32 _Detachments = 0;
    private TArray<FCk_Handle_Transform> _ReleasedParts;
    private FCk_Handle _Body;
    private FCk_Handle_ProceduralGait _Gait;
    private TArray<FCk_Handle_ProceduralLeg> _Legs;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated single-walker floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the walker is composed and evaluated", n"Check_Ready", 1200);
        Add_Step("bind the detach signal", n"Step_Bind");
        Add_Step_WaitUntil("the walker walks for 1 s", n"Check_Walked");
        Add_Step("detach leg 1 and hand its parts to the world", n"Step_Detach");
        Add_Step_WaitUntil("the detach releases its parts", n"Check_Detached");
        Add_Step("destroy the body", n"Step_DestroyBody");
        Add_Step_WaitUntil("the body, its gait and its legs are gone", n"Check_BodyGone");
        // Two frames cover a child sweep that trails the owner's destruction by a frame.
        Add_Step_WaitFrames("the released parts outlive the body's destruction", 2);
        Add_Step("verify the parts survived and retire them", n"Step_VerifyAndCleanup");
        Add_Step_WaitUntil("the parts and the fixture are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"The walker could not be composed: {_Fixture.CompositionError}");
            return;
        }
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsReady());
    }

    UFUNCTION()
    private void Step_Bind(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Leg = _Fixture.Crawlers[0].Legs[1];
        utils_procedural_leg::BindTo_OnDetached(Leg, FCk_Delegate_ProceduralLeg_OnDetached(this, n"OnDetached"));
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Walked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(float(System::GetGameTimeInSeconds()) - _PhaseStart >= 1.0);
    }

    UFUNCTION()
    private void Step_Detach(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Leg = _Fixture.Crawlers[0].Legs[1];
        utils_procedural_leg::Request_Detach(Leg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::TransferToWorld));
    }

    UFUNCTION()
    private void OnDetached(FCk_Handle_ProceduralLeg InLeg, FCk_ProceduralLeg_ReleasedParts InReleasedParts)
    {
        _Detachments++;
        _ReleasedParts = InReleasedParts.Get_Parts();
        _Fixture.Request_RagdollReleasedParts(InLeg, InReleasedParts);
    }

    UFUNCTION()
    private void Check_Detached(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(_Detachments > 0 && ck::Is_NOT_Valid(_Fixture.Crawlers[0].Legs[1]));
    }

    UFUNCTION()
    private void Step_DestroyBody(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Detachments, 1, "OnDetached fires exactly once");
        Assert_Equals_Int(_ReleasedParts.Num(), 3, "The released chain carries both segments and the foot");
        _Body = _Fixture.Crawlers[0].Root;
        _Gait = _Fixture.Crawlers[0].Gait;
        _Legs = _Fixture.Crawlers[0].Legs;
        utils_entity_lifetime::Request_DestroyEntity(_Body);
    }

    UFUNCTION()
    private void Check_BodyGone(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Gone = ck::Is_NOT_Valid(_Body) && ck::Is_NOT_Valid(_Gait);
        for (auto Leg : _Legs)
        {
            Gone = Gone && ck::Is_NOT_Valid(Leg);
        }
        auto Result = OutResult;
        Result.Set(Gone);
    }

    UFUNCTION()
    private void Step_VerifyAndCleanup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _ReleasedParts.Num(); Index++)
        {
            Assert_True(ck::IsValid(_ReleasedParts[Index]), f"Released part {Index} outlives the destroyed body");
        }
        for (auto Part : _ReleasedParts)
        {
            if (ck::IsValid(Part))
            {
                auto PartEntity = FCk_Handle(Part);
                utils_entity_lifetime::Request_DestroyEntity(PartEntity);
            }
        }
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
