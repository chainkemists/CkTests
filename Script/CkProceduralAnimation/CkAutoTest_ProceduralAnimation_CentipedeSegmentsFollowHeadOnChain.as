// Language=angelscript

class UCk_AutoTest_ProceduralAnimation_CentipedeSegmentsFollowHeadOnChain : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 14.0f;
    default _AutoStageOriginField = false;
    private FCkProceduralAnimationGym_Fixture _Fixture;
    private FVector _Origin = FVector(120000.0, 560000.0, 600.0);
    private TArray<FVector> _HeadPath;
    private TArray<FVector> _HeadSamples;
    private TArray<FVector> _FirstSegmentSamples;
    private TArray<FVector> _SecondSegmentSamples;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Roster = TArray<ECkProceduralAnimationGym_Species>();
        Roster.Add(ECkProceduralAnimationGym_Species::Centipede3);
        if (_Fixture.Create_WithRoster(InHandle, _Origin, ECkProceduralAnimationGym_Course::Flat, Roster, false) == false)
        {
            FinishFailure("The isolated centipede floor fixture could not be created");
            return;
        }
        Add_Step_WaitUntil("centipede ready", n"Check_Ready", 1200);
        Add_Step_WaitUntil("head has walked three spacings", n"Check_Walked");
        for (auto Index = 0; Index < 6; Index++)
        {
            Add_Step("sample", n"Do_Sample");
            Add_Step_WaitFrames("advance", 1);
        }
        Add_Step("assert", n"Do_Assert");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_Ready(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update(true, false);
        if (_Fixture.CompositionError.IsEmpty() == false)
        {
            FinishFailure(f"The centipede could not be composed: {_Fixture.CompositionError}");
            return;
        }
        auto Ready = _Fixture.Get_AllReady();
        if (Ready)
        {
            auto Chain = _Fixture.Crawlers[0].Handles.Chain;
            Assert_Equals_Int(utils_chain::Get_NumLinks(Chain), 2, "The head's chain holds both followers");
            auto Links = utils_chain::Get_Links(Chain);
            if (Links.Num() == 2)
            {
                Assert_True(utils_chain_link::Get_Orientation(Links[0]) == ECk_Chain_LinkOrientation::CopyHead,
                    "The first follower copies the head's recorded frame");
                Assert_Equals_Float(utils_chain_link::Get_DistanceFromHeadCm(Links[0]), 65.0, 0.01,
                    "The first follower sits one segment spacing behind the head");
                Assert_Equals_Float(utils_chain_link::Get_DistanceFromHeadCm(Links[1]), 130.0, 0.01,
                    "The second follower sits two segment spacings behind the head");
            }
        }
        auto Result = OutResult;
        Result.Set(Ready);
    }

    UFUNCTION()
    private void Check_Walked(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        _Fixture.Update(true, false);
        auto HeadLocation = utils_transform::Get_EntityCurrentLocation(_Fixture.Crawlers[0].Handles.Root);
        _HeadPath.Add(HeadLocation);
        auto Walked = (HeadLocation - _Fixture.Crawlers[0].Layout.Start).Size();
        auto Result = OutResult;
        Result.Set(Walked >= 3.0 * ck_procedural_gym_assets::CentipedeSegmentSpacing + 50.0);
    }

    UFUNCTION()
    private void Do_Sample(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _Fixture.Update(true, false);
        auto HeadLocation = utils_transform::Get_EntityCurrentLocation(_Fixture.Crawlers[0].Handles.Root);
        _HeadPath.Add(HeadLocation);
        _HeadSamples.Add(HeadLocation);
        _FirstSegmentSamples.Add(utils_transform::Get_EntityCurrentLocation(_Fixture.Crawlers[0].Handles.Segments[0].Root));
        _SecondSegmentSamples.Add(utils_transform::Get_EntityCurrentLocation(_Fixture.Crawlers[0].Handles.Segments[1].Root));
    }

    float Get_NearestHeadPathDistance(FVector InLocation) const
    {
        auto Nearest = 1000000.0;
        for (auto HeadLocation : _HeadPath)
        {
            Nearest = Math::Min(Nearest, (HeadLocation - InLocation).Size());
        }
        return Nearest;
    }

    UFUNCTION()
    private void Do_Assert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Spacing = ck_procedural_gym_assets::CentipedeSegmentSpacing;
        auto WorstSpacingError = 0.0;
        auto WorstPathOffset = 0.0;
        for (auto Index = 0; Index < _HeadSamples.Num(); Index++)
        {
            auto FirstGap = (_FirstSegmentSamples[Index] - _HeadSamples[Index]).Size();
            auto SecondGap = (_SecondSegmentSamples[Index] - _FirstSegmentSamples[Index]).Size();
            auto FirstOffset = Get_NearestHeadPathDistance(_FirstSegmentSamples[Index]);
            auto SecondOffset = Get_NearestHeadPathDistance(_SecondSegmentSamples[Index]);
            WorstSpacingError = Math::Max(WorstSpacingError, Math::Max(Math::Abs(FirstGap - Spacing), Math::Abs(SecondGap - Spacing)));
            WorstPathOffset = Math::Max(WorstPathOffset, Math::Max(FirstOffset, SecondOffset));
            Assert_Equals_Float(FirstGap, Spacing, 3.0, f"Sample {Index}: the first follower trails the head by one spacing");
            Assert_Equals_Float(SecondGap, Spacing, 3.0, f"Sample {Index}: the second follower trails the first by one spacing");
            Assert_True(FirstOffset <= 10.0, f"Sample {Index}: the first follower lies on the head's path ({FirstOffset :.2} cm off)");
            Assert_True(SecondOffset <= 10.0, f"Sample {Index}: the second follower lies on the head's path ({SecondOffset :.2} cm off)");
        }
        auto Crawler = _Fixture.Crawlers[0];
        for (auto SegmentIndex = 0; SegmentIndex < Crawler.Handles.Segments.Num(); SegmentIndex++)
        {
            Assert_True(utils_procedural_gait::Get_Status(Crawler.Handles.Segments[SegmentIndex].Gait) == ECk_ProceduralAnimation_Status::Ready,
                f"Follower {SegmentIndex}'s gait stays ready");
        }
        auto Replanted = Crawler.Get_ReplantedCount();
        ck::Trace(f"[CENTIPEDE-CHAIN] {_HeadSamples.Num()} samples, worst spacing error {WorstSpacingError :.2} cm, worst path offset {WorstPathOffset :.2} cm, {Replanted}/{Crawler.Layout.LegCount} legs replanted");
        Assert_True(Replanted >= 4, f"Feet are stepping on at least one full segment ({Replanted} legs replanted)");
        Assert_False(Crawler.Evidence.InvalidOutput, "The centipede produced no invalid output");
        _Fixture.Request_Destroy();
        FinishSuccess();
    }
}
