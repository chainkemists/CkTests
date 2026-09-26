// Language=angelscript

class ACk_ProceduralAnimationGym_PlayerController : ACk_Gym_Base_PlayerController
{
    private TArray<FCkProceduralAnimationGym_Fixture> _Courses;
    private FVector _Origin;
    private bool _ResetPending = false;
    private bool _Run = true;
    private bool _DrawContacts = false;
    private bool _Started = false;
    private bool _DetachIssued = false;
    private FString _CreateError;
    private int32 _Set = 0;

    TArray<FCkGym_Station_SpawnParams_Payload> Get_RequiredStations() override
    {
        auto Stations = TArray<FCkGym_Station_SpawnParams_Payload>();
        auto Station = FCkGym_Station_SpawnParams_Payload();
        Station.Tags.Add(n"Gym.ProceduralAnimation.SurfaceTraversal");
        Station.Title = FText::FromString("PROCEDURAL SURFACE TRAVERSAL");
        Station.Description.Add(FText::FromString("4 / 6 / 8 legs on uneven ground, a wall and a closed loop."));
        Station.Description.Add(FText::FromString("Authored routes steer real surface motion. Planted feet and joint poses are solved by CkFoundation."));
        Station.Description.Add(FText::FromString("N switches to a spider, a centipede, a tentacled walker and a mixed-chain beast on stairs, rubble and a convex hump."));
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

    ECkProceduralAnimationGym_Course Get_SetCourse(int32 InSlot) const
    {
        if (_Set == 1)
        {
            return InSlot == 0 ? ECkProceduralAnimationGym_Course::Stairs :
                (InSlot == 1 ? ECkProceduralAnimationGym_Course::Rubble : ECkProceduralAnimationGym_Course::Hump);
        }
        return InSlot == 0 ? ECkProceduralAnimationGym_Course::Uneven :
            (InSlot == 1 ? ECkProceduralAnimationGym_Course::RampWall : ECkProceduralAnimationGym_Course::Ring);
    }

    TArray<ECkProceduralAnimationGym_Species> Get_SetRoster(int32 InSlot) const
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        if (_Set == 0)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler4);
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler6);
            Roster.Add(ECkProceduralAnimationGym_Species::Crawler8);
        }
        else if (InSlot == 0)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
            Roster.Add(ECkProceduralAnimationGym_Species::Spider);
            Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
        }
        else if (InSlot == 1)
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Centipede);
            Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
        }
        else
        {
            Roster.Add(ECkProceduralAnimationGym_Species::Spider);
            Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
            Roster.Add(ECkProceduralAnimationGym_Species::Beast);
        }
        return Roster;
    }

    FString Get_CourseBanner(ECkProceduralAnimationGym_Course InCourse) const
    {
        if (InCourse == ECkProceduralAnimationGym_Course::Uneven)
        {
            return "UNEVEN GROUND";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::RampWall)
        {
            return "RAMP -> WALL";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Ring)
        {
            return "FLOOR -> WALL -> CEILING";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Stairs)
        {
            return "STAIRS";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Rubble)
        {
            return "RUBBLE";
        }
        if (InCourse == ECkProceduralAnimationGym_Course::Hump)
        {
            return "CONVEX HUMP";
        }
        return "FLAT";
    }

    void Request_Reset()
    {
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Request_Destroy();
        }
        _ResetPending = true;
        _DetachIssued = false;
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
            auto Created = _Courses[0].Create_WithRoster(SceneOwner, _Origin + FVector(0.0, -1500.0, 0.0), Get_SetCourse(0), Get_SetRoster(0));
            Created = _Courses[1].Create_WithRoster(SceneOwner, _Origin, Get_SetCourse(1), Get_SetRoster(1)) && Created;
            Created = _Courses[2].Create_WithRoster(SceneOwner, _Origin + FVector(0.0, 2000.0, 0.0), Get_SetCourse(2), Get_SetRoster(2)) && Created;
            _CreateError = Created ? "" : "a course could not be created on the retired scene";
            if (Created == false)
            {
                ck::Error(f"[FAIL] Procedural animation gym: {_CreateError}");
            }
            _ResetPending = false;
            Request_Frame(-1);
        }
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Update(_Run, _DrawContacts);
        }
        BindCrawlerSignals();
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            auto Course = _Courses[Index].Spawn.Course;
            auto BannerOffset = Course == ECkProceduralAnimationGym_Course::Ring ? FVector(0.0, 0.0, 2000.0) : FVector(-1200.0, 0.0, 280.0);
            utils_debug_draw::DrawDebugString(_Courses[Index].Spawn.Origin + BannerOffset,
                Get_CourseBanner(Course), FLinearColor::White, 0.0f);
        }
    }

    void BindCrawlerSignals()
    {
        for (auto CourseIndex = 0; CourseIndex < _Courses.Num(); CourseIndex++)
        {
            for (auto CrawlerIndex = 0; CrawlerIndex < _Courses[CourseIndex].Crawlers.Num(); CrawlerIndex++)
            {
                if (_Courses[CourseIndex].Crawlers[CrawlerIndex].SignalsBound ||
                    ck::Is_NOT_Valid(_Courses[CourseIndex].Crawlers[CrawlerIndex].Handles.Gait))
                {
                    continue;
                }
                auto Gait = _Courses[CourseIndex].Crawlers[CrawlerIndex].Handles.Gait;
                utils_procedural_gait::BindTo_OnLegSetChanged(Gait,
                    FCk_Delegate_ProceduralGait_OnLegSetChanged(this, n"OnLegSetChanged"));
                for (auto Leg : _Courses[CourseIndex].Crawlers[CrawlerIndex].Handles.Legs)
                {
                    auto BoundLeg = Leg;
                    utils_procedural_leg::BindTo_OnDetached(BoundLeg,
                        FCk_Delegate_ProceduralLeg_OnDetached(this, n"OnLegDetached"));
                }
                _Courses[CourseIndex].Crawlers[CrawlerIndex].SignalsBound = true;
            }
        }
    }

    UFUNCTION()
    private void OnLegDetached(FCk_Handle_ProceduralLeg InLeg, FCk_ProceduralLeg_ReleasedParts InReleasedParts)
    {
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            if (_Courses[Index].Get_OwnsLeg(InLeg))
            {
                _Courses[Index].Request_RagdollReleasedParts(InLeg, InReleasedParts);
                return;
            }
        }
    }

    UFUNCTION()
    private void OnLegSetChanged(FCk_Handle_ProceduralGait InGait, int32 InEnabledCount, int32 InTotalCount)
    {
        if (InEnabledCount >= ck_procedural_gym::SlowGaitBelowEnabledLegs)
        {
            return;
        }
        auto Gait = InGait;
        UCk_ProceduralGait_Data SlowPreset = ck::ProceduralGym_GaitSlow;
        utils_procedural_gait::Request_ApplyPreset(Gait,
            FCk_Request_ProceduralGait_ApplyPreset(SlowPreset.Get_Timing(), SlowPreset.Get_Step(), SlowPreset.Get_Probe()));
    }

    TArray<FCkGym_ControlRow> Get_ControlRows() override
    {
        auto Rows = TArray<FCkGym_ControlRow>();
        Rows.Add(CkGym_Control::Header("PROCEDURAL ANIMATION"));
        Rows.Add(CkGym_Control::Status("This shows", _Set == 0 ?
            "Nine crawlers traverse uneven ground, a ramp and wall, and a closed loop with live contacts and articulated limbs." :
            "A spider, a centipede, a tentacled walker and a mixed-chain beast cross stairs, rubble and a convex hump with live contacts and articulated limbs."));
        Rows.Add(CkGym_Control::Status("Verdict", Get_Verdict(), _ResetPending));
        for (auto Index = 0; Index < 3; Index++)
        {
            Rows.Add(CkGym_Control::Status(ck_procedural_gym::Get_CourseTitle(Get_SetCourse(Index)), Get_CourseVerdict(Index)));
        }
        Rows.Add(CkGym_Control::Toggle(EKeys::P, "P", "Travel", _Run));
        Rows.Add(CkGym_Control::Action(EKeys::R, "R", "Reset all courses"));
        Rows.Add(CkGym_Control::Action(EKeys::N, "N", "Switch walker set (original / menagerie)"));
        Rows.Add(CkGym_Control::Toggle(EKeys::V, "V", "Contact diagnostics", _DrawContacts));
        Rows.Add(CkGym_Control::Action(EKeys::K, "K", "Disable / enable leg 0 of every crawler"));
        Rows.Add(CkGym_Control::Action(EKeys::J, "J", "Detach leg 1 of the first crawler; its parts ragdoll", _DetachIssued == false));
        Rows.Add(CkGym_Control::Action(EKeys::Home, "Home", "Overview"));
        auto FirstTitle = ck_procedural_gym::Get_CourseTitle(Get_SetCourse(0));
        auto SecondTitle = ck_procedural_gym::Get_CourseTitle(Get_SetCourse(1));
        auto ThirdTitle = ck_procedural_gym::Get_CourseTitle(Get_SetCourse(2));
        Rows.Add(CkGym_Control::Action(EKeys::One, "1", f"View {FirstTitle}"));
        Rows.Add(CkGym_Control::Action(EKeys::Two, "2", f"View {SecondTitle}"));
        Rows.Add(CkGym_Control::Action(EKeys::Three, "3", f"View {ThirdTitle}"));
        return Rows;
    }

    void Request_ControlActivated(int32 InRowIndex) override
    {
        auto Rows = Get_ControlRows();
        if (Rows.IsValidIndex(InRowIndex) == false)
        {
            return;
        }
        auto Key = Rows[InRowIndex].Key;
        if (Key == EKeys::P)
        {
            _Run = !_Run;
        }
        else if (Key == EKeys::R)
        {
            Request_Reset();
        }
        else if (Key == EKeys::N)
        {
            _Set = (_Set + 1) % 2;
            Request_Reset();
        }
        else if (Key == EKeys::V)
        {
            _DrawContacts = !_DrawContacts;
        }
        else if (Key == EKeys::K)
        {
            Request_ToggleFirstLegs();
        }
        else if (Key == EKeys::J)
        {
            Request_DetachFirstCrawlerLeg();
        }
        else if (Key == EKeys::Home)
        {
            Request_Frame(-1);
        }
        else if (Key == EKeys::One)
        {
            Request_Frame(0);
        }
        else if (Key == EKeys::Two)
        {
            Request_Frame(1);
        }
        else if (Key == EKeys::Three)
        {
            Request_Frame(2);
        }
    }

    void Request_ToggleFirstLegs()
    {
        if (_ResetPending)
        {
            return;
        }
        for (auto Index = 0; Index < _Courses.Num(); Index++)
        {
            _Courses[Index].Request_ToggleFirstLeg();
        }
    }

    void Request_DetachFirstCrawlerLeg()
    {
        if (_ResetPending || _DetachIssued || _Courses.Num() == 0)
        {
            return;
        }
        _DetachIssued = _Courses[0].Request_DetachLeg(0, 1);
    }

    UFUNCTION(Exec)
    void Ck_ProceduralAnimation_Control(int32 InRowIndex)
    {
        Request_ControlActivated(InRowIndex);
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
        if (_CreateError.IsEmpty() == false)
        {
            return f"FAILED: {_CreateError}";
        }
        if (_ResetPending || _Courses.Num() != 3)
        {
            return "Pending: resetting owned scenes";
        }
        auto Completed = 0;
        for (auto CourseIndex = 0; CourseIndex < _Courses.Num(); CourseIndex++)
        {
            if (_Courses[CourseIndex].CompositionError.IsEmpty() == false)
            {
                return f"FAILED: {_Courses[CourseIndex].CompositionError}";
            }
            if (_Courses[CourseIndex].Rendering.RenderFailed)
            {
                return "FAILED: solid renderer or master material unavailable";
            }
            for (auto Crawler : _Courses[CourseIndex].Crawlers)
            {
                if (Crawler.Evidence.InvalidOutput)
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
            auto Course = _Courses[InCourse].Spawn.Course;
            Target = _Courses[InCourse].Spawn.Origin + FVector(0.0, 0.0, ck_procedural_gym::Get_FrameTargetZ(Course));
            Eye = Target + FVector(-2100.0, -2400.0, 1400.0);
            if (Course == ECkProceduralAnimationGym_Course::Ring)
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
                auto SpeciesName = ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species);
                ck::Trace(f"[PROCEDURAL-GYM] course={Index} species={SpeciesName} legs={Crawler.Layout.LegCount} displacement={Crawler.Progress.FurthestDistance :.1} replanted={Crawler.Get_ReplantedCount()} wall={Crawler.Evidence.SawWall} ceiling={Crawler.Evidence.SawCeiling} traversals={Crawler.Progress.Traversals}");
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
