// Language=angelscript

// Side and top-down HighResShot captures of the hump walkers and side captures of the uneven-course crawlers for
// docs/campaigns/procedural-animation/viz. A [PAVIZ-SHOT] line precedes each capture, so the files HighResShot adds to
// Saved/Screenshots map to shots by creation order. Needs a real RHI (--no-nullrhi); under -nullrhi it still passes and
// the captures are black.
class UCk_AutoTest_PaViz_Visual : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 75.0f;
    default _AutoStageOriginField = false;
    private TArray<FCkProceduralAnimationGym_Fixture> _Fixtures;
    private TArray<FVector> _Origins;
    private float _SideDistance = 450.0;
    private float _SideHeight = 80.0;
    // Uneven lanes are 280 cm apart, so the centre crawler is shot over its neighbour from higher up.
    private float _UnevenSideHeight = 220.0;
    private float _TopDownHeight = 600.0;
    // The camera narrows its field of view until the walker fills this share of the frame height. HighResShot captures
    // 16:9, so the horizontal field of view the camera takes is widened from the vertical one by that aspect.
    private float _FrameHeightFraction = 0.4;
    private float _CaptureAspect = 16.0 / 9.0;
    // Walker height from its clearance: the body and the knees arching above the hips add about 80 % on top.
    private float _WalkerHeightPerClearance = 1.8;
    private float _OriginalFieldOfView = -1.0;
    // The step tick polls twice per engine frame. The camera holds on its walker for a few frames before and after
    // each capture: the move must reach a rendered frame before HighResShot is issued, and the capture lands later.
    private int32 _SettlePolls = 6;
    private int32 _CooldownPolls = 8;
    private float _PhaseStart = 0.0;
    private TArray<int32> _PlanFixture;
    private TArray<int32> _PlanWalker;
    private TArray<FString> _PlanPhase;
    private TArray<float> _PlanX;
    private TArray<int32> _PlanStage;
    private TArray<bool> _PlanTopDown;
    private TArray<bool> _PlanTaken;
    private int32 _Taken = 0;
    private int32 _Tracked = -1;
    private bool _Armed = false;
    private int32 _PollsInState = 0;
    private FString _Open = "{";
    private FString _Close = "}";

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    FVector Get_RootLocal(int32 InFixture, int32 InWalker) const
    {
        return utils_transform::Get_EntityCurrentLocation(_Fixtures[InFixture].Crawlers[InWalker].Handles.Root) - _Origins[InFixture];
    }

    FString Get_WalkerName(const FCkProceduralAnimationGym_Crawler& InCrawler) const
    {
        auto SpeciesName = ck_procedural_gym::Get_SpeciesName(InCrawler.Layout.Species);
        return SpeciesName == "Crawler" ? f"Crawler{InCrawler.Layout.LegCount}" : SpeciesName;
    }

    private void DoAddShot(int32 InFixture, int32 InWalker, FString InPhase, float InX, int32 InStage, bool InTopDown)
    {
        _PlanFixture.Add(InFixture);
        _PlanWalker.Add(InWalker);
        _PlanPhase.Add(InPhase);
        _PlanX.Add(InX);
        _PlanStage.Add(InStage);
        _PlanTopDown.Add(InTopDown);
        _PlanTaken.Add(false);
    }

    private bool DoAddFixture(FCk_Handle InOwner, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin,
        ECkProceduralAnimationGym_Species InFirst, ECkProceduralAnimationGym_Species InSecond, ECkProceduralAnimationGym_Species InThird)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(InFirst);
        Roster.Add(InSecond);
        Roster.Add(InThird);
        _Origins.Add(InOrigin);
        _Fixtures.Add(FCkProceduralAnimationGym_Fixture());
        return _Fixtures[_Fixtures.Num() - 1].Create_WithRoster(InOwner, InOrigin, InCourse, Roster, true);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = DoAddFixture(InHandle, ECkProceduralAnimationGym_Course::Hump, FVector(120000.0, 130000.0, 600.0),
            ECkProceduralAnimationGym_Species::Tentacled, ECkProceduralAnimationGym_Species::Spider, ECkProceduralAnimationGym_Species::Beast);
        Created = DoAddFixture(InHandle, ECkProceduralAnimationGym_Course::Uneven, FVector(120000.0, 150000.0, 600.0),
            ECkProceduralAnimationGym_Species::Crawler4, ECkProceduralAnimationGym_Species::Crawler6, ECkProceduralAnimationGym_Species::Crawler8) && Created;
        if (Created == false)
        {
            FinishFailure("The isolated rendered hump and uneven fixtures could not be created");
            return;
        }

        // Hump side shots run on the outbound crossing (the hump spans x -700..700, steepest at +-350, crest at 0); the
        // top-down shots on the return. The uneven crawlers are shot on the first ridge (x -300, 65 cm up).
        auto SidePhases = TArray<FString>();
        SidePhases.Add("approach");
        SidePhases.Add("climbing");
        SidePhases.Add("crest");
        SidePhases.Add("descending");
        auto SideX = TArray<float>();
        SideX.Add(-900.0);
        SideX.Add(-350.0);
        SideX.Add(0.0);
        SideX.Add(350.0);
        for (auto PhaseIndex = 0; PhaseIndex < SidePhases.Num(); PhaseIndex++)
        {
            for (auto Walker = 0; Walker < 3; Walker++)
            {
                DoAddShot(0, Walker, SidePhases[PhaseIndex], SideX[PhaseIndex], 0, false);
            }
        }
        for (auto Walker = 0; Walker < 3; Walker++)
        {
            DoAddShot(1, Walker, "ridge", -300.0, 0, false);
        }
        for (auto Walker = 0; Walker < 3; Walker++)
        {
            DoAddShot(0, Walker, "topdown-slope", 350.0, 1, true);
        }
        for (auto Walker = 0; Walker < 3; Walker++)
        {
            DoAddShot(0, Walker, "topdown-crest", 0.0, 1, true);
        }

        // HighResShot rewrites these three and does not always put them back; snapshot them so the base does.
        Snapshot_CVarForTest(n"r.ForceLOD");
        Snapshot_CVarForTest(n"r.SceneColorFormat");
        Snapshot_CVarForTest(n"r.PostProcessingColorFormat");
        // The AutoTests level has no lighting. `viewmode` is a command, not a variable, so Step_Finish puts it back by hand,
        // as it does the camera's field of view.
        System::ExecuteConsoleCommand("viewmode unlit");

        Add_Step_WaitUntil("the hump and uneven walkers are composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("every planned capture is taken or 50 s pass", n"Check_Captured", 0, 55.0f);
        Add_Step("restore the lit view mode and retire the fixtures", n"Step_Finish");
        Add_Step_WaitUntil("the fixtures are gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Update(true, true);
            auto CompositionError = _Fixtures[Index].CompositionError;
            if (CompositionError.IsEmpty() == false)
            {
                FinishFailure(f"A walker could not be composed: {CompositionError}");
                return;
            }
            Ready = Ready && _Fixtures[Index].Get_AllReady();
        }
        if (Ready)
        {
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Captured(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Update(true, true);
        }
        _PollsInState++;
        if (_Tracked >= 0)
        {
            DoPlaceCamera(_Tracked);
        }
        if (_Armed)
        {
            if (_PollsInState >= _SettlePolls)
            {
                System::ExecuteConsoleCommand("HighResShot 1280x720");
                _PlanTaken[_Tracked] = true;
                _Taken++;
                _Armed = false;
                _PollsInState = 0;
            }
        }
        else if (_Tracked >= 0)
        {
            if (_PollsInState >= _CooldownPolls)
            {
                _Tracked = -1;
                _PollsInState = 0;
            }
        }
        else
        {
            auto Next = Get_DueShot();
            if (Next >= 0)
            {
                DoArm(Next);
            }
        }
        auto Result = OutResult;
        Result.Set((_Taken == _PlanTaken.Num() && _Tracked < 0) || Get_Elapsed() >= 50.0);
    }

    int32 Get_DueShot() const
    {
        for (auto Index = 0; Index < _PlanTaken.Num(); Index++)
        {
            if (_PlanTaken[Index])
            {
                continue;
            }
            auto FixtureIndex = _PlanFixture[Index];
            auto Walker = _PlanWalker[Index];
            if (_Fixtures[FixtureIndex].Crawlers[Walker].Progress.RouteStage != _PlanStage[Index])
            {
                continue;
            }
            auto X = Get_RootLocal(FixtureIndex, Walker).X;
            auto Due = _PlanStage[Index] == 0 ? X >= _PlanX[Index] : X <= _PlanX[Index];
            if (Due)
            {
                return Index;
            }
        }
        return -1;
    }

    // Side shots frame the walker's height; top-down shots frame its length along the course.
    float Get_FieldOfView(int32 InShot, float InEyeDistance) const
    {
        auto Crawler = _Fixtures[_PlanFixture[InShot]].Crawlers[_PlanWalker[InShot]];
        auto Profile = ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species);
        auto Extent = _PlanTopDown[InShot] ? 2.0 * (Profile.BodyHalfExtents.X + Profile.Clearance) :
            Profile.Clearance * _WalkerHeightPerClearance;
        auto HalfVertical = Math::Atan(Extent / (2.0 * _FrameHeightFraction * InEyeDistance));
        return Math::RadiansToDegrees(2.0 * Math::Atan(Math::Tan(HalfVertical) * _CaptureAspect));
    }

    private void DoArm(int32 InShot)
    {
        _Tracked = InShot;
        _Armed = true;
        _PollsInState = 0;
        auto EyeDistance = DoPlaceCamera(InShot);
        auto FieldOfView = Get_FieldOfView(InShot, EyeDistance);
        DoSet_FieldOfView(FieldOfView);
        auto FixtureIndex = _PlanFixture[InShot];
        auto Walker = _PlanWalker[InShot];
        auto Crawler = _Fixtures[FixtureIndex].Crawlers[Walker];
        auto WalkerName = Get_WalkerName(Crawler);
        auto Course = ck_procedural_gym::Get_CourseIdentifier(Crawler.Layout.Course);
        auto Phase = _PlanPhase[InShot];
        auto Local = Get_RootLocal(FixtureIndex, Walker);
        auto Elapsed = Get_Elapsed();
        FString View = _PlanTopDown[InShot] ? "top" : "side";
        ck::Trace(f"[PAVIZ-SHOT] {_Open}\"index\":{_Taken},\"plan\":{InShot},\"course\":\"{Course}\",\"species\":\"{WalkerName}\",\"walker\":{Walker},\"phase\":\"{Phase}\",\"view\":\"{View}\",\"x\":{Local.X :.1},\"z\":{Local.Z :.1},\"t\":{Elapsed :.3},\"fov\":{FieldOfView :.1}{_Close}",
            n"PAVIZ.Shot", 0.0f);
    }

    // The AutoTests pawn has no camera component, so the camera manager's default field of view is the one it renders with.
    private void DoSet_FieldOfView(float InFieldOfView)
    {
        auto Controller = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(Controller) || ck::Is_NOT_Valid(Controller.PlayerCameraManager))
        {
            return;
        }
        if (_OriginalFieldOfView < 0.0)
        {
            _OriginalFieldOfView = Controller.PlayerCameraManager.DefaultFOV;
        }
        Controller.PlayerCameraManager.DefaultFOV = InFieldOfView;
    }

    // Returns the eye's distance from the walker.
    private float DoPlaceCamera(int32 InShot)
    {
        auto Pawn = Gameplay::GetPlayerPawn(0);
        auto Controller = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(Pawn) || ck::Is_NOT_Valid(Controller))
        {
            return _SideDistance;
        }
        auto Crawler = _Fixtures[_PlanFixture[InShot]].Crawlers[_PlanWalker[InShot]];
        auto Target = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root);
        // Outer lanes are shot from their own outer side; the centre walker from +Y, looking over the third lane.
        auto Side = Crawler.Layout.LaneY < 0.0 ? -1.0 : 1.0;
        auto Eye = _PlanTopDown[InShot] ? Target + FVector(-1.0, 0.0, _TopDownHeight) :
            Target + FVector(0.0, Side * _SideDistance, _PlanFixture[InShot] == 1 ? _UnevenSideHeight : _SideHeight);
        Pawn.SetActorLocation(Eye);
        Controller.SetControlRotation(FRotator::MakeFromX(Target - Eye));
        return (Target - Eye).Size();
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        System::ExecuteConsoleCommand("viewmode lit");
        if (_OriginalFieldOfView > 0.0)
        {
            DoSet_FieldOfView(_OriginalFieldOfView);
        }
        auto Planned = _PlanTaken.Num();
        auto Elapsed = Get_Elapsed();
        ck::Trace(f"[PAVIZ-SHOT-END] {_Taken} of {Planned} captures taken after {Elapsed :.2} s");
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
