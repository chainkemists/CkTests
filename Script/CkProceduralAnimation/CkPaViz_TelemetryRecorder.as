// Language=angelscript

// Traces one [PAVIZ] JSON line per walker per frame for docs/campaigns/procedural-animation/viz/render_paviz.py. Each PaViz
// telemetry autotest owns one recorder and its own courses. Positions are fixture-local (world minus the fixture origin,
// which the meta line carries); the data is the product, so a test passes once its sequence completes.
namespace ck_paviz_telemetry
{
    // Sampling covers every walker's turnaround and most of its return.
    const float MinSampleSeconds = 34.0;
    const float MaxSampleSeconds = 45.0;
    // The buried-foot ray starts this far out along the foot's contact normal and ends on the foot, so a hit above the foot
    // measures how deep the foot sits inside a solid, whatever the course's shape.
    const float BuriedRayLength = 60.0;
    // A ray that hits at its very start began inside a solid: the depth is then unknown, not zero.
    const float StartInsideFraction = 0.0001;
    // The body-pose spring steps are taken on the flat past the hump: 180 cm past its foot the offset has settled from the
    // descent, and 1.8 s later the enable step still has 1.8 s of flat after the turnaround.
    const float SpringStepsPastHump = 180.0;
    const float SpringStepSeconds = 1.8;

    TArray<ECkProceduralAnimationGym_Species> MakeRoster(ECkProceduralAnimationGym_Species InFirst, ECkProceduralAnimationGym_Species InSecond,
        ECkProceduralAnimationGym_Species InThird)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(InFirst);
        Roster.Add(InSecond);
        Roster.Add(InThird);
        return Roster;
    }
}

struct FCkPaViz_TelemetryRecorder
{
    UPROPERTY()
    TArray<FCkProceduralAnimationGym_Fixture> Fixtures;
    UPROPERTY()
    TArray<FString> CourseNames;
    UPROPERTY()
    TArray<int32> PassedOffsets;
    UPROPERTY()
    TArray<bool> Passed;
    // The fixture and walker whose rear legs step the body-pose spring; -1 takes no spring steps.
    UPROPERTY()
    int32 SpringFixture = -1;
    UPROPERTY()
    int32 SpringWalker = -1;
    UPROPERTY()
    float DisabledAt = -1.0;
    UPROPERTY()
    bool RearDisabled = false;
    UPROPERTY()
    bool RearEnabled = false;
    UPROPERTY()
    float PhaseStart = 0.0;
    UPROPERTY()
    float LastPollTime = -1.0;
    UPROPERTY()
    int32 Frame = 0;
    UPROPERTY()
    FString CompositionError;

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - PhaseStart;
    }

    FString Get_Vector(FVector InValue) const
    {
        return f"[{InValue.X :.1},{InValue.Y :.1},{InValue.Z :.1}]";
    }

    FString Get_Direction(FVector InValue) const
    {
        return f"[{InValue.X :.4},{InValue.Y :.4},{InValue.Z :.4}]";
    }

    FString Get_Quat(FQuat InValue) const
    {
        return f"[{InValue.X :.4},{InValue.Y :.4},{InValue.Z :.4},{InValue.W :.4}]";
    }

    FString Get_Lengths(TArray<float32> InLengths) const
    {
        FString Text = "";
        for (auto Index = 0; Index < InLengths.Num(); Index++)
        {
            FString Separator = Index == 0 ? "" : ",";
            auto Length = InLengths[Index];
            Text = f"{Text}{Separator}{Length :.1}";
        }
        return f"[{Text}]";
    }

    FString Get_WalkerName(const FCkProceduralAnimationGym_Crawler& InCrawler) const
    {
        auto SpeciesName = ck_procedural_gym::Get_SpeciesName(InCrawler.Layout.Species);
        return SpeciesName == "Crawler" ? f"Crawler{InCrawler.Layout.LegCount}" : SpeciesName;
    }

    bool Get_HasPassedTurnaround(const FCkProceduralAnimationGym_Crawler& InCrawler) const
    {
        return InCrawler.Progress.RouteStage == 1 || InCrawler.Progress.Traversals > 0;
    }

    void DoAddCourse(FString InName, int32 InWalkers)
    {
        CourseNames.Add(InName);
        PassedOffsets.Add(Passed.Num());
        for (auto Index = 0; Index < InWalkers; Index++)
        {
            Passed.Add(false);
        }
        Fixtures.Add(FCkProceduralAnimationGym_Fixture());
    }

    bool Add_Fixture(FCk_Handle InOwner, FString InName, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin,
        TArray<ECkProceduralAnimationGym_Species> InRoster)
    {
        DoAddCourse(InName, InRoster.Num());
        return Fixtures[Fixtures.Num() - 1].Create_WithRoster(InOwner, InOrigin, InCourse, InRoster, false);
    }

    // The 4, 6 and 8-leg crawlers of the fixture's default Create.
    bool Add_CrawlerFixture(FCk_Handle InOwner, FString InName, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin)
    {
        auto Walkers = 3;
        DoAddCourse(InName, Walkers);
        return Fixtures[Fixtures.Num() - 1].Create(InOwner, InOrigin, InCourse, false, Walkers);
    }

    void Enable_SpringSteps(int32 InFixture, int32 InWalker)
    {
        SpringFixture = InFixture;
        SpringWalker = InWalker;
    }

    // Updates every fixture and reports whether every walker is composed and evaluated; a composition error is left in
    // CompositionError. On the ready poll it traces each walker's meta line and starts the clock.
    bool Update_Ready()
    {
        auto Ready = true;
        for (auto Index = 0; Index < Fixtures.Num(); Index++)
        {
            Fixtures[Index].Update();
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
            for (auto FixtureIndex = 0; FixtureIndex < Fixtures.Num(); FixtureIndex++)
            {
                for (auto Walker = 0; Walker < Fixtures[FixtureIndex].Crawlers.Num(); Walker++)
                {
                    DoEmitMeta(FixtureIndex, Walker);
                }
            }
        }
        return Ready;
    }

    // Updates every fixture and traces this frame's pose; true once every walker passed its turnaround and the minimum
    // time passed, or the maximum time passed.
    bool Update_Sampled()
    {
        for (auto Index = 0; Index < Fixtures.Num(); Index++)
        {
            Fixtures[Index].Update();
        }
        auto Elapsed = Get_Elapsed();
        if (SpringFixture >= 0)
        {
            DoUpdate_SpringSteps(Elapsed);
        }

        // The step tick polls twice per engine frame, before and after the procedural update, at one game time; the
        // second poll carries this frame's pose, so a repeated game time is the one to trace.
        auto Now = float(System::GetGameTimeInSeconds());
        auto Emit = Now == LastPollTime;
        LastPollTime = Now;
        if (Emit)
        {
            Frame++;
        }

        auto AllPassed = true;
        for (auto FixtureIndex = 0; FixtureIndex < Fixtures.Num(); FixtureIndex++)
        {
            for (auto Walker = 0; Walker < Fixtures[FixtureIndex].Crawlers.Num(); Walker++)
            {
                auto PassedIndex = PassedOffsets[FixtureIndex] + Walker;
                Passed[PassedIndex] = Passed[PassedIndex] || Get_HasPassedTurnaround(Fixtures[FixtureIndex].Crawlers[Walker]);
                AllPassed = AllPassed && Passed[PassedIndex];
                if (Emit)
                {
                    DoEmitFrame(FixtureIndex, Walker, Elapsed);
                }
            }
        }
        return (AllPassed && Elapsed >= ck_paviz_telemetry::MinSampleSeconds) || Elapsed >= ck_paviz_telemetry::MaxSampleSeconds;
    }

    void DoUpdate_SpringSteps(float InElapsed)
    {
        auto SpringCrawler = Fixtures[SpringFixture].Crawlers[SpringWalker];
        auto SpringX = utils_transform::Get_EntityCurrentLocation(SpringCrawler.Handles.Root).X - SpringCrawler.Layout.Origin.X;
        auto PastHump = SpringX > ck_procedural_gym::HumpHalfWidth + ck_paviz_telemetry::SpringStepsPastHump;
        if (RearDisabled == false && SpringCrawler.Progress.RouteStage == 0 && PastHump)
        {
            RearDisabled = true;
            DisabledAt = InElapsed;
            DoRequest_RearLegs(ECk_EnableDisable::Disable, "disable", InElapsed);
        }
        if (RearDisabled && RearEnabled == false && InElapsed >= DisabledAt + ck_paviz_telemetry::SpringStepSeconds)
        {
            RearEnabled = true;
            DoRequest_RearLegs(ECk_EnableDisable::Enable, "enable", InElapsed);
        }
    }

    void DoRequest_RearLegs(ECk_EnableDisable InState, FString InEvent, float InElapsed)
    {
        auto Crawler = Fixtures[SpringFixture].Crawlers[SpringWalker];
        auto Course = CourseNames[SpringFixture];
        FString Ids = "";
        for (auto Leg : Crawler.Handles.Legs)
        {
            if (ck::Is_NOT_Valid(Leg) || utils_procedural_leg::Get_Placement(Leg).Get_HipLocal().X >= 0.0)
            {
                continue;
            }
            auto LegLocal = Leg;
            utils_procedural_leg::Request_EnableDisable(LegLocal, FCk_Request_ProceduralLeg_EnableDisable(InState));
            auto LegId = utils_procedural_leg::Get_Id(Leg);
            FString Separator = Ids.IsEmpty() ? "" : ",";
            Ids = f"{Ids}{Separator}\"{LegId}\"";
        }
        FString Open = "{";
        FString Close = "}";
        ck::Trace(f"[PAVIZ] {Open}\"k\":\"ev\",\"ev\":\"{InEvent}\",\"c\":\"{Course}\",\"w\":{SpringWalker},\"n\":{Frame},\"t\":{InElapsed :.4},\"legs\":[{Ids}]{Close}", n"PAVIZ.Event", 0.0f);
    }

    void DoEmitMeta(int32 InFixture, int32 InWalker)
    {
        auto Crawler = Fixtures[InFixture].Crawlers[InWalker];
        auto Course = CourseNames[InFixture];
        auto Profile = ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species);
        auto WalkerName = Get_WalkerName(Crawler);
        auto Spring = FCk_ProceduralBodyPose_Spring();
        auto Origin = Get_Vector(Crawler.Layout.Origin);
        auto Start = Get_Vector(Crawler.Layout.Start - Crawler.Layout.Origin);
        auto HalfExtents = Get_Vector(Profile.BodyHalfExtents);
        auto Stiffness = Spring.Get_Stiffness();
        auto Damping = Spring.Get_CriticalDampingFactor();
        auto Mass = Spring.Get_Mass();
        auto MaxAttitudeLag = Spring.Get_MaxAttitudeLag();
        auto LaneY = Crawler.Layout.LaneY;
        auto Clearance = Profile.Clearance;
        auto CollapseDrop = Profile.CollapseDrop;
        auto MaxTilt = ck_procedural_gym::BodyMaxTilt;
        auto TurnaroundX = ck_procedural_gym::TurnaroundX;
        FString Open = "{";
        FString Close = "}";
        FString Legs = "";
        for (auto Leg : Crawler.Handles.Legs)
        {
            if (ck::Is_NOT_Valid(Leg))
            {
                continue;
            }
            auto Placement = utils_procedural_leg::Get_Placement(Leg);
            auto Chain = utils_procedural_leg::Get_ChainGeometry(Leg);
            auto LegId = utils_procedural_leg::Get_Id(Leg);
            auto Hip = Get_Vector(Placement.Get_HipLocal());
            auto Rest = Get_Vector(Placement.Get_RestFootLocal());
            auto Pole = Get_Vector(Chain.Get_PoleLocal());
            auto Lengths = Get_Lengths(Chain.Get_SegmentLengths());
            auto PhaseOffset = Placement.Get_PhaseOffset();
            FString Separator = Legs.IsEmpty() ? "" : ",";
            Legs = f"{Legs}{Separator}{Open}\"id\":\"{LegId}\",\"hip\":{Hip},\"rest\":{Rest},\"pole\":{Pole},\"len\":{Lengths},\"po\":{PhaseOffset :.3}{Close}";
        }
        ck::Trace(f"[PAVIZ] {Open}\"k\":\"meta\",\"c\":\"{Course}\",\"s\":\"{WalkerName}\",\"w\":{InWalker},\"frame\":\"fixture-local\",\"origin\":{Origin},\"start\":{Start},\"lane\":{LaneY :.1},\"he\":{HalfExtents},\"clearance\":{Clearance :.1},\"collapse\":{CollapseDrop :.1},\"maxTilt\":{MaxTilt :.1},\"spring\":[{Stiffness :.3},{Damping :.3},{Mass :.3}],\"maxLag\":{MaxAttitudeLag :.1},\"turnX\":{TurnaroundX :.1},\"legs\":[{Legs}]{Close}", n"PAVIZ.Meta", 0.0f);
    }

    // How deep a planted foot sits inside a solid along its contact normal: ",\"bd\":<cm>" with ",\"bs\":1" when the ray
    // began inside a solid.
    FString Get_BuriedFields(FCk_ProceduralLeg_Foot InFoot, FVector InSupportNormal) const
    {
        auto Normal = InFoot.Get_Normal().GetSafeNormal();
        if (Normal.IsNearlyZero())
        {
            Normal = InSupportNormal;
        }
        auto Start = InFoot.Get_Position() + Normal * ck_paviz_telemetry::BuriedRayLength;
        auto Hit = utils_jolt_query::Get_RayCast(Start, InFoot.Get_Position(), FCk_Jolt_QueryFilter());
        if (Hit.Get_HasHit() == false)
        {
            return ",\"bd\":0.0";
        }
        auto RayLength = ck_paviz_telemetry::BuriedRayLength;
        if (Hit.Get_Fraction() <= ck_paviz_telemetry::StartInsideFraction)
        {
            return f",\"bd\":{RayLength :.1},\"bs\":1";
        }
        auto Depth = (1.0 - Hit.Get_Fraction()) * RayLength;
        return f",\"bd\":{Depth :.1}";
    }

    void DoEmitFrame(int32 InFixture, int32 InWalker, float InElapsed)
    {
        auto Crawler = Fixtures[InFixture].Crawlers[InWalker];
        auto Course = CourseNames[InFixture];
        auto Handles = Crawler.Handles;
        if (ck::Is_NOT_Valid(Handles.Root) || ck::Is_NOT_Valid(Handles.Presentation))
        {
            return;
        }
        FString Open = "{";
        FString Close = "}";
        auto Origin = Crawler.Layout.Origin;
        auto WalkerName = Get_WalkerName(Crawler);
        auto RouteStage = Crawler.Progress.RouteStage;
        auto Spinning = Crawler.Progress.Spinning ? 1 : 0;
        auto Body = utils_transform::Get_EntityCurrentTransform(Handles.Root);
        auto Presentation = utils_transform::Get_EntityCurrentTransform(Handles.Presentation);
        auto Offset = utils_procedural_body_pose::Get_Offset(Handles.BodyPose);
        auto Target = utils_procedural_body_pose::Get_TargetOffset(Handles.BodyPose);
        auto BodyLocation = Get_Vector(Body.GetLocation() - Origin);
        auto BodyRotation = Get_Quat(Body.GetRotation());
        auto PresentationLocation = Get_Vector(Presentation.GetLocation() - Origin);
        auto PresentationRotation = Get_Quat(Presentation.GetRotation());
        auto OffsetLocation = Get_Vector(Offset.GetLocation());
        auto OffsetRotation = Get_Quat(Offset.GetRotation());
        auto TargetRotation = Get_Quat(Target.GetRotation());
        auto SupportNormalValue = utils_surface_motion::Get_SupportNormal(Handles.Motion);
        auto SupportNormal = Get_Direction(SupportNormalValue);

        FString Legs = "";
        for (auto Leg : Handles.Legs)
        {
            if (ck::Is_NOT_Valid(Leg))
            {
                continue;
            }
            auto Rig = utils_procedural_rig::DoCast(Leg);
            if (Rig.IsSet() == false)
            {
                continue;
            }
            auto Segments = utils_procedural_rig::Get_Chain(Rig.GetValue()).Get_Segments();
            auto SegmentLengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            FString Joints = "";
            for (auto SegmentIndex = 0; SegmentIndex < Segments.Num() && SegmentIndex < SegmentLengths.Num(); SegmentIndex++)
            {
                auto Segment = utils_transform::Get_EntityCurrentTransform(Segments[SegmentIndex]);
                auto HalfAxis = Segment.GetRotation().GetForwardVector() * (SegmentLengths[SegmentIndex] * 0.5);
                if (SegmentIndex == 0)
                {
                    Joints = Get_Vector(Segment.GetLocation() - HalfAxis - Origin);
                }
                auto FarEnd = Get_Vector(Segment.GetLocation() + HalfAxis - Origin);
                Joints = f"{Joints},{FarEnd}";
            }
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto LegId = utils_procedural_leg::Get_Id(Leg);
            auto EnabledValue = utils_procedural_leg::Get_EnableDisable(Leg) == ECk_EnableDisable::Enable;
            auto Enabled = EnabledValue ? 1 : 0;
            auto Planted = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted;
            FString Phase = Planted ? "P" : "S";
            FString Buried = "";
            if (EnabledValue && Planted)
            {
                Buried = Get_BuriedFields(Foot, SupportNormalValue);
            }
            auto FootLocation = Get_Vector(Foot.Get_Position() - Origin);
            auto Hip = Get_Vector(Presentation.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal()) - Origin);
            auto Lengths = Get_Lengths(SegmentLengths);
            FString Separator = Legs.IsEmpty() ? "" : ",";
            Legs = f"{Legs}{Separator}{Open}\"id\":\"{LegId}\",\"en\":{Enabled},\"ph\":\"{Phase}\",\"f\":{FootLocation},\"h\":{Hip},\"len\":{Lengths},\"j\":[{Joints}]{Buried}{Close}";
        }
        ck::Trace(f"[PAVIZ] {Open}\"k\":\"f\",\"c\":\"{Course}\",\"s\":\"{WalkerName}\",\"w\":{InWalker},\"n\":{Frame},\"t\":{InElapsed :.4},\"stage\":{RouteStage},\"sp\":{Spinning},\"b\":{BodyLocation},\"bq\":{BodyRotation},\"p\":{PresentationLocation},\"pq\":{PresentationRotation},\"off\":{OffsetLocation},\"oq\":{OffsetRotation},\"tq\":{TargetRotation},\"sn\":{SupportNormal},\"legs\":[{Legs}]{Close}",
            FName(f"PAVIZ.{Course}.{InWalker}"), 0.0f);
    }

    // Traces the run summary and retires every fixture.
    void Finish()
    {
        auto Elapsed = Get_Elapsed();
        FString Open = "{";
        FString Close = "}";
        FString PassedText = "";
        for (auto FixtureIndex = 0; FixtureIndex < Fixtures.Num(); FixtureIndex++)
        {
            auto Course = CourseNames[FixtureIndex];
            for (auto Walker = 0; Walker < Fixtures[FixtureIndex].Crawlers.Num(); Walker++)
            {
                FString Separator = PassedText.IsEmpty() ? "" : ",";
                auto WalkerPassed = Passed[PassedOffsets[FixtureIndex] + Walker];
                PassedText = f"{PassedText}{Separator}\"{Course}.{Walker}\":{WalkerPassed}";
            }
            Fixtures[FixtureIndex].Request_Destroy();
        }
        ck::Trace(f"[PAVIZ] {Open}\"k\":\"end\",\"n\":{Frame},\"t\":{Elapsed :.4},\"passed\":{Open}{PassedText}{Close}{Close}", n"PAVIZ.End", 0.0f);
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
