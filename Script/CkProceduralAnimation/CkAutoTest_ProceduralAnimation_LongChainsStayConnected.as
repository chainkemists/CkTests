// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_LongChainsStayConnected : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 12.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 100000.0, 600.0);
    private float _PhaseStart = 0.0;
    // FABRIK's fixed iteration count converges more slowly as a long chain straightens, so the reach assertion samples
    // feet up to 95 % of the chain's length and the 95-98 % band is only traced.
    private float _ReachableFraction = 0.95;
    private float _NearExtensionFraction = 0.98;
    private TArray<float> _MaxJointGap;
    private TArray<float> _MaxReachError;
    private TArray<float> _MaxReachErrorNearExtension;
    private TArray<int32> _ReachableSamples;
    private TArray<int32> _NearExtensionSamples;
    private TArray<FString> _WorstGap;
    private TArray<FString> _WorstReach;
    private TArray<FString> _WorstReachNearExtension;

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
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, Roster, false) == false)
        {
            FinishFailure("The isolated long-chain floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("both long-chain walkers are composed and evaluated", n"Check_Ready", 1200);
        Add_Step_WaitUntil("the walkers walk for 3 s while every chain is measured", n"Check_WalkedThreeSeconds", 0, 4.0f);
        Add_Step("verify every chain stayed connected and reached its planted foot", n"Step_Verify");
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
                _MaxJointGap.Add(0.0);
                _MaxReachError.Add(0.0);
                _MaxReachErrorNearExtension.Add(0.0);
                _ReachableSamples.Add(0);
                _NearExtensionSamples.Add(0);
                _WorstGap.Add("none");
                _WorstReach.Add("none");
                _WorstReachNearExtension.Add("none");
            }
            _PhaseStart = float(System::GetGameTimeInSeconds());
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_WalkedThreeSeconds(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update();
        for (auto Index = 0; Index < _Fixture.Crawlers.Num(); Index++)
        {
            DoMeasure(Index);
        }
        auto Result = OutResult;
        Result.Set(Get_Elapsed() >= 3.0);
    }

    private void DoMeasure(int32 InCrawlerIndex)
    {
        auto Handles = _Fixture.Crawlers[InCrawlerIndex].Handles;
        auto Body = utils_transform::Get_EntityCurrentTransform(Handles.Root);
        auto Posed = utils_procedural_body_pose::Get_Offset(Handles.BodyPose) * Body;
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
            auto Lengths = utils_procedural_leg::Get_ChainGeometry(Leg).Get_SegmentLengths();
            if (Segments.Num() == 0 || Segments.Num() != Lengths.Num())
            {
                continue;
            }

            auto Starts = TArray<FVector>();
            auto Ends = TArray<FVector>();
            auto TotalLength = 0.0;
            for (auto SegmentIndex = 0; SegmentIndex < Segments.Num(); SegmentIndex++)
            {
                auto Segment = utils_transform::Get_EntityCurrentTransform(Segments[SegmentIndex]);
                auto HalfAxis = Segment.GetRotation().GetForwardVector() * (Lengths[SegmentIndex] * 0.5);
                Starts.Add(Segment.GetLocation() - HalfAxis);
                Ends.Add(Segment.GetLocation() + HalfAxis);
                TotalLength += Lengths[SegmentIndex];
            }

            auto LegId = utils_procedural_leg::Get_Id(Leg);
            auto SegmentCount = Segments.Num();
            for (auto SegmentIndex = 0; SegmentIndex + 1 < SegmentCount; SegmentIndex++)
            {
                auto Gap = (Ends[SegmentIndex] - Starts[SegmentIndex + 1]).Size();
                if (Gap > _MaxJointGap[InCrawlerIndex])
                {
                    auto Joint = SegmentIndex + 1;
                    _MaxJointGap[InCrawlerIndex] = Gap;
                    _WorstGap[InCrawlerIndex] = f"leg {LegId}, joint {Joint} of a {SegmentCount}-segment chain";
                }
            }

            auto Foot = utils_procedural_leg::Get_Foot(Leg);
            auto Hip = Posed.TransformPosition(utils_procedural_leg::Get_Placement(Leg).Get_HipLocal());
            auto HipToFoot = (Foot.Get_Position() - Hip).Size();
            if (Foot.Get_Phase() != ECk_ProceduralLeg_FootPhase::Planted || HipToFoot >= _NearExtensionFraction * TotalLength)
            {
                continue;
            }
            auto ReachError = (Ends[SegmentCount - 1] - Foot.Get_Position()).Size();
            if (HipToFoot <= _ReachableFraction * TotalLength)
            {
                _ReachableSamples[InCrawlerIndex] += 1;
                if (ReachError > _MaxReachError[InCrawlerIndex])
                {
                    _MaxReachError[InCrawlerIndex] = ReachError;
                    _WorstReach[InCrawlerIndex] = f"leg {LegId}, hip to foot {HipToFoot :.1} of {TotalLength :.1} cm";
                }
            }
            else
            {
                _NearExtensionSamples[InCrawlerIndex] += 1;
                if (ReachError > _MaxReachErrorNearExtension[InCrawlerIndex])
                {
                    _MaxReachErrorNearExtension[InCrawlerIndex] = ReachError;
                    _WorstReachNearExtension[InCrawlerIndex] = f"leg {LegId}, hip to foot {HipToFoot :.1} of {TotalLength :.1} cm";
                }
            }
        }
    }

    UFUNCTION()
    private void Step_Verify(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        for (auto Index = 0; Index < _Fixture.Crawlers.Num(); Index++)
        {
            auto Crawler = _Fixture.Crawlers[Index];
            auto SpeciesName = ck_procedural_gym::Get_SpeciesName(Crawler.Layout.Species);
            auto MaxJointGap = _MaxJointGap[Index];
            auto MaxReachError = _MaxReachError[Index];
            auto ReachableSamples = _ReachableSamples[Index];
            auto WorstGap = _WorstGap[Index];
            auto WorstReach = _WorstReach[Index];
            auto MaxReachErrorNearExtension = _MaxReachErrorNearExtension[Index];
            auto NearExtensionSamples = _NearExtensionSamples[Index];
            auto WorstReachNearExtension = _WorstReachNearExtension[Index];
            ck::Trace(f"[LONG-CHAINS] {SpeciesName}: max joint gap {MaxJointGap :.4} cm ({WorstGap}), max reach error {MaxReachError :.4} cm ({WorstReach}), {ReachableSamples} planted reachable samples");
            ck::Trace(f"[LONG-CHAINS] {SpeciesName}: MaxReachErrorNearExtension {MaxReachErrorNearExtension :.4} cm ({WorstReachNearExtension}), {NearExtensionSamples} planted samples between 95 and 98 % of the chain length");
            Assert_True(MaxJointGap < 1.0, f"The {SpeciesName}'s posed segments stay joined end to start (worst gap {MaxJointGap :.3} cm at {WorstGap})");
            Assert_True(MaxReachError < 2.0, f"The {SpeciesName}'s chain end reaches each planted, reachable foot (worst error {MaxReachError :.3} cm at {WorstReach})");
            Assert_True(ReachableSamples > 0, f"The {SpeciesName} planted a reachable foot at least once ({ReachableSamples} samples)");
            for (auto LegIndex = 0; LegIndex < Crawler.Handles.Legs.Num(); LegIndex++)
            {
                auto Leg = Crawler.Handles.Legs[LegIndex];
                auto Rig = utils_procedural_rig::DoCast(Leg);
                Assert_True(ck::IsValid(Leg) && Rig.IsSet() && utils_procedural_rig::Get_Status(Rig.GetValue()) == ECk_ProceduralAnimation_Status::Ready,
                    f"The {SpeciesName}'s rig on leg {LegIndex} stays Ready");
            }
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
