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
    // A drawn chain segment passes through a solid when a ray along it hits strictly inside it: a hit at the start is a ray
    // that began inside a solid, and one at the end is the foot resting on its contact surface. Shorter segments (the hip
    // and the chain's first joint coincide) are not cast.
    const float CrossingMinFraction = 0.02;
    const float CrossingMaxFraction = 0.98;
    const float CrossingMinSegmentLength = 0.5;
    // A planted foot is occluded when the ray from its simulation hip meets a solid farther than the gait's default
    // occlusion tolerance from the foot, the gait's own test for an occluded plant.
    const float HipFootOcclusionTolerance = 3.0;
    // The body-pose spring steps are taken where the hump's flat would be, past its foot, on a walker without conform, so the
    // step response is the spring's alone: 180 cm past the foot, and 1.8 s later the enable step still has 1.8 s of flat
    // before the turnaround.
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
        TArray<ECkProceduralAnimationGym_Species> InRoster,
        ECk_ProceduralBodyPose_ConformMode InConformMode = ECk_ProceduralBodyPose_ConformMode::PlantedFeet)
    {
        DoAddCourse(InName, InRoster.Num());
        return Fixtures[Fixtures.Num() - 1].Create_WithRoster(InOwner, InOrigin, InCourse, InRoster, false, InConformMode);
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
        auto StepDuration = Crawler.Layout.GaitPreset.Get_Timing().Get_StepDuration().Get_Seconds();
        auto Clearance = Profile.Clearance;
        auto CollapseDrop = Profile.CollapseDrop;
        auto MaxTilt = ck_procedural_gym::BodyMaxTilt;
        auto TurnaroundX = ck_procedural_gym::TurnaroundX;
        FString Open = "{";
        FString Close = "}";
        // The renderer draws the crossing and the lane's cylinder from these instead of re-deriving the lane layout.
        FString CourseFields = "";
        if (Crawler.Layout.Course == ECkProceduralAnimationGym_Course::PillarCrossing)
        {
            CourseFields = ",\"crossing\":1";
        }
        else if (Crawler.Layout.Course == ECkProceduralAnimationGym_Course::Cylinder)
        {
            auto CylinderRadius = Crawler.Layout.CylinderRadius;
            CourseFields = f",\"cyl\":{CylinderRadius :.1}";
        }
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
        ck::Trace(f"[PAVIZ] {Open}\"k\":\"meta\",\"c\":\"{Course}\",\"s\":\"{WalkerName}\",\"w\":{InWalker},\"frame\":\"fixture-local\",\"origin\":{Origin},\"start\":{Start},\"lane\":{LaneY :.1},\"he\":{HalfExtents},\"clearance\":{Clearance :.1},\"collapse\":{CollapseDrop :.1},\"maxTilt\":{MaxTilt :.1},\"spring\":[{Stiffness :.3},{Damping :.3},{Mass :.3}],\"maxLag\":{MaxAttitudeLag :.1},\"turnX\":{TurnaroundX :.1},\"stepDur\":{StepDuration :.3}{CourseFields},\"legs\":[{Legs}]{Close}", n"PAVIZ.Meta", 0.0f);
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

    // Which drawn chain segments pass through a solid: ",\"oc\":<mask>" with bit i set for the segment from point i to point
    // i + 1 of InPoints (hip, the chain's joints, foot), or nothing when none does.
    FString Get_CrossingFields(TArray<FVector> InPoints) const
    {
        auto Mask = 0;
        for (auto Index = 0; Index + 1 < InPoints.Num(); Index++)
        {
            if ((InPoints[Index + 1] - InPoints[Index]).Size() < ck_paviz_telemetry::CrossingMinSegmentLength)
            {
                continue;
            }
            auto Hit = utils_jolt_query::Get_RayCast(InPoints[Index], InPoints[Index + 1], FCk_Jolt_QueryFilter());
            if (Hit.Get_HasHit() && Hit.Get_Fraction() > ck_paviz_telemetry::CrossingMinFraction &&
                Hit.Get_Fraction() < ck_paviz_telemetry::CrossingMaxFraction)
            {
                Mask = Mask | (1 << Index);
            }
        }
        if (Mask == 0)
        {
            return "";
        }
        return f",\"oc\":{Mask}";
    }

    // ",\"hf\":1" when a solid lies between the planted foot and its simulation hip, or nothing. A ray that starts inside a
    // solid tells nothing, as for the gait.
    FString Get_HipFootFields(FVector InHip, FVector InFoot) const
    {
        auto Hit = utils_jolt_query::Get_RayCast(InHip, InFoot, FCk_Jolt_QueryFilter());
        auto Occluded = Hit.Get_HasHit() && Hit.Get_Fraction() > ck_paviz_telemetry::StartInsideFraction
            && (Hit.Get_Position() - InFoot).Size() > ck_paviz_telemetry::HipFootOcclusionTolerance;
        return Occluded ? ",\"hf\":1" : "";
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
        // ECk_SurfaceMotion_ContactSource by value: None, Forward, Down, LookAhead, Fan, Fall.
        auto ContactSource = int32(utils_surface_motion::Get_ContactSource(Handles.Motion));

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
            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto HipLocation = Presentation.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal());
            auto ChainPoints = TArray<FVector>();
            ChainPoints.Add(HipLocation);
            FString Joints = "";
            for (auto SegmentIndex = 0; SegmentIndex < Segments.Num() && SegmentIndex < SegmentLengths.Num(); SegmentIndex++)
            {
                auto Segment = utils_transform::Get_EntityCurrentTransform(Segments[SegmentIndex]);
                auto HalfAxis = Segment.GetRotation().GetForwardVector() * (SegmentLengths[SegmentIndex] * 0.5);
                if (SegmentIndex == 0)
                {
                    ChainPoints.Add(Segment.GetLocation() - HalfAxis);
                    Joints = Get_Vector(Segment.GetLocation() - HalfAxis - Origin);
                }
                ChainPoints.Add(Segment.GetLocation() + HalfAxis);
                auto FarEnd = Get_Vector(Segment.GetLocation() + HalfAxis - Origin);
                Joints = f"{Joints},{FarEnd}";
            }
            ChainPoints.Add(Foot.Get_Position());
            auto LegId = utils_procedural_leg::Get_Id(Leg);
            auto EnabledValue = utils_procedural_leg::Get_EnableDisable(Leg) == ECk_EnableDisable::Enable;
            auto Enabled = EnabledValue ? 1 : 0;
            auto Planted = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted;
            FString Phase = Planted ? "P" : "S";
            FString Buried = "";
            FString HipFoot = "";
            if (EnabledValue && Planted)
            {
                Buried = Get_BuriedFields(Foot, SupportNormalValue);
                HipFoot = Get_HipFootFields(Body.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal()), Foot.Get_Position());
            }
            auto Contact = Foot.Get_Contact() == ECk_ProceduralLeg_FootContact::Trusted ? 1 : 0;
            // ECk_ProceduralLeg_Foothold by value: None, Ideal, Held, Front, Inward, Outward, Ring.
            auto FootholdSource = int32(Foot.Get_Foothold());
            auto Crossings = Get_CrossingFields(ChainPoints);
            auto FootLocation = Get_Vector(Foot.Get_Position() - Origin);
            auto Hip = Get_Vector(HipLocation - Origin);
            auto Lengths = Get_Lengths(SegmentLengths);
            FString Separator = Legs.IsEmpty() ? "" : ",";
            Legs = f"{Legs}{Separator}{Open}\"id\":\"{LegId}\",\"en\":{Enabled},\"ph\":\"{Phase}\",\"f\":{FootLocation},\"h\":{Hip},\"len\":{Lengths},\"j\":[{Joints}]{Buried},\"ct\":{Contact},\"fh\":{FootholdSource}{HipFoot}{Crossings}{Close}";
        }
        auto Rays = UCk_Utils_ProceduralAnimation_Debug_UE::Get_RaysLastSolve(Handles.Gait);
        ck::Trace(f"[PAVIZ] {Open}\"k\":\"f\",\"c\":\"{Course}\",\"s\":\"{WalkerName}\",\"w\":{InWalker},\"n\":{Frame},\"t\":{InElapsed :.4},\"stage\":{RouteStage},\"sp\":{Spinning},\"b\":{BodyLocation},\"bq\":{BodyRotation},\"p\":{PresentationLocation},\"pq\":{PresentationRotation},\"off\":{OffsetLocation},\"oq\":{OffsetRotation},\"tq\":{TargetRotation},\"sn\":{SupportNormal},\"src\":{ContactSource},\"rays\":{Rays},\"legs\":[{Legs}]{Close}",
            FName(f"PAVIZ.{Course}.{InWalker}"), 0.0f);
    }

    // Traces the run summary, with each walker's completed traversals, and retires every fixture.
    void Finish()
    {
        auto Elapsed = Get_Elapsed();
        FString Open = "{";
        FString Close = "}";
        FString PassedText = "";
        FString TraversalsText = "";
        for (auto FixtureIndex = 0; FixtureIndex < Fixtures.Num(); FixtureIndex++)
        {
            auto Course = CourseNames[FixtureIndex];
            for (auto Walker = 0; Walker < Fixtures[FixtureIndex].Crawlers.Num(); Walker++)
            {
                FString Separator = PassedText.IsEmpty() ? "" : ",";
                auto WalkerPassed = Passed[PassedOffsets[FixtureIndex] + Walker];
                auto Traversals = Fixtures[FixtureIndex].Crawlers[Walker].Progress.Traversals;
                PassedText = f"{PassedText}{Separator}\"{Course}.{Walker}\":{WalkerPassed}";
                TraversalsText = f"{TraversalsText}{Separator}\"{Course}.{Walker}\":{Traversals}";
            }
            Fixtures[FixtureIndex].Request_Destroy();
        }
        ck::Trace(f"[PAVIZ] {Open}\"k\":\"end\",\"n\":{Frame},\"t\":{Elapsed :.4},\"passed\":{Open}{PassedText}{Close},\"trav\":{Open}{TraversalsText}{Close}{Close}",
            n"PAVIZ.End", 0.0f);
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
