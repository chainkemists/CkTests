// Language=angelscript

class ACk_ProceduralAnimationGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FCkProceduralAnimationGym_Fixture> _Courses;
    private FVector _Origin;
    private bool _ResetPending = false;
    private bool _Run = true;
    private bool _DrawContacts = false;
    private bool _Started = false;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.ProceduralAnimation.SurfaceTraversal");
        Station.Title = FText::FromString("PROCEDURAL SURFACE TRAVERSAL");
        Station.Description.Add(FText::FromString("4 / 6 / 8 legs on uneven ground, a wall and a closed loop."));
        Station.Description.Add(FText::FromString("Authored routes steer real surface motion. Planted feet and joint poses are solved by CkFoundation."));
        Station.AutoSize = true;
        Stations.Add(Station);
        return Stations;
    }

    void Request_StartGym() override
    {
        _Origin = Get_StationAnchorLocation("Gym.ProceduralAnimation.SurfaceTraversal",
            ECk_GymStation_Anchor::FootprintCenter) + FVector(-3500.0, 0.0, 200.0);
        _Started = true;
        Request_Reset();
    }

    void Request_Reset()
    {
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Request_Destroy();
        }
        _ResetPending = true;
    }

    UFUNCTION(BlueprintOverride)
    void Tick(float InDeltaSeconds)
    {
        if (_Started == false)
        {
            return;
        }
        if (_ResetPending)
        {
            for (auto Index = 0; Index < _Courses.Num(); Index++)
            {
                if (_Courses[Index].Get_IsDestroyed() == false)
                {
                    return;
                }
            }
            auto SceneOwner = ck::ToEntity(this);
            if (ck::Is_NOT_Valid(SceneOwner))
            {
                return;
            }
            if (_Courses.Num() == 0)
            {
                for (auto Index = 0; Index < 3; Index++)
                {
                    _Courses.Add(FCkProceduralAnimationGym_Fixture());
                }
            }
            // Reuse the fixture objects so their material/renderer palettes survive reset.
            _Courses[0].Create(SceneOwner, _Origin + FVector(0.0, -1500.0, 0.0), ECkProceduralAnimationGym_Course::Uneven);
            _Courses[1].Create(SceneOwner, _Origin, ECkProceduralAnimationGym_Course::RampWall);
            _Courses[2].Create(SceneOwner, _Origin + FVector(0.0, 2000.0, 0.0), ECkProceduralAnimationGym_Course::Ring);
            _ResetPending = false;
            Request_Frame(-1);
        }
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Update(_Run, _DrawContacts);
        }
        utils_debug_draw::DrawDebugString(_Origin + FVector(-1200.0, -1500.0, 280.0),
            "UNEVEN GROUND", FLinearColor::White, 0.0f);
        utils_debug_draw::DrawDebugString(_Origin + FVector(-1200.0, 0.0, 280.0),
            "RAMP -> WALL", FLinearColor::White, 0.0f);
        utils_debug_draw::DrawDebugString(_Origin + FVector(0.0, 2000.0, 2000.0),
            "FLOOR -> WALL -> CEILING", FLinearColor::White, 0.0f);
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("PROCEDURAL ANIMATION"));
        Rows.Add(CkGym_Control::Status("This shows", "Nine crawlers traverse uneven ground, a ramp and wall, and a closed loop with live contacts and articulated limbs."));
        Rows.Add(CkGym_Control::Status("Verdict", Get_Verdict(), _ResetPending));
        Rows.Add(CkGym_Control::Status("Uneven", Get_CourseVerdict(0)));
        Rows.Add(CkGym_Control::Status("Ramp / wall", Get_CourseVerdict(1)));
        Rows.Add(CkGym_Control::Status("Closed loop", Get_CourseVerdict(2)));
        Rows.Add(CkGym_Control::Toggle(EKeys::P, "P", "Travel", _Run));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset all courses"));
        Rows.Add(CkGym_Control::Toggle(EKeys::V, "V", "Contact diagnostics", _DrawContacts));
        Rows.Add(CkGym_Control::Action(EKeys::Home, "Home", "Overview"));
        Rows.Add(CkGym_Control::Action(EKeys::One, "1", "View uneven ground"));
        Rows.Add(CkGym_Control::Action(EKeys::Two, "2", "View ramp / wall"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", "View closed loop"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        if (InRowIndex == 6)
        {
            _Run = !_Run;
        }
        else if (InRowIndex == 7)
        {
            Request_Reset();
        }
        else if (InRowIndex == 8)
        {
            _DrawContacts = !_DrawContacts;
        }
        else if (InRowIndex == 9)
        {
            Request_Frame(-1);
        }
        else if (InRowIndex >= 10 && InRowIndex <= 12)
        {
            Request_Frame(InRowIndex - 10);
        }
    }

    UFUNCTION(Exec)
    void Ck_ProceduralAnimation_Control(int32 InRowIndex)
    {
        if (InRowIndex >= 6 && InRowIndex <= 12)
        {
            Request_ControlActivated(InRowIndex);
        }
    }

    FString Get_CourseVerdict(int32 InIndex)
    {
        if (_ResetPending || _Courses.IsValidIndex(InIndex) == false)
        {
            return "Pending: resetting owned scene";
        }
        return _Courses[InIndex].Get_Verdict();
    }

    FString Get_Verdict()
    {
        if (_ResetPending || _Courses.Num() != 3)
        {
            return "Pending: resetting owned scenes";
        }
        auto Completed = 0;
        for (auto CourseIndex = 0; CourseIndex < _Courses.Num(); CourseIndex++)
        {
            if (_Courses[CourseIndex].RenderFailed)
            {
                return "FAILED: solid renderer or master material unavailable";
            }
            for (auto Crawler : _Courses[CourseIndex].Crawlers)
            {
                if (Crawler.InvalidOutput)
                {
                    return "FAILED: invalid output; inspect contact diagnostics";
                }
                if (Crawler.Get_HasCompletedCourse())
                {
                    Completed++;
                }
            }
        }
        return Completed == 9 ? "Observed: all nine crawler courses completed" :
            f"Pending: crawler courses {Completed}/9";
    }

    void Request_Frame(int32 InCourse)
    {
        auto Pawn = GetControlledPawn();
        if (ck::Is_NOT_Valid(Pawn))
        {
            return;
        }
        auto Target = _Origin + FVector(0.0, 250.0, 650.0);
        auto Eye = _Origin + FVector(-4300.0, -5400.0, 4400.0);
        if (_Courses.IsValidIndex(InCourse))
        {
            Target = _Courses[InCourse].Origin + FVector(0.0, 0.0, InCourse == 0 ? 80.0 : 800.0);
            Eye = Target + FVector(-2100.0, -2400.0, 1400.0);
            if (InCourse == 2)
            {
                Eye = Target + FVector(-600.0, -3100.0, 650.0);
            }
        }
        Pawn.SetActorLocation(Eye);
        SetControlRotation(FRotator::MakeFromX(Target - Eye));
    }

    UFUNCTION(Exec)
    void Ck_ProceduralAnimation_Record()
    {
        ck::Trace(f"[PROCEDURAL-GYM] {Get_Verdict()}");
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            for (auto Crawler : _Courses[Index].Crawlers)
            {
                ck::Trace(f"[PROCEDURAL-GYM] course={Index} legs={Crawler.LegCount} displacement={Crawler.FurthestDistance :.1} replanted={Crawler.Get_ReplantedCount()} wall={Crawler.SawWall} ceiling={Crawler.SawCeiling} traversals={Crawler.Traversals}");
            }
        }
    }

    UFUNCTION(BlueprintOverride)
    void EndPlay(EEndPlayReason InReason)
    {
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Request_Destroy();
        }
    }
}
