// Language=angelscript

// The capture sequence the PaViz visual autotests share. A planned shot is armed once its walker reaches its trigger; the
// camera then holds on that walker for a few polls and HighResShot captures. A [PAVIZ-SHOT] line precedes each capture, so
// the files HighResShot adds to Saved/Screenshots map to shots by creation order. Needs a real RHI (--no-nullrhi); under
// -nullrhi the captures are black.
struct FCkPaViz_ShotPlan
{
    UPROPERTY()
    TArray<FCkProceduralAnimationGym_Fixture> Fixtures;
    UPROPERTY()
    TArray<FVector> Origins;
    UPROPERTY()
    FString CompositionError;

    float SideDistance = 450.0;
    // The camera narrows its field of view until the walker fills this share of the frame height. HighResShot captures
    // 16:9, so the horizontal field of view the camera takes is widened from the vertical one by that aspect.
    float FrameHeightFraction = 0.4;
    float CaptureAspect = 16.0 / 9.0;
    // Walker height from its clearance: the body and the knees arching above the hips add about 80 % on top.
    float WalkerHeightPerClearance = 1.8;
    float OriginalFieldOfView = -1.0;
    // The step tick polls twice per engine frame. The camera holds on its walker for a few frames before and after each
    // capture: the move must reach a rendered frame before HighResShot is issued, and the capture lands later.
    int32 SettlePolls = 6;
    int32 CooldownPolls = 8;
    float PhaseStart = 0.0;

    TArray<int32> PlanFixture;
    TArray<int32> PlanWalker;
    TArray<FString> PlanPhase;
    TArray<float> PlanX;
    TArray<float> PlanMaxX;
    TArray<int32> PlanStage;
    TArray<bool> PlanTopDown;
    TArray<float> PlanEyeHeight;
    TArray<float> PlanMinZ;
    TArray<float> PlanMaxZ;
    TArray<float> PlanMinSeconds;
    TArray<bool> PlanTaken;
    int32 Taken = 0;
    int32 Tracked = -1;
    bool Armed = false;
    int32 PollsInState = 0;

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - PhaseStart;
    }

    FVector Get_RootLocal(int32 InFixture, int32 InWalker) const
    {
        return utils_transform::Get_EntityCurrentLocation(Fixtures[InFixture].Crawlers[InWalker].Handles.Root) - Origins[InFixture];
    }

    FString Get_WalkerName(const FCkProceduralAnimationGym_Crawler& InCrawler) const
    {
        auto SpeciesName = ck_procedural_gym::Get_SpeciesName(InCrawler.Layout.Species);
        return SpeciesName == "Crawler" ? f"Crawler{InCrawler.Layout.LegCount}" : SpeciesName;
    }

    bool Add_Fixture(FCk_Handle InOwner, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin,
        TArray<ECkProceduralAnimationGym_Species> InRoster)
    {
        Origins.Add(InOrigin);
        Fixtures.Add(FCkProceduralAnimationGym_Fixture());
        return Fixtures[Fixtures.Num() - 1].Create_WithRoster(InOwner, InOrigin, InCourse, InRoster, true);
    }

    // A shot is due once its walker is on InStage and past InX (beyond it on the return), at least InMinZ up and at least
    // InMinSeconds into the run, between InMinZ and InMaxZ, and no farther than InMaxX.
    void Add_Shot(int32 InFixture, int32 InWalker, FString InPhase, float InX, int32 InStage, bool InTopDown,
        float InEyeHeight, float InMinZ = -100000.0, float InMinSeconds = 0.0, float InMaxZ = 100000.0, float InMaxX = 100000.0)
    {
        PlanFixture.Add(InFixture);
        PlanWalker.Add(InWalker);
        PlanPhase.Add(InPhase);
        PlanX.Add(InX);
        PlanMaxX.Add(InMaxX);
        PlanStage.Add(InStage);
        PlanTopDown.Add(InTopDown);
        PlanEyeHeight.Add(InEyeHeight);
        PlanMinZ.Add(InMinZ);
        PlanMaxZ.Add(InMaxZ);
        PlanMinSeconds.Add(InMinSeconds);
        PlanTaken.Add(false);
    }

    // Updates every fixture and reports whether every walker is composed and evaluated; a composition error is left in
    // CompositionError. The clock starts on the ready poll.
    bool Update_Ready()
    {
        auto Ready = true;
        for (auto Index = 0; Index < Fixtures.Num(); Index++)
        {
            Fixtures[Index].Update(true, true);
            if (Fixtures[Index].CompositionError.IsEmpty() == false)
            {
                CompositionError = Fixtures[Index].CompositionError;
                return false;
            }
            Ready = Ready && Fixtures[Index].Get_AllReady();
        }
        if (Ready)
        {
            PhaseStart = float(System::GetGameTimeInSeconds());
        }
        return Ready;
    }

    // Updates every fixture and advances the capture sequence; true once every planned shot is taken or InMaxSeconds pass.
    bool Update_Captured(float InMaxSeconds)
    {
        for (auto Index = 0; Index < Fixtures.Num(); Index++)
        {
            Fixtures[Index].Update(true, true);
        }
        PollsInState++;
        if (Tracked >= 0)
        {
            DoPlaceCamera(Tracked);
        }
        if (Armed)
        {
            if (PollsInState >= SettlePolls)
            {
                System::ExecuteConsoleCommand("HighResShot 1280x720");
                PlanTaken[Tracked] = true;
                Taken++;
                Armed = false;
                PollsInState = 0;
            }
        }
        else if (Tracked >= 0)
        {
            if (PollsInState >= CooldownPolls)
            {
                Tracked = -1;
                PollsInState = 0;
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
        return (Taken == PlanTaken.Num() && Tracked < 0) || Get_Elapsed() >= InMaxSeconds;
    }

    int32 Get_DueShot() const
    {
        for (auto Index = 0; Index < PlanTaken.Num(); Index++)
        {
            if (PlanTaken[Index])
            {
                continue;
            }
            auto FixtureIndex = PlanFixture[Index];
            auto Walker = PlanWalker[Index];
            if (Fixtures[FixtureIndex].Crawlers[Walker].Progress.RouteStage != PlanStage[Index])
            {
                continue;
            }
            auto Local = Get_RootLocal(FixtureIndex, Walker);
            auto PastX = PlanStage[Index] == 0 ? Local.X >= PlanX[Index] : Local.X <= PlanX[Index];
            if (PastX && Local.X <= PlanMaxX[Index] && Local.Z >= PlanMinZ[Index] && Local.Z <= PlanMaxZ[Index] &&
                Get_Elapsed() >= PlanMinSeconds[Index])
            {
                return Index;
            }
        }
        return -1;
    }

    // Side shots frame the walker's height; top-down shots frame its length along the course.
    float Get_FieldOfView(int32 InShot, float InEyeDistance) const
    {
        auto Crawler = Fixtures[PlanFixture[InShot]].Crawlers[PlanWalker[InShot]];
        auto Profile = ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species);
        auto Extent = PlanTopDown[InShot] ? 2.0 * (Profile.BodyHalfExtents.X + Profile.Clearance) :
            Profile.Clearance * WalkerHeightPerClearance;
        auto HalfVertical = Math::Atan(Extent / (2.0 * FrameHeightFraction * InEyeDistance));
        return Math::RadiansToDegrees(2.0 * Math::Atan(Math::Tan(HalfVertical) * CaptureAspect));
    }

    void DoArm(int32 InShot)
    {
        Tracked = InShot;
        Armed = true;
        PollsInState = 0;
        auto EyeDistance = DoPlaceCamera(InShot);
        auto FieldOfView = Get_FieldOfView(InShot, EyeDistance);
        DoSet_FieldOfView(FieldOfView);
        auto FixtureIndex = PlanFixture[InShot];
        auto Walker = PlanWalker[InShot];
        auto Crawler = Fixtures[FixtureIndex].Crawlers[Walker];
        auto WalkerName = Get_WalkerName(Crawler);
        auto Course = ck_procedural_gym::Get_CourseIdentifier(Crawler.Layout.Course);
        auto Phase = PlanPhase[InShot];
        auto Local = Get_RootLocal(FixtureIndex, Walker);
        auto Elapsed = Get_Elapsed();
        FString View = PlanTopDown[InShot] ? "top" : "side";
        FString Open = "{";
        FString Close = "}";
        ck::Trace(f"[PAVIZ-SHOT] {Open}\"index\":{Taken},\"plan\":{InShot},\"course\":\"{Course}\",\"species\":\"{WalkerName}\",\"walker\":{Walker},\"phase\":\"{Phase}\",\"view\":\"{View}\",\"x\":{Local.X :.1},\"z\":{Local.Z :.1},\"t\":{Elapsed :.3},\"fov\":{FieldOfView :.1}{Close}",
            n"PAVIZ.Shot", 0.0f);
    }

    // The AutoTests pawn has no camera component, so the camera manager's default field of view is the one it renders with.
    void DoSet_FieldOfView(float InFieldOfView)
    {
        auto Controller = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(Controller) || ck::Is_NOT_Valid(Controller.PlayerCameraManager))
        {
            return;
        }
        if (OriginalFieldOfView < 0.0)
        {
            OriginalFieldOfView = Controller.PlayerCameraManager.DefaultFOV;
        }
        Controller.PlayerCameraManager.DefaultFOV = InFieldOfView;
    }

    // Returns the eye's distance from the walker.
    float DoPlaceCamera(int32 InShot)
    {
        auto Pawn = Gameplay::GetPlayerPawn(0);
        auto Controller = Gameplay::GetPlayerController(0);
        if (ck::Is_NOT_Valid(Pawn) || ck::Is_NOT_Valid(Controller))
        {
            return SideDistance;
        }
        auto Crawler = Fixtures[PlanFixture[InShot]].Crawlers[PlanWalker[InShot]];
        auto Target = utils_transform::Get_EntityCurrentLocation(Crawler.Handles.Root);
        auto Eye = Target + FVector(-1.0, 0.0, PlanEyeHeight[InShot]);
        if (PlanTopDown[InShot] == false)
        {
            // Outer lanes are shot from their own outer side, except on the cylinder: the side camera follows the
            // walker's radial face so the solid cannot hide it as it circles to the opposite side.
            auto Side = Crawler.Layout.LaneY < 0.0 ? -1.0 : 1.0;
            auto Outward = FVector(0.0, Side, 0.0);
            if (Crawler.Layout.Course == ECkProceduralAnimationGym_Course::Cylinder)
            {
                auto Axis = Crawler.Layout.Origin + FVector(0.0, Crawler.Layout.LaneY, 0.0);
                auto Radial = Target - Axis;
                Radial.Z = 0.0;
                Outward = Radial.GetSafeNormal();
            }
            Eye = Target + Outward * SideDistance + FVector::UpVector * PlanEyeHeight[InShot];
        }
        Pawn.SetActorLocation(Eye);
        Controller.SetControlRotation(FRotator::MakeFromX(Target - Eye));
        return (Target - Eye).Size();
    }

    // Restores the camera's field of view, traces the summary and retires every fixture.
    void Finish()
    {
        if (OriginalFieldOfView > 0.0)
        {
            DoSet_FieldOfView(OriginalFieldOfView);
        }
        auto Planned = PlanTaken.Num();
        auto Elapsed = Get_Elapsed();
        ck::Trace(f"[PAVIZ-SHOT-END] {Taken} of {Planned} captures taken after {Elapsed :.2} s");
        for (auto Index = 0; Index < Fixtures.Num(); Index++)
        {
            Fixtures[Index].Request_Destroy();
        }
    }

    bool Get_IsDestroyed() const
    {
        for (auto Index = 0; Index < Fixtures.Num(); Index++)
        {
            if (Fixtures[Index].Get_IsDestroyed() == false)
            {
                return false;
            }
        }
        return true;
    }
}
