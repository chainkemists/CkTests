// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_DetachLegReleasesPartsAndRebalances : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 72500.0, 600.0);
    private float _PhaseStart = 0.0;
    private int32 _EnsuresBefore = 0;
    private FVector _BodyAtDetach;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _CompletionResult = ECk_Request_OperationResult::Failed;
    private int32 _Detachments = 0;
    private TArray<FCk_Handle_Transform> _ReleasedParts;
    private TArray<float> _ReleasedZ;
    private FCk_Handle _ReleasedFoot;
    private int32 _LegSetChanges = 0;
    private int32 _EnabledCount = -1;
    private int32 _TotalCount = -1;

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (_Fixture.Create(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, false, 1) == false)
        {
            FinishFailure("The isolated single-walker floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the walker is composed and evaluated", n"Check_Ready", 1200);
        Add_Step("bind the detach and leg-set signals", n"Step_Bind");
        Add_Step_WaitUntil("the walker walks for 1 s", n"Check_Walked");
        Add_Step("detach leg 1", n"Step_Detach");
        Add_Step_WaitUntil("the detach completes and releases its parts", n"Check_Detached");
        Add_Step_WaitUntil("the survivors walk for 1.5 s while the debris falls", n"Check_WalkedAfterDetach");
        Add_Step("verify release, rebalance and ragdoll", n"Step_Verify");
        Add_Step_WaitUntil("the fixture is gone", n"Check_Destroyed");
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
        auto Gait = _Fixture.Crawlers[0].Gait;
        utils_procedural_gait::BindTo_OnLegSetChanged(Gait, FCk_Delegate_ProceduralGait_OnLegSetChanged(this, n"OnLegSetChanged"));
        _PhaseStart = float(System::GetGameTimeInSeconds());
    }

    UFUNCTION()
    private void Check_Walked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 1.0);
    }

    UFUNCTION()
    private void Step_Detach(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _EnsuresBefore = utils_ensure::Get_EnsureCount();
        _BodyAtDetach = utils_transform::Get_EntityCurrentLocation(_Fixture.Crawlers[0].Root);
        _ReleasedFoot = _Fixture.Crawlers[0].VisibleFeet[1];
        auto Leg = _Fixture.Crawlers[0].Legs[1];
        utils_procedural_leg::Request_Detach(Leg,
            FCk_Request_ProceduralLeg_Detach(ECk_ProceduralLeg_ReleasedPartsOwnership::KeepBodyOwned),
            FCk_Delegate_Request_OnCompleted(this, n"OnDetachCompleted"));
    }

    UFUNCTION()
    private void OnDetached(FCk_Handle_ProceduralLeg InLeg, FCk_ProceduralLeg_ReleasedParts InReleasedParts)
    {
        _Detachments++;
        _ReleasedParts = InReleasedParts.Get_Parts();
        for (auto Part : _ReleasedParts)
        {
            _ReleasedZ.Add(utils_transform::Get_EntityCurrentLocation(Part).Z);
        }
        _Fixture.Request_RagdollReleasedParts(InLeg, InReleasedParts);
    }

    UFUNCTION()
    private void OnDetachCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Completions++;
        _CompletionResult = InResult;
    }

    UFUNCTION()
    private void OnLegSetChanged(FCk_Handle_ProceduralGait InGait, int32 InEnabledCount, int32 InTotalCount)
    {
        _LegSetChanges++;
        _EnabledCount = InEnabledCount;
        _TotalCount = InTotalCount;
    }

    UFUNCTION()
    private void Check_Detached(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Detached = _Detachments > 0 && _Completions > 0;
        if (Detached)
        {
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Detached);
    }

    UFUNCTION()
    private void Check_WalkedAfterDetach(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 1.5);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        Assert_Equals_Int(_Completions, 1, "The detach request completes exactly once");
        Assert_True(_CompletionResult == ECk_Request_OperationResult::Succeeded, "The detach request completes Succeeded");
        Assert_Equals_Int(_Detachments, 1, "OnDetached fires exactly once");
        Assert_Equals_Int(_ReleasedParts.Num(), 3, "The released chain carries both segments and the foot");
        Assert_Equals_Int(_LegSetChanges, 1, "OnLegSetChanged fires exactly once");
        Assert_Equals_Int(_EnabledCount, 3, "The leg-set change reports three enabled legs");
        Assert_Equals_Int(_TotalCount, 4, "The leg-set change reports four authored legs");
        Assert_Equals_Int(utils_procedural_leg::Get_Legs(Crawler.Root).Num(), 3, "The body's record keeps three legs");
        Assert_Equals_Int(utils_procedural_gait::Get_EnabledLegCount(Crawler.Gait), 3, "The gait counts three enabled legs");
        Assert_True(utils_procedural_gait::Get_IsReady(Crawler.Gait), "The gait keeps evaluating on the survivors");
        Assert_Equals_Int(utils_ensure::Get_EnsureCount() - _EnsuresBefore, 0, "Detaching and ragdolling fire no ensure");

        auto Travel = (utils_transform::Get_EntityCurrentLocation(Crawler.Root) - _BodyAtDetach).Size();
        Assert_True(Travel > 100.0, f"The survivors keep walking after the detach ({Travel :.1} cm)");

        for (auto Index = 0; Index < _ReleasedParts.Num() && Index < _ReleasedZ.Num(); Index++)
        {
            auto Part = _ReleasedParts[Index];
            Assert_True(ck::IsValid(Part), f"Released part {Index} is still alive");
            if (ck::Is_NOT_Valid(Part))
            {
                continue;
            }
            auto Z = utils_transform::Get_EntityCurrentLocation(Part).Z;
            Assert_True(Z > _Origin.Z - 2.0, f"Released part {Index} rests on the floor instead of falling through ({Z :.1})");
            if (FCk_Handle(Part) == _ReleasedFoot)
            {
                // The foot was already planted on the floor, so it cannot drop further; it must not be launched.
                Assert_True(Z < _ReleasedZ[Index] + 10.0, f"The released foot settles on the floor ({_ReleasedZ[Index] :.1} -> {Z :.1})");
            }
            else
            {
                Assert_True(Z < _ReleasedZ[Index] - 20.0, f"Released segment {Index} fell more than 20 cm ({_ReleasedZ[Index] :.1} -> {Z :.1})");
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
