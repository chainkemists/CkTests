// Language=angelscript

// Short, unchanged course approaches capture target admission and scheduling before choosing a regression policy.
class UCk_AutoTest_ProceduralAnimation_IntactApproachDiagnostics : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 40.0f;
    default _AutoStageOriginField = false;

    private TArray<FCkProceduralAnimationGym_Fixture> _Fixtures;
    private TArray<float> _LastCapture;
    private TArray<int32> _Samples;
    private float _StartTime = -1.0;
    private bool _CylinderWasGuessed = false;
    private int32 _CylinderGuessedSamples = 0;
    private int32 _CompressedFrontSamples = 0;

    bool CreateFixture(FCk_Handle InOwner, ECkProceduralAnimationGym_Course InCourse,
        ECkProceduralAnimationGym_Species InSpecies, FVector InOrigin)
    {
        auto Fixture = FCkProceduralAnimationGym_Fixture();
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(InSpecies);
        if (Fixture.Create_WithRoster(InOwner, InOrigin, InCourse, Roster, false) == false)
        {
            return false;
        }
        _Fixtures.Add(Fixture);
        _LastCapture.Add(-1.0);
        _Samples.Add(0);
        return true;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        if (CreateFixture(InHandle, ECkProceduralAnimationGym_Course::StepField,
            ECkProceduralAnimationGym_Species::Spider, FVector(120000.0, 460000.0, 600.0)) == false ||
            CreateFixture(InHandle, ECkProceduralAnimationGym_Course::Ledge,
            ECkProceduralAnimationGym_Species::Spider, FVector(120000.0, 465000.0, 600.0)) == false ||
            CreateFixture(InHandle, ECkProceduralAnimationGym_Course::Cylinder,
            ECkProceduralAnimationGym_Species::Spider, FVector(120000.0, 470000.0, 600.0)) == false ||
            CreateFixture(InHandle, ECkProceduralAnimationGym_Course::RampWall,
            ECkProceduralAnimationGym_Species::Crawler4, FVector(120000.0, 475000.0, 600.0)) == false ||
            CreateFixture(InHandle, ECkProceduralAnimationGym_Course::RampWall,
            ECkProceduralAnimationGym_Species::Crawler6, FVector(120000.0, 480000.0, 600.0)) == false ||
            CreateFixture(InHandle, ECkProceduralAnimationGym_Course::RampWall,
            ECkProceduralAnimationGym_Species::Crawler8, FVector(120000.0, 485000.0, 600.0)) == false)
        {
            FinishFailure("The isolated intact approach fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("capture intact approaches through the ramp crest", n"Check_Approaches", 0, 25.0f);
        Add_Step("verify diagnostic coverage", n"Step_Check");
        Add_Step("retire the approach fixtures", n"Step_Destroy");
        Add_Step_WaitUntil("fixture lifetime subtrees are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    void Capture(int32 InIndex, float InElapsed)
    {
        auto Crawler = _Fixtures[InIndex].Crawlers[0];
        auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
        auto Local = Body.GetLocation() - Crawler.Layout.Origin;
        auto Guessed = false;
        for (auto Leg : Crawler.Handles.Legs)
        {
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
                Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Guessed)
            {
                Guessed = true;
            }
        }
        auto Onset = InIndex == 2 && Guessed && _CylinderWasGuessed == false;
        if (InIndex == 2)
        {
            _CylinderWasGuessed = Guessed;
            if (Guessed)
            {
                _CylinderGuessedSamples++;
            }
        }
        // Public-state onset detection is every frame; formatting is bounded to one capture per .2 seconds otherwise.
        if (Onset == false && _LastCapture[InIndex] >= 0.0 && InElapsed - _LastCapture[InIndex] < 0.2)
        {
            return;
        }
        _LastCapture[InIndex] = InElapsed;
        _Samples[InIndex]++;
        for (auto Leg : Crawler.Handles.Legs)
        {
            auto Id = utils_procedural_leg::Get_Id(Leg);
            if (InIndex < 2 && Id != n"Leg0" && Id != n"Leg1" && Id != n"Leg6" && Id != n"Leg7")
            {
                continue;
            }
            auto Placement = utils_procedural_leg::Get_Placement(Leg);
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto FootLocal = Body.InverseTransformPosition(Foot.Get_Position());
            auto Behind = Placement.Get_HipLocal().X - FootLocal.X;
            if (InIndex < 2 && (Id == n"Leg0" || Id == n"Leg7") &&
                Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted &&
                Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted && Behind > 0.0)
            {
                _CompressedFrontSamples++;
            }
            auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                Crawler.Handles.Root, Id, Crawler.Layout.Origin);
            ck::Trace(f"[INTACT-APPROACH] course {InIndex} t {InElapsed :.3} body ({Local.X :.3},{Local.Y :.3},{Local.Z :.3}) behind {Behind :.3} guessed {Guessed} onset {Onset} {Snapshot}");
        }
    }

    UFUNCTION()
    private void Check_Approaches(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Update();
            if (_Fixtures[Index].CompositionError.IsEmpty() == false)
            {
                FinishFailure(_Fixtures[Index].CompositionError);
                return;
            }
            Ready = Ready && _Fixtures[Index].Get_AllReady();
        }
        if (Ready == false)
        {
            return;
        }
        auto Now = float(System::GetGameTimeInSeconds());
        if (_StartTime < 0.0)
        {
            _StartTime = Now;
        }
        auto Elapsed = Now - _StartTime;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            Capture(Index, Elapsed);
        }
        auto Result = OutResult;
        Result.Set(Elapsed >= 18.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            auto Crawler = _Fixtures[Index].Crawlers[0];
            Assert_True(_Samples[Index] > 20 && Crawler.Evidence.InvalidOutput == false,
                f"Course {Index} produced finite ready diagnostic samples ({_Samples[Index]})");
            auto Enabled = 0;
            for (auto Leg : Crawler.Handles.Legs)
            {
                if (utils_procedural_leg::Get_EnableDisable(Leg) == ECk_EnableDisable::Enable)
                {
                    Enabled++;
                }
            }
            Assert_True(Enabled == Crawler.Layout.LegCount,
                f"Course {Index} retained every authored leg ({Enabled}/{Crawler.Layout.LegCount})");
        }
        ck::Trace(f"[INTACT-APPROACH] coverage compressed front samples {_CompressedFrontSamples}, cylinder guessed frames {_CylinderGuessedSamples}");
    }

    UFUNCTION()
    private void Step_Destroy(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Request_Destroy();
        }
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Destroyed = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            Destroyed = Destroyed && _Fixtures[Index].Get_IsDestroyed();
        }
        auto Result = OutResult;
        Result.Set(Destroyed);
    }
}
