// Language=angelscript

// The tentacled walker and the spider cross the convex hump, turn and cross it again. Every frame is measured the way
// docs/campaigns/procedural-animation/viz/render_paviz.py measures the PaViz harness, and the run must meet its acceptance:
// M1 interior joints inside the drawn body, M2 planted feet out of reach, M3 drawn feet sliding while planted, and M5 the
// drawn body's up turning per frame.
struct FCkProceduralAnimation_WalkQuality
{
    UPROPERTY()
    TArray<float> JointDepths;
    UPROPERTY()
    int32 PlantedSamples = 0;
    UPROPERTY()
    int32 PlantedBeyondReach = 0;
    UPROPERTY()
    TArray<float> PlantSlides;
    UPROPERTY()
    TArray<bool> Planted;
    UPROPERTY()
    TArray<FVector> PlantStarts;
    UPROPERTY()
    TArray<float> PlantMaxSlides;
    UPROPERTY()
    TArray<float> UpSteps;
    UPROPERTY()
    FVector LastUp;
    UPROPERTY()
    bool HasLastUp = false;
    UPROPERTY()
    int32 LastStage = 0;
    UPROPERTY()
    float LastTurnTime = -1000.0;
    UPROPERTY()
    bool PassedTurnaround = false;
    UPROPERTY()
    bool CrossedBack = false;
}

class UCk_AutoTest_ProceduralAnimation_WalkQualityOnHump : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 50.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 170000.0, 600.0);
    private TArray<FCkProceduralAnimation_WalkQuality> _Quality;
    private float _PhaseStart = 0.0;
    private float _LastPollTime = -1.0;
    private float _TurnaroundExclusionSeconds = 1.0;
    private float _MaxJointDepthP99 = 1.0;
    private float _MaxPlantedBeyondReach = 0.01;
    private float _MaxPlantSlideP95 = 3.0;
    private float _MaxUpStepP95 = 1.5;
    private float _ReturnX = 0.0;

    float Get_Elapsed() const
    {
        return float(System::GetGameTimeInSeconds()) - _PhaseStart;
    }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Tentacled);
        Roster.Add(ECkProceduralAnimationGym_Species::Spider);
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Hump, Roster, false) == false)
        {
            FinishFailure("The isolated hump fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("both walkers are composed and evaluated", n"Check_Ready", 1200, 15.0f);
        Add_Step_WaitUntil("both walkers cross the hump, turn and come back over its crest while every frame is measured",
            n"Check_Walked", 0, 36.0f);
        Add_Step("verify the walk quality and retire the fixture", n"Step_Verify");
        Add_Step_WaitUntil("the fixture is gone", n"Check_Destroyed");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"The walkers could not be composed: {_Fixture.CompositionError}");
            return;
        }
        auto Ready = _Fixture.Get_AllReady();
        if (Ready)
        {
            for (auto Index = 0; Index < _Fixture.Crawlers.Num(); Index++)
            {
                auto Quality = FCkProceduralAnimation_WalkQuality();
                for (auto Leg : _Fixture.Crawlers[Index].Handles.Legs)
                {
                    Quality.Planted.Add(false);
                    Quality.PlantStarts.Add(FVector::ZeroVector);
                    Quality.PlantMaxSlides.Add(0.0);
                }
                _Quality.Add(Quality);
            }
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Walked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();

        // The step tick polls twice per engine frame, before and after the procedural update, at one game time; the
        // second poll carries this frame's pose, so only a repeated game time is measured.
        auto Now = float(System::GetGameTimeInSeconds());
        auto Measure = Now == _LastPollTime;
        _LastPollTime = Now;

        auto Done = true;
        for (auto Index = 0; Index < _Fixture.Crawlers.Num(); Index++)
        {
            if (Measure)
            {
                DoMeasure(Index, Get_Elapsed());
            }
            Done = Done && _Quality[Index].CrossedBack;
        }
        auto Result = OutResult;
        Result.Set(Done);
    }

    private void DoMeasure(int32 InIndex, float InElapsed)
    {
        auto Crawler = _Fixture.Crawlers[InIndex];
        auto& Quality = _Quality[InIndex];
        auto Handles = Crawler.Handles;
        auto Profile = ck_procedural_gym::Get_SpeciesProfile(Crawler.Layout.Species);
        auto HalfExtents = Profile.BodyHalfExtents;
        auto Presentation = utils_transform::Get_EntityCurrentTransform(Handles.Presentation);
        auto RootLocal = utils_transform::Get_EntityCurrentLocation(Handles.Root) - Crawler.Layout.Origin;

        if (Crawler.Progress.RouteStage != Quality.LastStage)
        {
            Quality.LastStage = Crawler.Progress.RouteStage;
            Quality.LastTurnTime = InElapsed;
            Quality.PassedTurnaround = true;
        }
        Quality.CrossedBack = Quality.CrossedBack || (Quality.PassedTurnaround && RootLocal.X < _ReturnX);
        auto AfterTurnaround = InElapsed - Quality.LastTurnTime <= _TurnaroundExclusionSeconds;

        auto FrameDepth = 0.0;
        for (auto LegIndex = 0; LegIndex < Handles.Legs.Num(); LegIndex++)
        {
            auto Leg = Handles.Legs[LegIndex];
            auto Rig = utils_procedural_rig::DoCast(Leg);
            if (ck::Is_NOT_Valid(Leg) || Rig.IsSet() == false)
            {
                continue;
            }
            auto Segments = utils_procedural_rig::Get_Chain(Rig.GetValue()).Get_Segments();
            auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            auto Joints = TArray<FVector>();
            auto ChainLength = 0.0;
            for (auto SegmentIndex = 0; SegmentIndex < Segments.Num() && SegmentIndex < Lengths.Num(); SegmentIndex++)
            {
                auto Segment = utils_transform::Get_EntityCurrentTransform(Segments[SegmentIndex]);
                auto HalfAxis = Segment.GetRotation().GetForwardVector() * (Lengths[SegmentIndex] * 0.5);
                if (SegmentIndex == 0)
                {
                    Joints.Add(Segment.GetLocation() - HalfAxis);
                }
                Joints.Add(Segment.GetLocation() + HalfAxis);
                ChainLength += Lengths[SegmentIndex];
            }
            if (Joints.Num() < 2)
            {
                continue;
            }

            for (auto JointIndex = 1; JointIndex < Joints.Num() - 1; JointIndex++)
            {
                auto Local = Presentation.InverseTransformPosition(Joints[JointIndex]);
                auto Depth = Math::Min(HalfExtents.X - Math::Abs(Local.X),
                    Math::Min(HalfExtents.Y - Math::Abs(Local.Y), HalfExtents.Z - Math::Abs(Local.Z)));
                FrameDepth = Math::Max(FrameDepth, Depth);
            }

            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto ChainEnd = Joints[Joints.Num() - 1];
            if (Foot.Get_Phase() == ECk_ProceduralLeg_FootPhase::Planted)
            {
                auto Hip = Presentation.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal());
                Quality.PlantedSamples++;
                if ((Foot.Get_Position() - Hip).Size() > ChainLength)
                {
                    Quality.PlantedBeyondReach++;
                }
                if (Quality.Planted[LegIndex] == false)
                {
                    Quality.Planted[LegIndex] = true;
                    Quality.PlantStarts[LegIndex] = ChainEnd;
                    Quality.PlantMaxSlides[LegIndex] = 0.0;
                }
                else
                {
                    Quality.PlantMaxSlides[LegIndex] = Math::Max(Quality.PlantMaxSlides[LegIndex], (ChainEnd - Quality.PlantStarts[LegIndex]).Size());
                }
            }
            else if (Quality.Planted[LegIndex])
            {
                Quality.Planted[LegIndex] = false;
                Quality.PlantSlides.Add(Quality.PlantMaxSlides[LegIndex]);
            }
        }
        if (AfterTurnaround == false)
        {
            Quality.JointDepths.Add(FrameDepth);
        }

        auto Up = Presentation.GetRotation().GetUpVector();
        if (Quality.HasLastUp)
        {
            Quality.UpSteps.Add(Math::RadiansToDegrees(Math::Acos(Math::Clamp(Up.DotProduct(Quality.LastUp), -1.0, 1.0))));
        }
        Quality.LastUp = Up;
        Quality.HasLastUp = true;
    }

    // Linear interpolation between the two closest ranks, as render_paviz.py's percentile().
    float Get_Percentile(TArray<float> InValues, float InPercent) const
    {
        if (InValues.Num() == 0)
        {
            return 0.0;
        }
        auto Ordered = InValues;
        Ordered.Sort();
        auto Rank = (Ordered.Num() - 1) * InPercent / 100.0;
        auto Low = Math::FloorToInt(Rank);
        auto High = Math::Min(Low + 1, Ordered.Num() - 1);
        return Ordered[Low] + (Ordered[High] - Ordered[Low]) * (Rank - Low);
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixture.Crawlers.Num(); Index++)
        {
            auto Crawler = _Fixture.Crawlers[Index];
            auto Quality = _Quality[Index];
            auto Name = ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species);
            for (auto LegIndex = 0; LegIndex < Quality.Planted.Num(); LegIndex++)
            {
                if (Quality.Planted[LegIndex])
                {
                    Quality.PlantSlides.Add(Quality.PlantMaxSlides[LegIndex]);
                }
            }

            auto DepthP99 = Get_Percentile(Quality.JointDepths, 99.0);
            auto BeyondReach = Quality.PlantedSamples > 0 ? float(Quality.PlantedBeyondReach) / float(Quality.PlantedSamples) : 1.0;
            auto SlideP95 = Get_Percentile(Quality.PlantSlides, 95.0);
            auto UpStepP95 = Get_Percentile(Quality.UpSteps, 95.0);
            auto Frames = Quality.UpSteps.Num();
            auto Plants = Quality.PlantSlides.Num();
            ck::Trace(f"[WALK-QUALITY] {Name}: M1 p99 depth {DepthP99 :.3} cm over {Quality.JointDepths.Num()} frames, M2 {BeyondReach :.4} of {Quality.PlantedSamples} planted samples, M3 p95 slide {SlideP95 :.3} cm over {Plants} plants, M5 p95 up step {UpStepP95 :.3} deg over {Frames} frames");

            Assert_True(Quality.CrossedBack, f"The {Name} crossed the hump, turned and came back over its crest");
            Assert_True(Plants > 0 && Frames > 0, f"The {Name} was measured ({Frames} frames, {Plants} plants)");
            Assert_True(DepthP99 < _MaxJointDepthP99,
                f"M1: the {Name}'s interior joints stay out of its drawn body (p99 depth {DepthP99 :.3} cm, below {_MaxJointDepthP99 :.1})");
            Assert_True(BeyondReach < _MaxPlantedBeyondReach,
                f"M2: the {Name}'s planted feet stay within reach ({BeyondReach :.4} beyond, below {_MaxPlantedBeyondReach :.2})");
            Assert_True(SlideP95 < _MaxPlantSlideP95,
                f"M3: the {Name}'s drawn feet hold while planted (p95 slide {SlideP95 :.3} cm, below {_MaxPlantSlideP95 :.1})");
            Assert_True(UpStepP95 < _MaxUpStepP95,
                f"M5: the {Name}'s drawn body turns smoothly on the hump (p95 {UpStepP95 :.3} deg per frame, below {_MaxUpStepP95 :.1})");
        }
        _Fixture.Request_Destroy();
    }

    UFUNCTION()
    private void Check_Destroyed(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Result = OutResult;
        Result.Set(_Fixture.Get_IsDestroyed());
    }
}
