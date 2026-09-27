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
    private float _LastClock = 0.0;
    private float _LastClockDelta = 0.0;
    private float _WindowClock = 0.0;
    private float _WindowTime = 0.0;
    private float _ClockAdvance = 0.0;
    private float _ClockSeconds = 0.0;
    private float _ClockRateBefore = 0.0;
    private float _ClockRateAfter = 0.0;
    private TArray<FVector> _LastFeet;
    private TArray<bool> _LastPlanted;
    private int32 _Completions = 0;
    private ECk_Request_OperationResult _CompletionResult = ECk_Request_OperationResult::Failed;
    private bool _ApplyObserved = false;
    private float _ApplyClockDelta = 0.0;
    private float _ApplyFootShift = 0.0;
    private int32 _FeetPlantedAcrossApply = 0;
    private int32 _WideKeepRadiusCompletions = 0;
    private ECk_Request_OperationResult _WideKeepRadiusResult = ECk_Request_OperationResult::Failed;

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
        auto Legs = _Fixture.Crawlers[0].Handles.Legs;
        if (_WasPlanted.Num() != Legs.Num())
        {
            _WasPlanted.SetNum(Legs.Num());
        }
        for (auto Index = 0; Index < Legs.Num(); Index++)
        {
            auto Planted = utils_procedural_leg::Get_Foot(Legs[Index]).Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted;
            if (Planted && _WasPlanted[Index] == false)
            {
                _Landings++;
            }
            _WasPlanted[Index] = Planted;
        }
    }

    void SampleGait()
    {
        auto Clock = utils_procedural_gait::Get_GaitClock(_Fixture.Crawlers[0].Handles.Gait);
        _LastClockDelta = Get_WrappedDelta(_LastClock, Clock);
        _LastClock = Clock;
        _LastFeet.Reset();
        _LastPlanted.Reset();
        for (auto Leg : _Fixture.Crawlers[0].Handles.Legs)
        {
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            _LastFeet.Add(Foot.Get_Position());
            _LastPlanted.Add(Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted);
        }
    }

    // The clock's wrapped per-frame advance summed over whole frames is a cadence measure that does not
    // depend on how many landings happen to fall inside a window.
    void BeginClockWindow()
    {
        _WindowClock = utils_procedural_gait::Get_GaitClock(_Fixture.Crawlers[0].Handles.Gait);
        _WindowTime = float(System::GetGameTimeInSeconds());
        _ClockAdvance = 0.0;
        _ClockSeconds = 0.0;
    }

    void AccumulateClock()
    {
        auto Clock = utils_procedural_gait::Get_GaitClock(_Fixture.Crawlers[0].Handles.Gait);
        auto Now = float(System::GetGameTimeInSeconds());
        _ClockAdvance += Get_WrappedDelta(_WindowClock, Clock);
        _ClockSeconds += Now - _WindowTime;
        _WindowClock = Clock;
        _WindowTime = Now;
    }

    float Get_ClockRate() const
    {
        return _ClockSeconds > 0.0 ? _ClockAdvance / _ClockSeconds : 0.0;
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
        Add_Step_WaitUntil("landings and the gait clock rate are measured over 1 s at the authored cadence", n"Check_BeforeWindow");
        Add_Step("apply the slow preset", n"Step_Apply");
        Add_Step_WaitUntil("the preset is applied on a live gait", n"Check_Applied");
        Add_Step_WaitUntil("the gait clock rate is measured over 2 s at the slow cadence", n"Check_AfterWindow");
        Add_Step("verify the retune kept leg state and slowed the steps", n"Step_Verify");
        Add_Step("apply a preset whose held footholds may lie 500 cm from the ideal", n"Step_ApplyWideKeepRadius");
        Add_Step_WaitUntil("the wide keep-radius preset completes", n"Check_WideKeepRadiusApplied");
        // A settle, not a condition: the assertion after it is that nothing latches a failure while the gait runs on
        // the wide keep radius; the completion above already proved the preset landed.
        Add_Step_WaitFrames("the gait updates with the wide keep radius", 10);
        Add_Step("verify the walker stays ready and retire the fixture", n"Step_VerifyWideKeepRadius");
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
        auto Ready = _Fixture.Get_AllReady();
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
            BeginClockWindow();
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
        AccumulateClock();
        auto Done = Get_Elapsed() >= 1.0;
        if (Done)
        {
            _ClockRateBefore = Get_ClockRate();
        }
        auto Result = OutResult;
        Result.Set(Done);
    }

    UFUNCTION()
    private void Step_Apply(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _LandingsBefore = _Landings;
        SampleGait();
        auto Gait = _Fixture.Crawlers[0].Handles.Gait;
        UCk_ProceduralGait_Data SlowPreset = ck::ProceduralGym_GaitSlow;
        utils_procedural_gait::Request_ApplyPreset(Gait,
            FCk_Request_ProceduralGait_ApplyPreset(SlowPreset.Get_Timing(), SlowPreset.Get_Step(), SlowPreset.Get_Probe(),
                SlowPreset.Get_Foothold()),
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
        if (_Completions == 0)
        {
            SampleGait();
            auto Pending = OutResult;
            Pending.Set(false);
            return;
        }
        _ApplyObserved = true;
        _ApplyClockDelta = Get_WrappedDelta(_LastClock, utils_procedural_gait::Get_GaitClock(_Fixture.Crawlers[0].Handles.Gait));
        auto Legs = _Fixture.Crawlers[0].Handles.Legs;
        for (auto Index = 0; Index < Legs.Num() && Index < _LastFeet.Num(); Index++)
        {
            auto Foot = utils_procedural_leg::Get_Foot(Legs[Index]);
            if (_LastPlanted[Index] && Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted)
            {
                _FeetPlantedAcrossApply++;
                _ApplyFootShift = Math::Max(_ApplyFootShift, (Foot.Get_Position() - _LastFeet[Index]).Size());
            }
        }
        _PhaseStart = float(System::GetGameTimeInSeconds());
        BeginClockWindow();
        auto Result = OutResult;
        Result.Set(true);
    }

    UFUNCTION()
    private void Check_AfterWindow(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        AccumulateClock();
        auto Done = Get_Elapsed() >= 2.0;
        if (Done)
        {
            _ClockRateAfter = Get_ClockRate();
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
        Assert_True(_LandingsBefore > 0, "Precondition: the walker was stepping before the retune");
        Assert_True(_ClockRateBefore > 0.0, f"Precondition: the gait clock advanced before the retune ({_ClockRateBefore :.3} cycles per second)");
        Assert_True(_ClockRateAfter < _ClockRateBefore,
            f"The slow preset slows the gait cadence ({_ClockRateBefore :.3} -> {_ClockRateAfter :.3} cycles per second)");
    }

    UFUNCTION()
    private void Step_ApplyWideKeepRadius(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Gait = _Fixture.Crawlers[0].Handles.Gait;
        UCk_ProceduralGait_Data SlowPreset = ck::ProceduralGym_GaitSlow;
        auto Foothold = SlowPreset.Get_Foothold();
        Foothold.Set_KeepRadius(500.0f);
        utils_procedural_gait::Request_ApplyPreset(Gait,
            FCk_Request_ProceduralGait_ApplyPreset(SlowPreset.Get_Timing(), SlowPreset.Get_Step(), SlowPreset.Get_Probe(), Foothold),
            FCk_Delegate_Request_OnCompleted(this, n"OnWideKeepRadiusApplied"));
    }

    UFUNCTION()
    private void OnWideKeepRadiusApplied(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _WideKeepRadiusCompletions++;
        _WideKeepRadiusResult = InResult;
    }

    UFUNCTION()
    private void Check_WideKeepRadiusApplied(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Result = OutResult;
        Result.Set(_WideKeepRadiusCompletions > 0);
    }

    UFUNCTION()
    private void Step_VerifyWideKeepRadius(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_WideKeepRadiusCompletions, 1, "The wide keep-radius preset completes exactly once");
        Assert_True(_WideKeepRadiusResult == ECk_Request_OperationResult::Succeeded, "The wide keep-radius preset completes Succeeded");
        Assert_True(utils_procedural_gait::Get_Status(_Fixture.Crawlers[0].Handles.Gait) == ECk_ProceduralAnimation_Status::Ready,
            "A 500 cm keep radius leaves the walker Ready");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
