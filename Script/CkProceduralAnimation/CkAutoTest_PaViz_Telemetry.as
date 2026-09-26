// Language=angelscript

// Emits one [PAVIZ] JSON line per walker per frame for docs/campaigns/procedural-animation/viz/render_paviz.py.
// Positions are fixture-local (world minus the fixture origin, which the meta line carries); the data is the product,
// so the test passes once the sequence completes.
class UCk_AutoTest_PaViz_Telemetry : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 75.0f;
    default _AutoStageOriginField = false;
    private TArray<FCkProceduralAnimationGym_Fixture> _Fixtures;
    private TArray<FString> _CourseNames;
    private TArray<int32> _PassedOffsets;
    private TArray<bool> _Passed;
    private int32 _SpringFixture = 0;
    private int32 _SpringWalker = 2;
    private float _DisableSeconds = 20.0;
    private float _EnableSeconds = 26.0;
    // Sampling runs past the crossings so both body-pose spring responses settle inside the samples.
    private float _MinSampleSeconds = 34.0;
    private float _MaxSampleSeconds = 45.0;
    private float _PhaseStart = 0.0;
    private float _LastPollTime = -1.0;
    private int32 _Frame = 0;
    private bool _RearDisabled = false;
    private bool _RearEnabled = false;
    private FString _Open = "{";
    private FString _Close = "}";

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
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

    private bool DoAddFixture(FCk_Handle InOwner, FString InName, ECkProceduralAnimationGym_Course InCourse, FVector InOrigin,
        ECkProceduralAnimationGym_Species InFirst, ECkProceduralAnimationGym_Species InSecond, ECkProceduralAnimationGym_Species InThird)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(InFirst);
        Roster.Add(InSecond);
        Roster.Add(InThird);
        _CourseNames.Add(InName);
        _PassedOffsets.Add(_Passed.Num());
        for (auto Index = 0; Index < Roster.Num(); Index++)
        {
            _Passed.Add(false);
        }
        _Fixtures.Add(FCkProceduralAnimationGym_Fixture());
        return _Fixtures[_Fixtures.Num() - 1].Create_WithRoster(InOwner, InOrigin, InCourse, Roster, false);
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Created = DoAddFixture(InHandle, "Hump", ECkProceduralAnimationGym_Course::Hump, FVector(120000.0, 120000.0, 600.0),
            ECkProceduralAnimationGym_Species::Tentacled, ECkProceduralAnimationGym_Species::Spider, ECkProceduralAnimationGym_Species::Beast);
        Created = DoAddFixture(InHandle, "Stairs", ECkProceduralAnimationGym_Course::Stairs, FVector(120000.0, 125000.0, 600.0),
            ECkProceduralAnimationGym_Species::Centipede, ECkProceduralAnimationGym_Species::Spider, ECkProceduralAnimationGym_Species::Beast) && Created;
        Created = DoAddFixture(InHandle, "Uneven", ECkProceduralAnimationGym_Course::Uneven, FVector(120000.0, 135000.0, 600.0),
            ECkProceduralAnimationGym_Species::Crawler4, ECkProceduralAnimationGym_Species::Crawler6, ECkProceduralAnimationGym_Species::Crawler8) && Created;
        Created = DoAddFixture(InHandle, "Rubble", ECkProceduralAnimationGym_Course::Rubble, FVector(120000.0, 140000.0, 600.0),
            ECkProceduralAnimationGym_Species::Centipede, ECkProceduralAnimationGym_Species::Tentacled, ECkProceduralAnimationGym_Species::Beast) && Created;
        if (Created == false)
        {
            FinishFailure("The isolated hump, stairs, uneven and rubble fixtures could not be created");
            return;
        }
        Add_Step_WaitUntil("every walker on the four courses is composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("every walker passes the turnaround and 34 s pass, or 45 s pass, while each frame is traced", n"Check_Sampled", 0, 48.0f);
        Add_Step("trace the run summary and retire the fixtures", n"Step_Finish");
        Add_Step_WaitUntil("every fixture lifetime subtree is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Ready = true;
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Update();
            auto CompositionError = _Fixtures[Index].CompositionError;
            if (CompositionError.IsEmpty() == false)
            {
                FinishFailure(f"A walker could not be composed: '{CompositionError}'");
                return;
            }
            Ready = Ready && _Fixtures[Index].Get_AllReady();
        }
        if (Ready)
        {
            _PhaseStart = float(System::GetGameTimeInSeconds());
            for (auto FixtureIndex = 0; FixtureIndex < _Fixtures.Num(); FixtureIndex++)
            {
                for (auto Walker = 0; Walker < _Fixtures[FixtureIndex].Crawlers.Num(); Walker++)
                {
                    DoEmitMeta(FixtureIndex, Walker);
                }
            }
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Sampled(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixtures.Num(); Index++)
        {
            _Fixtures[Index].Update();
        }
        auto Elapsed = Get_Elapsed();
        if (_RearDisabled == false && Elapsed >= _DisableSeconds)
        {
            _RearDisabled = true;
            DoRequest_RearLegs(ECk_EnableDisable::Disable, "disable", Elapsed);
        }
        if (_RearEnabled == false && Elapsed >= _EnableSeconds)
        {
            _RearEnabled = true;
            DoRequest_RearLegs(ECk_EnableDisable::Enable, "enable", Elapsed);
        }

        // The step tick polls twice per engine frame, before and after the procedural update, at one game time; the
        // second poll carries this frame's pose, so a repeated game time is the one to trace.
        auto Now = float(System::GetGameTimeInSeconds());
        auto Emit = Now == _LastPollTime;
        _LastPollTime = Now;
        if (Emit)
        {
            _Frame++;
        }

        auto AllPassed = true;
        for (auto FixtureIndex = 0; FixtureIndex < _Fixtures.Num(); FixtureIndex++)
        {
            for (auto Walker = 0; Walker < _Fixtures[FixtureIndex].Crawlers.Num(); Walker++)
            {
                auto PassedIndex = _PassedOffsets[FixtureIndex] + Walker;
                _Passed[PassedIndex] = _Passed[PassedIndex] || Get_HasPassedTurnaround(_Fixtures[FixtureIndex].Crawlers[Walker]);
                AllPassed = AllPassed && _Passed[PassedIndex];
                if (Emit)
                {
                    DoEmitFrame(FixtureIndex, Walker, Elapsed);
                }
            }
        }
        auto Result = OutResult;
        Result.Set((AllPassed && Elapsed >= _MinSampleSeconds) || Elapsed >= _MaxSampleSeconds);
    }

    private void DoRequest_RearLegs(ECk_EnableDisable InState, FString InEvent, float InElapsed)
    {
        auto Crawler = _Fixtures[_SpringFixture].Crawlers[_SpringWalker];
        auto Course = _CourseNames[_SpringFixture];
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
        ck::Trace(f"[PAVIZ] {_Open}\"k\":\"ev\",\"ev\":\"{InEvent}\",\"c\":\"{Course}\",\"w\":{_SpringWalker},\"n\":{_Frame},\"t\":{InElapsed :.4},\"legs\":[{Ids}]{_Close}", n"PAVIZ.Event", 0.0f);
    }

    private void DoEmitMeta(int32 InFixture, int32 InWalker)
    {
        auto Crawler = _Fixtures[InFixture].Crawlers[InWalker];
        auto Course = _CourseNames[InFixture];
        auto Profile = ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species);
        auto WalkerName = Get_WalkerName(Crawler);
        auto Spring = FCk_ProceduralBodyPose_Spring();
        auto Origin = Get_Vector(Crawler.Layout.Origin);
        auto Start = Get_Vector(Crawler.Layout.Start - Crawler.Layout.Origin);
        auto HalfExtents = Get_Vector(Profile.BodyHalfExtents);
        auto Stiffness = Spring.Get_Stiffness();
        auto Damping = Spring.Get_CriticalDampingFactor();
        auto Mass = Spring.Get_Mass();
        auto LaneY = Crawler.Layout.LaneY;
        auto Clearance = Profile.Clearance;
        auto CollapseDrop = Profile.CollapseDrop;
        auto MaxTilt = ck_procedural_gym::BodyMaxTilt;
        auto TurnaroundX = ck_procedural_gym::TurnaroundX;
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
            Legs = f"{Legs}{Separator}{_Open}\"id\":\"{LegId}\",\"hip\":{Hip},\"rest\":{Rest},\"pole\":{Pole},\"len\":{Lengths},\"po\":{PhaseOffset :.3}{_Close}";
        }
        ck::Trace(f"[PAVIZ] {_Open}\"k\":\"meta\",\"c\":\"{Course}\",\"s\":\"{WalkerName}\",\"w\":{InWalker},\"frame\":\"fixture-local\",\"origin\":{Origin},\"start\":{Start},\"lane\":{LaneY :.1},\"he\":{HalfExtents},\"clearance\":{Clearance :.1},\"collapse\":{CollapseDrop :.1},\"maxTilt\":{MaxTilt :.1},\"spring\":[{Stiffness :.3},{Damping :.3},{Mass :.3}],\"turnX\":{TurnaroundX :.1},\"legs\":[{Legs}]{_Close}", n"PAVIZ.Meta", 0.0f);
    }

    private void DoEmitFrame(int32 InFixture, int32 InWalker, float InElapsed)
    {
        auto Crawler = _Fixtures[InFixture].Crawlers[InWalker];
        auto Course = _CourseNames[InFixture];
        auto Handles = Crawler.Handles;
        if (ck::Is_NOT_Valid(Handles.Root) || ck::Is_NOT_Valid(Handles.Presentation))
        {
            return;
        }
        auto Origin = Crawler.Layout.Origin;
        auto WalkerName = Get_WalkerName(Crawler);
        auto RouteStage = Crawler.Progress.RouteStage;
        auto Body = utils_transform::Get_EntityCurrentTransform(Handles.Root);
        auto Presentation = utils_transform::Get_EntityCurrentTransform(Handles.Presentation);
        auto Offset = utils_procedural_body_pose::Get_Offset(Handles.BodyPose);
        auto BodyLocation = Get_Vector(Body.GetLocation() - Origin);
        auto BodyRotation = Get_Quat(Body.GetRotation());
        auto PresentationLocation = Get_Vector(Presentation.GetLocation() - Origin);
        auto PresentationRotation = Get_Quat(Presentation.GetRotation());
        auto OffsetLocation = Get_Vector(Offset.GetLocation());
        auto OffsetRotation = Get_Quat(Offset.GetRotation());
        auto SupportNormal = Get_Direction(utils_surface_motion::Get_SupportNormal(Handles.Motion));

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
            auto Enabled = utils_procedural_leg::Get_EnableDisable(Leg) == ECk_EnableDisable::Enable ? 1 : 0;
            FString Phase = Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted ? "P" : "S";
            auto FootLocation = Get_Vector(Foot.Get_Position() - Origin);
            auto Hip = Get_Vector(Presentation.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal()) - Origin);
            auto Lengths = Get_Lengths(SegmentLengths);
            FString Separator = Legs.IsEmpty() ? "" : ",";
            Legs = f"{Legs}{Separator}{_Open}\"id\":\"{LegId}\",\"en\":{Enabled},\"ph\":\"{Phase}\",\"f\":{FootLocation},\"h\":{Hip},\"len\":{Lengths},\"j\":[{Joints}]{_Close}";
        }
        ck::Trace(f"[PAVIZ] {_Open}\"k\":\"f\",\"c\":\"{Course}\",\"s\":\"{WalkerName}\",\"w\":{InWalker},\"n\":{_Frame},\"t\":{InElapsed :.4},\"stage\":{RouteStage},\"b\":{BodyLocation},\"bq\":{BodyRotation},\"p\":{PresentationLocation},\"pq\":{PresentationRotation},\"off\":{OffsetLocation},\"oq\":{OffsetRotation},\"sn\":{SupportNormal},\"legs\":[{Legs}]{_Close}",
            FName(f"PAVIZ.{Course}.{InWalker}"), 0.0f);
    }

    UFUNCTION()
    private void Step_Finish(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Elapsed = Get_Elapsed();
        FString Passed = "";
        for (auto FixtureIndex = 0; FixtureIndex < _Fixtures.Num(); FixtureIndex++)
        {
            auto Course = _CourseNames[FixtureIndex];
            for (auto Walker = 0; Walker < _Fixtures[FixtureIndex].Crawlers.Num(); Walker++)
            {
                FString Separator = Passed.IsEmpty() ? "" : ",";
                auto WalkerPassed = _Passed[_PassedOffsets[FixtureIndex] + Walker];
                Passed = f"{Passed}{Separator}\"{Course}.{Walker}\":{WalkerPassed}";
            }
            _Fixtures[FixtureIndex].Request_Destroy();
        }
        ck::Trace(f"[PAVIZ] {_Open}\"k\":\"end\",\"n\":{_Frame},\"t\":{Elapsed :.4},\"passed\":{_Open}{Passed}{_Close}{_Close}", n"PAVIZ.End", 0.0f);
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
