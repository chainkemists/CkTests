// Language=angelscript

// Two unchanged route traversals per intact Spider; low-progress windows retain diagnostic evidence without imposing a pause policy.
class UCk_AutoTest_ProceduralAnimation_SpiderCourseTraversal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 100.0f;
    default _AutoStageOriginField = false;

    private TArray<FCkProceduralAnimationGym_Fixture> _Fixtures;
    private TArray<FString> _Names;
    private TArray<FVector> _WindowPosition;
    private TArray<float> _WindowStart;
    private TArray<int32> _WindowStage;
    private TArray<int32> _WindowTraversals;
    private TArray<bool> _CandidateStall;
    private TArray<int32> _Samples;
    private float _StartTime = -1.0;
    private float _LastSummary = -5.0;

    bool AddFixture(FCk_Handle InOwner, FString InName, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin)
    {
        auto Fixture = FCkProceduralAnimationGym_Fixture();
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Spider);
        if (Fixture.Create_WithRoster(InOwner, InOrigin, InCourse, Roster, false) == false)
        {
            return false;
        }
        _Fixtures.Add(Fixture);
        _Names.Add(InName);
        _WindowPosition.Add(FVector::ZeroVector);
        _WindowStart.Add(-1.0);
        _WindowStage.Add(0);
        _WindowTraversals.Add(0);
        _CandidateStall.Add(false);
        _Samples.Add(0);
        return true;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = AddFixture(InHandle, "StepField", ECkProceduralAnimationGym_Course::StepField, FVector(120000.0, 460000.0, 600.0));
        Created = AddFixture(InHandle, "Ledge", ECkProceduralAnimationGym_Course::Ledge, FVector(120000.0, 465000.0, 600.0)) && Created;
        Created = AddFixture(InHandle, "Ridge", ECkProceduralAnimationGym_Course::Ridge, FVector(120000.0, 470000.0, 600.0)) && Created;
        Created = AddFixture(InHandle, "Rubble", ECkProceduralAnimationGym_Course::Rubble, FVector(120000.0, 475000.0, 600.0)) && Created;
        Created = AddFixture(InHandle, "Beam", ECkProceduralAnimationGym_Course::Beam, FVector(120000.0, 480000.0, 600.0)) && Created;
        if (Created == false)
        {
            FinishFailure("The five isolated intact Spider fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("observe two intact Spider route traversals", n"Check_Observe", 0, 85.0f);
        Add_Step("verify two complete traversals and intact coverage", n"Step_Check");
        Add_Step("retire diagnostic fixtures", n"Step_Destroy");
        Add_Step_WaitUntil("diagnostic lifetime subtrees are gone", n"Check_Destroyed", 0, 10.0f);
        Run_Steps(InHandle);
    }

    void Dump(int32 InIndex, float InElapsed, FString InEvent)
    {
        auto Crawler = _Fixtures[InIndex].Crawlers[0];
        for (auto Leg : Crawler.Handles.Legs)
        {
            auto Snapshot = UCk_Utils_AutoTest_UE::Get_ProceduralAnimationLegSnapshot(
                Crawler.Handles.Root, utils_procedural_leg::Get_Id(Leg), Crawler.Layout.Origin);
            ck::Trace(f"[SPIDER-STALL] course {_Names[InIndex]} t {InElapsed :.6} event {InEvent} stage {Crawler.Progress.RouteStage} traversals {Crawler.Progress.Traversals} {Snapshot}");
        }
    }

    UFUNCTION()
    private void Check_Observe(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
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
        auto Summary = Elapsed - _LastSummary >= 5.0;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            auto Crawler = _Fixtures[Index].Crawlers[0];
            auto Body = utils_transform::Get_EntityCurrentTransform(Crawler.Handles.Root);
            auto Local = Body.GetLocation() - Crawler.Layout.Origin;
            auto Stage = Crawler.Progress.RouteStage;
            auto Traversals = Crawler.Progress.Traversals;
            auto ChangedRoute = Stage != _WindowStage[Index] || Traversals != _WindowTraversals[Index];
            if (_WindowStart[Index] < 0.0 || ChangedRoute)
            {
                if (_CandidateStall[Index])
                {
                    Dump(Index, Elapsed, "route-recovered");
                    _CandidateStall[Index] = false;
                }
                _WindowStart[Index] = Elapsed;
                _WindowPosition[Index] = Local;
                _WindowStage[Index] = Stage;
                _WindowTraversals[Index] = Traversals;
            }
            if (Elapsed - _WindowStart[Index] >= 2.0)
            {
                // These five courses patrol X. Lateral jitter and vertical motion cannot hide absent longitudinal progress.
                auto SignedProgress = (Local.X - _WindowPosition[Index].X) * (Stage == 0 ? 1.0 : -1.0);
                auto Candidate = SignedProgress < 2.0;
                if (Candidate && _CandidateStall[Index] == false)
                {
                    ck::Trace(f"[SPIDER-STALL-WINDOW] course {_Names[Index]} t {Elapsed :.6} signedX {SignedProgress :.6} delta3D {(Local - _WindowPosition[Index]).Size() :.6} stage {Stage} traversals {Traversals}");
                    Dump(Index, Elapsed, "onset");
                }
                else if (Candidate == false && _CandidateStall[Index])
                {
                    Dump(Index, Elapsed, "progress-recovered");
                }
                _CandidateStall[Index] = Candidate;
                _WindowStart[Index] = Elapsed;
                _WindowPosition[Index] = Local;
            }
            _Samples[Index]++;
            if (Summary)
            {
                auto PaceScale = utils_surface_motion::Get_ReachPaceScale(Crawler.Handles.Motion);
                auto PaceState = int32(utils_surface_motion::Get_ReachPaceState(Crawler.Handles.Motion));
                auto Swinging = 0;
                auto TrustedPlants = 0;
                for (auto Leg : Crawler.Handles.Legs)
                {
                    auto Foot = utils_procedural_leg::Get_Foot(Leg);
                    if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Swinging)
                    {
                        Swinging++;
                    }
                    else if (Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted)
                    {
                        TrustedPlants++;
                    }
                }
                ck::Trace(f"[SPIDER-STALL-SUMMARY] course {_Names[Index]} t {Elapsed :.6} body ({Local.X :.6},{Local.Y :.6},{Local.Z :.6}) stage {Stage} traversals {Traversals} pace {PaceScale :.6}/{PaceState} swinging {Swinging} trustedPlants {TrustedPlants} candidate {_CandidateStall[Index]} invalid {Crawler.Evidence.InvalidOutput}");
            }
        }
        if (Summary)
        {
            _LastSummary = Elapsed;
        }
        auto Result = OutResult;
        Result.Set(Elapsed >= 60.0);
    }

    UFUNCTION()
    private void Step_Check(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            auto Crawler = _Fixtures[Index].Crawlers[0];
            Assert_True(_Samples[Index] > 100 && Crawler.Evidence.InvalidOutput == false,
                f"{_Names[Index]} produced finite intact route observations ({_Samples[Index]})");
            auto Enabled = 0;
            for (auto Leg : Crawler.Handles.Legs)
            {
                if (utils_procedural_leg::Get_EnableDisable(Leg) == ECk_EnableDisable::Enable)
                {
                    Enabled++;
                }
            }
            Assert_True(Enabled == 8, f"{_Names[Index]} retained all eight authored legs");
            auto Completed = Crawler.Progress.Traversals >= 2 && Crawler.Get_HasCompletedCourse();
            if (Completed == false)
            {
                Dump(Index, 60.0, "liveness-failure");
            }
            Assert_True(Completed,
                f"{_Names[Index]} completed two route traversals with every leg replanted ({Crawler.Progress.Traversals} traversals, {Crawler.Get_ReplantedCount()}/8 legs)");
            if (_CandidateStall[Index])
            {
                Dump(Index, 60.0, "still-candidate-at-end");
            }
        }
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