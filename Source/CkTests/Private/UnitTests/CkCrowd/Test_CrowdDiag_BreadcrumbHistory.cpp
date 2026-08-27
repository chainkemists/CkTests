#include "CkCrowd/Agent/CkCrowdAgent_DiagBreadcrumb_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_Diag_BreadcrumbHistory_IncrementalBounded,
    "CkTests.UnitTests.CkCrowd.Diag.BreadcrumbHistory.IncrementalBounded",
    kCkUnitTestFlags)

bool FCkTest_Crowd_Diag_BreadcrumbHistory_IncrementalBounded::RunTest(const FString& Parameters)
{
    using namespace ck::crowd_diag_breadcrumb;

    constexpr auto TrackGeneration = 7;
    constexpr auto SampleSpacing = 10.0f;
    constexpr auto Capacity = SegmentsPerChunk * MaximumRetainedChunks;

    TestEqual(TEXT("raw recorder history stays unchanged below its ceiling"),
        GetRecorderTrimCount(DefaultMaximumRecordedSamples, DefaultMaximumRecordedSamples),
        0);
    TestEqual(TEXT("raw recorder history trims to its lower watermark in one batch"),
        GetRecorderTrimCount(DefaultMaximumRecordedSamples + 1, DefaultMaximumRecordedSamples),
        DefaultMaximumRecordedSamples / 4 + 1);

    auto Samples = TArray<FVector>{};
    Samples.Reserve(Capacity * 2 + 5);
    for (auto Index = 1; Index <= Capacity * 2 + 5; ++Index)
    { Samples.Add(FVector{Index * SampleSpacing, 0.0f, 0.0f}); }

    auto State = FHistoryState{};
    auto SimulatedChunkCount = 0;
    auto ConsumedSamples = 0;
    auto AppendedSegments = 0;
    auto EvictedChunks = 0;

    while (State._NextSampleIndex < Samples.Num())
    {
        const auto Range = PrepareUpdate(Samples.Num(), TrackGeneration, FVector::ZeroVector, State);
        TestTrue(TEXT("Only the first update resets retained geometry"),
            ConsumedSamples > 0 || Range._NeedsGeometryReset);

        for (auto SampleIndex = Range._BeginSampleIndex; SampleIndex < Range._EndSampleIndex; ++SampleIndex)
        {
            const auto Plan = PlanSample(Samples[SampleIndex], State);
            ++ConsumedSamples;
            if (Plan._ShouldAppend)
            { ++AppendedSegments; }
            if (Plan._ShouldStartChunk)
            { ++SimulatedChunkCount; }
            if (Plan._ShouldEvictOldestChunk)
            {
                --SimulatedChunkCount;
                ++EvictedChunks;
            }
            State = Plan._NextState;
        }
    }

    TestEqual(TEXT("Every source sample is consumed exactly once"), ConsumedSamples, Samples.Num());
    TestEqual(TEXT("Every moving sample contributes one segment"), AppendedSegments, Samples.Num());
    TestEqual(TEXT("The cursor ends at the source tail"), State._NextSampleIndex, Samples.Num());
    TestEqual(TEXT("The retained chunk count stays at the production ceiling"),
        SimulatedChunkCount,
        MaximumRetainedChunks);
    TestEqual(TEXT("The state and retained storage agree"), State._RetainedChunkCount, SimulatedChunkCount);
    TestTrue(TEXT("Long histories evict completed chunks"), EvictedChunks > 0);
    TestTrue(TEXT("The retained tail ends at the newest sample"),
        State._PreviousPosition.Equals(Samples.Last()));

    const auto UnchangedRange = PrepareUpdate(Samples.Num(), TrackGeneration, FVector::ZeroVector, State);
    TestEqual(TEXT("An unchanged history has no samples to revisit"),
        UnchangedRange._BeginSampleIndex,
        UnchangedRange._EndSampleIndex);
    TestFalse(TEXT("An unchanged history does not reset geometry"), UnchangedRange._NeedsGeometryReset);

    Samples.Add(Samples.Last() + FVector{SampleSpacing, 0.0f, 0.0f});
    const auto AppendedRange = PrepareUpdate(Samples.Num(), TrackGeneration, FVector::ZeroVector, State);
    TestEqual(TEXT("Appending one sample schedules only that sample"),
        AppendedRange._EndSampleIndex - AppendedRange._BeginSampleIndex,
        1);
    const auto AppendedPlan = PlanSample(Samples.Last(), State);
    TestTrue(TEXT("The new moving sample appends one retained segment"), AppendedPlan._ShouldAppend);
    State = AppendedPlan._NextState;
    TestEqual(TEXT("The cursor advances by one without replaying history"),
        State._NextSampleIndex,
        Samples.Num());
    TestTrue(TEXT("The newest sample remains the retained tail"),
        State._PreviousPosition.Equals(Samples.Last()));
    TestTrue(TEXT("The chunk ceiling remains enforced after another append"),
        State._RetainedChunkCount <= MaximumRetainedChunks);

    const auto NewTrackRange = PrepareUpdate(0, TrackGeneration + 1, FVector{50.0f, 60.0f, 70.0f}, State);
    TestTrue(TEXT("A new Track generation explicitly resets old geometry"),
        NewTrackRange._NeedsGeometryReset);
    TestEqual(TEXT("A new Track generation resets the sample cursor"), State._NextSampleIndex, 0);
    TestEqual(TEXT("A new Track generation resets retained chunk accounting"), State._RetainedChunkCount, 0);
    TestTrue(TEXT("A new Track generation seeds its own start position"),
        State._PreviousPosition.Equals(FVector{50.0f, 60.0f, 70.0f}));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
