// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_ApplyPresetRetunesLiveGait : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 77500.0, 600.0);
    private float _PhaseStart = 0.0;
    private TArray<bool> _WasPlanted;
    private int32 _Landings = 0;
    private int32 _LandingsBefore = 0;
    private int32 _LandingsAfter = 0;
    private float _LastClock = 0.0;
    private float _LastClockDelta = 0.0;
    private TArray<FVector> _LastFeet;
    private TArray<bool> _LastPlanted;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _CompletionResult = ECk_Request_OperationResult::Failed;
    private bool _ApplyObserved = false;
    private float _ApplyClockDelta = 0.0;
    private float _ApplyFootShift = 0.0;
    private int32 _FeetPlantedAcrossApply = 0;

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    float Get_WrappedDelta(float InFrom, float InTo) const
    {
        return Math::Frac(InTo - InFrom + 1.5) - 0.5;
    }

    void CountLandings()
    {
        auto Legs = _Fixture.Crawlers[0].Legs;
        if (_WasPlanted.Num() != Legs.Num())
        {
            _WasPlanted.SetNum(Legs.Num());
        }
        for (auto Index = 0; Index < Legs.Num(); Index++)
        {
            auto Planted = utils_procedural_leg::Get_Foot(Legs[Index]).Get_Planted();
            if (Planted && _WasPlanted[Index] == false)
            {
                _Landings++;
            }
            _WasPlanted[Index] = Planted;
        }
    }

    void SampleGait()
    {
        auto Clock = utils_procedural_gait::Get_GaitClock(_Fixture.Crawlers[0].Gait);
        _LastClockDelta = Get_WrappedDelta(_LastClock, Clock);
        _LastClock = Clock;
        _LastFeet.Reset();
        _LastPlanted.Reset();
        for (auto Leg : _Fixture.Crawlers[0].Legs)
        {
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            _LastFeet.Add(Foot.Get_Position());
            _LastPlanted.Add(Foot.Get_Planted());
        }
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
        Add_Step_WaitUntil("the walker settles into its stride for 1 s", n"Check_Warmup");
        Add_Step_WaitUntil("landings are counted over 1 s at the authored cadence", n"Check_BeforeWindow");
        Add_Step("apply the slow preset", n"Step_Apply");
        Add_Step_WaitUntil("the preset is applied on a live gait", n"Check_Applied");
        Add_Step_WaitUntil("landings are counted over 2 s at the slow cadence", n"Check_AfterWindow");
        Add_Step("verify the retune kept leg state and slowed the steps", n"Step_Verify");
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
        auto Ready = _Fixture.Get_IsReady();
        if (Ready)
        {
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Warmup(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        CountLandings();
        auto Done = Get_Elapsed() >= 1.0;
        if (Done)
        {
            _Landings = 0;
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Done);
    }

    UFUNCTION()
    private void Check_BeforeWindow(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        CountLandings();
        SampleGait();
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 1.0);
    }

    UFUNCTION()
    private void Step_Apply(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _LandingsBefore = _Landings;
        _Landings = 0;
        SampleGait();
        auto Gait = _Fixture.Crawlers[0].Gait;
        utils_procedural_gait::Request_ApplyPreset(Gait, ck::ProceduralGym_GaitSlow,
            FCk_Delegate_Request_OnCompleted(this, n"OnApplied"));
    }

    UFUNCTION()
    private void OnApplied(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _Completions++;
        _CompletionResult = InResult;
    }

    UFUNCTION()
    private void Check_Applied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        CountLandings();
        if (_Completions == 0)
        {
            SampleGait();
            auto Pending = OutResult;
            Pending.Set(false);
            return;
        }
        _ApplyObserved = true;
        _ApplyClockDelta = Get_WrappedDelta(_LastClock, utils_procedural_gait::Get_GaitClock(_Fixture.Crawlers[0].Gait));
        auto Legs = _Fixture.Crawlers[0].Legs;
        for (auto Index = 0; Index < Legs.Num() && Index < _LastFeet.Num(); Index++)
        {
            auto Foot = utils_procedural_leg::Get_Foot(Legs[Index]);
            if (_LastPlanted[Index] && Foot.Get_Planted())
            {
                _FeetPlantedAcrossApply++;
                _ApplyFootShift = Math::Max(_ApplyFootShift, (Foot.Get_Position() - _LastFeet[Index]).Size());
            }
        }
        _PhaseStart = float(System::GetGameTimeInSeconds());
        auto Result = OutResult;
        Result.Set(true);
    }

    UFUNCTION()
    private void Check_AfterWindow(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        CountLandings();
        auto Done = Get_Elapsed() >= 2.0;
        if (Done)
        {
            _LandingsAfter = _Landings;
        }
        auto Result = OutResult;
        Result.Set(Done);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_Completions, 1, "The apply-preset request completes exactly once");
        Assert_True(_CompletionResult == ECk_Request_OperationResult::Succeeded, "The apply-preset request completes Succeeded");
        Assert_True(_ApplyObserved, "The apply frame was observed");
        // A reset would re-seed the clock at zero; a live retune only keeps advancing it by about one frame.
        Assert_True(_ApplyClockDelta >= 0.0 && _ApplyClockDelta <= Math::Max(3.0 * _LastClockDelta, 0.05),
            f"The gait clock is continuous across the apply frame (advanced {_ApplyClockDelta :.4} after {_LastClockDelta :.4})");
        Assert_True(_FeetPlantedAcrossApply > 0, "At least one foot stayed planted across the apply frame");
        Assert_True(_ApplyFootShift < 0.5, f"Planted feet do not move on the apply frame (max shift {_ApplyFootShift :.3} cm)");
        auto RateBefore = float(_LandingsBefore) / 1.0;
        auto RateAfter = float(_LandingsAfter) / 2.0;
        Assert_True(_LandingsBefore > 0, "Precondition: the walker was stepping before the retune");
        Assert_True(RateAfter < RateBefore,
            f"The slow preset lengthens the mean step interval ({RateBefore :.2} -> {RateAfter :.2} landings per second)");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
