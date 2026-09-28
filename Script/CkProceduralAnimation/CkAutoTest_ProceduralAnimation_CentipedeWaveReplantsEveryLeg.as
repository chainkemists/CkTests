// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_CentipedeWaveReplantsEveryLeg : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 20.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 105000.0, 600.0);
    private float _PhaseStart = 0.0;
    private float _SteadyStart = 1.0;
    private int32 _MaxSwinging = 0;
    private int32 _SwingSamples = 0;

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, Roster, false) == false)
        {
            FinishFailure("The isolated centipede floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("the centipede is composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("every leg replants or 10 s pass", n"Check_Replanted", 0, 11.0f);
        Add_Step("verify the wave replanted every leg inside the swing budget", n"Step_Verify");
        Add_Step_WaitUntil("the fixture is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"The centipede could not be composed: {_Fixture.CompositionError}");
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
    private void Check_Replanted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        auto Crawler = _Fixture.Crawlers[0];
        if (Get_Elapsed() >= _SteadyStart)
        {
            auto Swinging = 0;
            for (auto Leg : Crawler.Handles.Legs)
            {
                if (ck::IsValid(Leg) && utils_procedural_leg::Get_Foot(Leg).Get_Phase() == ECk_ProceduralLeg_FootPhase::Swinging)
                {
                    Swinging++;
                }
            }
            _MaxSwinging = Math::Max(_MaxSwinging, Swinging);
            _SwingSamples++;
        }
        // Replanting can finish inside the start-up second, so the wave is sampled for at least one full gait cycle.
        auto CycleSeconds = Crawler.Layout.GaitPreset.Get_Timing().Get_CycleDuration().Get_Seconds();
        auto Sampled = Get_Elapsed() >= _SteadyStart + CycleSeconds;
        auto Result = OutResult;
        Result.Set((Crawler.Get_ReplantedCount() == Crawler.Layout.LegCount && Sampled) || Get_Elapsed() >= 10.0);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Crawler = _Fixture.Crawlers[0];
        auto Replanted = Crawler.Get_ReplantedCount();
        auto LegCount = Crawler.Layout.LegCount;
        auto Budget = Math::Max(1, Math::IntegerDivisionTrunc(LegCount, 2));
        auto Elapsed = Get_Elapsed();
        ck::Trace(f"[CENTIPEDE-WAVE] {Replanted}/{LegCount} replanted after {Elapsed :.2} s, max {_MaxSwinging} swinging over {_SwingSamples} samples (budget {Budget})");
        Assert_Equals_Int(LegCount, 16, "The centipede walks on sixteen legs");
        Assert_Equals_Int(Replanted, LegCount, "Every leg of the centipede swung and replanted");
        Assert_True(_MaxSwinging >= 2, f"The wave overlaps swings ({_MaxSwinging} legs swinging at once at most)");
        Assert_True(_MaxSwinging <= Budget, f"The wave stays inside the automatic swing budget ({_MaxSwinging} of {Budget})");
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
