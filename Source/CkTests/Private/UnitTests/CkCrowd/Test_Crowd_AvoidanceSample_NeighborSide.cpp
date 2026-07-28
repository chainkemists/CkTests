// Pure C++ coverage for the local neighbor-relative side-preference seam. These assertions do not
// instantiate an ECS world or processor; world-dependent sampling remains covered by Crowd AutoTests.

#include "CkCrowd/Agent/CkCrowdAgent_AvoidanceSample_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_avoidance_sample
{
    using ck::ck_crowd_agent_avoidance_sample_algorithm::CalculateNeighborSidePenalty;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::CalculateCandidateScore;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::CalculateCandidateScoreForNeighbors;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::BuildSampleCloud;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FCandidateScore;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FMinimumTimeToCollision;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FScoringParameters;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FSampleDepthResults;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::IsExpectedPreviousSamplingFrame;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::SelectWinner;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::SelectWinnerForCloud;
    using ck::FFragment_CrowdAgent_NeighborCache;

    constexpr auto kMaxSpeed = 100.0f;
    const auto kNeighborOnPositiveX = FVector{100.0f, 0.0f, 0.0f};
    const auto kCandidateLeft = FVector{0.0f, 100.0f, 0.0f};
    const auto kCandidateRight = FVector{0.0f, -100.0f, 0.0f};

    auto ScoresMatchExactly(const FCandidateScore& InLeft, const FCandidateScore& InRight) -> bool
    {
        return InLeft._DesiredVelocityPenalty == InRight._DesiredVelocityPenalty &&
            InLeft._CurrentVelocityPenalty == InRight._CurrentVelocityPenalty &&
            InLeft._TimeToImpactPenalty == InRight._TimeToImpactPenalty &&
            InLeft._SidePenalty == InRight._SidePenalty &&
            InLeft._TotalPenalty == InRight._TotalPenalty;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_TimeToCollisionContributor,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.TimeToCollisionContributor",
    kCkUnitTestFlags)

bool FCkTest_Crowd_AvoidanceSample_TimeToCollisionContributor::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_avoidance_sample;

    const auto CandidateVelocity = FVector{100.0f, 0.0f, 0.0f};
    const auto DesiredVelocity = CandidateVelocity;
    const auto CurrentVelocity = FVector::ZeroVector;
    const auto ScoringParameters = FScoringParameters{
        10.0f, 100.0f, 2.5f,
        0.0f, 0.0f, 0.0f, 2.5f,
        ECk_AvoidanceSidePreference::Disabled};

    const auto Neighbors = TArray<FCk_CrowdAgent_Neighbor>{
        FCk_CrowdAgent_Neighbor{
            FCk_Handle{},
            FVector{200.0f, 0.0f, 0.0f},
            FVector::ZeroVector,
            200.0f},
        FCk_CrowdAgent_Neighbor{
            FCk_Handle{},
            FVector{100.0f, 0.0f, 0.0f},
            FVector::ZeroVector,
            100.0f}};

    const auto ScoreWithoutContributor = CalculateCandidateScoreForNeighbors(
        CandidateVelocity,
        DesiredVelocity,
        CurrentVelocity,
        MakeArrayView(Neighbors),
        ScoringParameters);
    auto MinimumTimeToCollision = FMinimumTimeToCollision{};
    const auto ScoreWithContributor = CalculateCandidateScoreForNeighbors(
        CandidateVelocity,
        DesiredVelocity,
        CurrentVelocity,
        MakeArrayView(Neighbors),
        ScoringParameters,
        &MinimumTimeToCollision);

    TestTrue(TEXT("Optional contributor output leaves every score component bit-for-bit unchanged"),
        ScoresMatchExactly(ScoreWithoutContributor, ScoreWithContributor));
    TestEqual(TEXT("The earliest collision identifies its cache index"),
        MinimumTimeToCollision._NeighborIndex, 1);
    TestTrue(TEXT("The earliest collision retains its exact time"),
        FMath::IsNearlyEqual(MinimumTimeToCollision._Time, 0.4f));

    const auto EqualTimeNeighbors = TArray<FCk_CrowdAgent_Neighbor>{
        Neighbors[1],
        Neighbors[1]};
    auto EqualMinimum = FMinimumTimeToCollision{};
    CalculateCandidateScoreForNeighbors(
        CandidateVelocity,
        DesiredVelocity,
        CurrentVelocity,
        MakeArrayView(EqualTimeNeighbors),
        ScoringParameters,
        &EqualMinimum);
    TestEqual(TEXT("Equal collision times retain the first cache entry"),
        EqualMinimum._NeighborIndex, 0);

    const auto NoHitNeighbors = TArray<FCk_CrowdAgent_Neighbor>{
        FCk_CrowdAgent_Neighbor{
            FCk_Handle{},
            FVector{100.0f, 0.0f, 0.0f},
            FVector::ZeroVector,
            100.0f}};
    auto NoHitMinimum = FMinimumTimeToCollision{};
    CalculateCandidateScoreForNeighbors(
        FVector::ZeroVector,
        FVector::ZeroVector,
        FVector::ZeroVector,
        MakeArrayView(NoHitNeighbors),
        ScoringParameters,
        &NoHitMinimum);
    TestEqual(TEXT("No collision inside the horizon has no contributing neighbor"),
        NoHitMinimum._NeighborIndex, INDEX_NONE);
    TestEqual(TEXT("No collision preserves the sentinel time"),
        NoHitMinimum._Time, FLT_MAX);

    const auto OverlapNeighbors = TArray<FCk_CrowdAgent_Neighbor>{
        FCk_CrowdAgent_Neighbor{
            FCk_Handle{},
            FVector::ZeroVector,
            FVector::ZeroVector,
            0.0f}};
    auto OverlapMinimum = FMinimumTimeToCollision{};
    const auto OverlapScore = CalculateCandidateScoreForNeighbors(
        FVector::ZeroVector,
        FVector::ZeroVector,
        FVector::ZeroVector,
        MakeArrayView(OverlapNeighbors),
        ScoringParameters,
        &OverlapMinimum);
    TestEqual(TEXT("A static overlap remains the collision contributor"),
        OverlapMinimum._NeighborIndex, 0);
    TestTrue(TEXT("A static overlap preserves zero time to collision"),
        FMath::IsNearlyZero(OverlapMinimum._Time));
    TestTrue(TEXT("A static overlap preserves the saturated time-to-impact penalty"),
        FMath::IsNearlyEqual(OverlapScore._TimeToImpactPenalty, 25.0f));

    TestTrue(TEXT("A prior sample one stride earlier is continuous"),
        IsExpectedPreviousSamplingFrame(100, 99, 1));
    TestTrue(TEXT("A prior sample at the configured wider stride is continuous"),
        IsExpectedPreviousSamplingFrame(100, 96, 4));
    TestTrue(TEXT("A nonpositive stride clamps to one"),
        IsExpectedPreviousSamplingFrame(100, 99, 0));
    TestFalse(TEXT("A no-sampling gap is not treated as temporal continuity"),
        IsExpectedPreviousSamplingFrame(100, 98, 1));
    TestFalse(TEXT("An invalid prior frame is not temporal continuity"),
        IsExpectedPreviousSamplingFrame(100, INDEX_NONE, 1));
    TestFalse(TEXT("A future prior frame is not temporal continuity"),
        IsExpectedPreviousSamplingFrame(100, 101, 1));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_AdaptiveDepth,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.AdaptiveDepth",
    kCkUnitTestFlags)

bool FCkTest_Crowd_AvoidanceSample_AdaptiveDepth::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_avoidance_sample;

    const auto DesiredVelocity = FVector{100.0f, 0.0f, 0.0f};
    const auto CurrentVelocity = FVector{86.0f, 0.0f, 0.0f};
    const auto ScoringParameters = FScoringParameters{
        25.0f, 100.0f, 2.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        ECk_AvoidanceSidePreference::Disabled};
    const auto NeighborCache = FFragment_CrowdAgent_NeighborCache{};

    auto DepthOneCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, 1);
    const auto FirstDepthWinner = SelectWinnerForCloud(
        DepthOneCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters);
    auto DepthOneResults = FSampleDepthResults{};
    const auto AdaptiveDepthOneWinner = SelectWinner(
        DepthOneCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters, nullptr, &DepthOneResults);
    TestEqual(TEXT("Depth one preserves the first-depth candidate index"), AdaptiveDepthOneWinner._CandidateIndex, FirstDepthWinner._CandidateIndex);
    TestTrue(TEXT("Depth one preserves the first-depth penalty"),
        FMath::IsNearlyEqual(AdaptiveDepthOneWinner._Score._TotalPenalty, FirstDepthWinner._Score._TotalPenalty));
    TestEqual(TEXT("Depth one emits one trace result"), DepthOneResults.Num(), 1);

    auto RefinedCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, 3);
    const auto RefinedWinner = SelectWinner(
        RefinedCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters);
    TestTrue(TEXT("Refinement lowers the constructed coarse current-velocity penalty"),
        RefinedWinner._Score._CurrentVelocityPenalty < FirstDepthWinner._Score._CurrentVelocityPenalty);

    auto TracedCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, 5);
    auto DepthResults = FSampleDepthResults{};
    const auto TracedWinner = SelectWinner(
        TracedCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters, nullptr, &DepthResults);
    auto UntracedCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, 5);
    const auto UntracedWinner = SelectWinner(
        UntracedCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters);

    TestEqual(TEXT("Trace result count matches the effective depth"), DepthResults.Num(), 5);
    TestEqual(TEXT("Tracing leaves the returned candidate index unchanged"),
        TracedWinner._CandidateIndex, UntracedWinner._CandidateIndex);
    TestTrue(TEXT("Tracing leaves every returned score component bit-for-bit unchanged"),
        ScoresMatchExactly(TracedWinner._Score, UntracedWinner._Score));
    TestEqual(TEXT("Tracing leaves the final candidate count unchanged"),
        TracedCloud._Candidates.Num(), UntracedCloud._Candidates.Num());
    for (int32 CandidateIndex = 0; CandidateIndex < TracedCloud._Candidates.Num(); ++CandidateIndex)
    {
        TestTrue(TEXT("Tracing leaves every final candidate vector bit-for-bit unchanged"),
            TracedCloud._Candidates[CandidateIndex] == UntracedCloud._Candidates[CandidateIndex]);
    }

    TestTrue(TEXT("Depth one records the original bias centre"),
        DepthResults[0]._Centre == DesiredVelocity * 0.5f);
    TestTrue(TEXT("Depth one records the original cloud radius"),
        DepthResults[0]._Radius == 50.0f);
    for (int32 DepthIndex = 1; DepthIndex < DepthResults.Num(); ++DepthIndex)
    {
        TestTrue(TEXT("Each refinement recentres on the prior depth winner"),
            DepthResults[DepthIndex]._Centre == DepthResults[DepthIndex - 1]._WinnerVelocity);
        TestTrue(TEXT("Each refinement halves the prior depth radius"),
            DepthResults[DepthIndex]._Radius == DepthResults[DepthIndex - 1]._Radius * 0.5f);
    }

    const auto& FinalDepthResult = DepthResults.Last();
    TestEqual(TEXT("Final trace result matches the returned winner index"),
        FinalDepthResult._Winner._CandidateIndex, TracedWinner._CandidateIndex);
    TestTrue(TEXT("Final trace result matches the returned winner velocity"),
        FinalDepthResult._WinnerVelocity == TracedCloud._Candidates[TracedWinner._CandidateIndex]);
    TestTrue(TEXT("Final trace result matches every returned score component"),
        ScoresMatchExactly(FinalDepthResult._Winner._Score, TracedWinner._Score));

    auto NonPositiveDepthCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, 0);
    auto NonPositiveDepthResults = FSampleDepthResults{};
    const auto NonPositiveDepthWinner = SelectWinner(
        NonPositiveDepthCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters, nullptr, &NonPositiveDepthResults);
    TestEqual(TEXT("Nonpositive depth clamps to one"), NonPositiveDepthWinner._CandidateIndex, FirstDepthWinner._CandidateIndex);
    TestTrue(TEXT("Nonpositive depth preserves depth-one penalty"),
        FMath::IsNearlyEqual(NonPositiveDepthWinner._Score._TotalPenalty, FirstDepthWinner._Score._TotalPenalty));
    TestEqual(TEXT("Nonpositive depth emits one trace result"), NonPositiveDepthResults.Num(), 1);

    auto NegativeDepthCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, -1);
    auto NegativeDepthResults = FSampleDepthResults{};
    const auto NegativeDepthWinner = SelectWinner(
        NegativeDepthCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters, nullptr, &NegativeDepthResults);
    TestEqual(TEXT("Negative depth clamps to one"), NegativeDepthWinner._CandidateIndex, FirstDepthWinner._CandidateIndex);
    TestTrue(TEXT("Negative depth preserves depth-one penalty"),
        FMath::IsNearlyEqual(NegativeDepthWinner._Score._TotalPenalty, FirstDepthWinner._Score._TotalPenalty));
    TestEqual(TEXT("Negative depth emits one trace result"), NegativeDepthResults.Num(), 1);

    auto ExcessiveDepthCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, 99);
    TestEqual(TEXT("Excessive depth clamps to the configured maximum"), ExcessiveDepthCloud._Depth, 8);
    auto ExcessiveDepthResults = FSampleDepthResults{};
    SelectWinner(
        ExcessiveDepthCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters, nullptr, &ExcessiveDepthResults);
    TestEqual(TEXT("Excessive depth emits the clamped number of trace results"),
        ExcessiveDepthResults.Num(), 8);

    auto BoundedCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 2, 5);
    SelectWinner(BoundedCloud, DesiredVelocity, CurrentVelocity, NeighborCache, ScoringParameters);
    for (const auto& Candidate : BoundedCloud._Candidates)
    {
        TestTrue(TEXT("Every final-depth candidate respects max speed"),
            Candidate.SizeSquared2D() <= FMath::Square(100.0f + KINDA_SMALL_NUMBER));
    }

    auto OverspeedCentreCloud = BuildSampleCloud(FVector{250.0f, 0.0f, 0.0f}, 100.0f, 0.5f, 8, 2, 1);
    TestFalse(TEXT("An overspeed bias centre is not admitted"), OverspeedCentreCloud._Candidates.Contains(FVector{125.0f, 0.0f, 0.0f}));
    for (const auto& Candidate : OverspeedCentreCloud._Candidates)
    {
        TestTrue(TEXT("Every candidate respects max speed when the desired velocity is overspeed"),
            Candidate.SizeSquared2D() <= FMath::Square(100.0f + KINDA_SMALL_NUMBER));
    }

    AddExpectedError(
        TEXT("Invalid crowd avoidance sample"),
        EAutomationExpectedErrorFlags::Contains,
        4);
    const auto InvalidDivisionsCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 0, 2, 1);
    const auto InvalidRingsCloud = BuildSampleCloud(DesiredVelocity, 100.0f, 0.5f, 8, 0, 1);
    TestEqual(TEXT("Zero angular divisions fail closed"), InvalidDivisionsCloud._Candidates.Num(), 0);
    TestEqual(TEXT("Zero rings fail closed"), InvalidRingsCloud._Candidates.Num(), 0);

    auto SideScoringParameters = ScoringParameters;
    SideScoringParameters._WeightSide = 0.75f;
    SideScoringParameters._SidePreference = ECk_AvoidanceSidePreference::PassLeft;
    const auto EmptyNeighborScore = CalculateCandidateScore(
        DesiredVelocity, DesiredVelocity, CurrentVelocity, NeighborCache, SideScoringParameters);
    TestTrue(TEXT("Side scoring with no neighbors stays finite"), FMath::IsFinite(EmptyNeighborScore._TotalPenalty));
    TestTrue(TEXT("Side scoring with no neighbors contributes no side penalty"), FMath::IsNearlyZero(EmptyNeighborScore._SidePenalty));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_NeighborSidePassLeft,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.NeighborSide.PassLeft",
    kCkUnitTestFlags)

bool FCkTest_Crowd_AvoidanceSample_NeighborSidePassLeft::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_avoidance_sample;

    const auto LeftPenalty = CalculateNeighborSidePenalty(
        kCandidateLeft, kNeighborOnPositiveX, kMaxSpeed, ECk_AvoidanceSidePreference::PassLeft);
    const auto RightPenalty = CalculateNeighborSidePenalty(
        kCandidateRight, kNeighborOnPositiveX, kMaxSpeed, ECk_AvoidanceSidePreference::PassLeft);

    TestTrue(TEXT("PassLeft accepts +Y for a neighbor on +X"), FMath::IsNearlyZero(LeftPenalty));
    TestTrue(TEXT("PassLeft penalizes -Y for a neighbor on +X"), FMath::IsNearlyEqual(RightPenalty, 1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_NeighborSidePassRightMirror,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.NeighborSide.PassRightMirror",
    kCkUnitTestFlags)

bool FCkTest_Crowd_AvoidanceSample_NeighborSidePassRightMirror::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_avoidance_sample;

    const auto LeftPenalty = CalculateNeighborSidePenalty(
        kCandidateLeft, kNeighborOnPositiveX, kMaxSpeed, ECk_AvoidanceSidePreference::PassRight);
    const auto RightPenalty = CalculateNeighborSidePenalty(
        kCandidateRight, kNeighborOnPositiveX, kMaxSpeed, ECk_AvoidanceSidePreference::PassRight);

    TestTrue(TEXT("PassRight is the exact mirror: it penalizes +Y"), FMath::IsNearlyEqual(LeftPenalty, 1.0f));
    TestTrue(TEXT("PassRight is the exact mirror: it accepts -Y"), FMath::IsNearlyZero(RightPenalty));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_NeighborSideInvalidAndPlanar,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.NeighborSide.InvalidAndPlanar",
    kCkUnitTestFlags)

bool FCkTest_Crowd_AvoidanceSample_NeighborSideInvalidAndPlanar::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_avoidance_sample;

    const auto DisabledPenalty = CalculateNeighborSidePenalty(
        kCandidateRight, kNeighborOnPositiveX, kMaxSpeed, ECk_AvoidanceSidePreference::Disabled);
    TestTrue(TEXT("Disabled always returns zero"), FMath::IsNearlyZero(DisabledPenalty));

    const auto ZeroOffsetPenalty = CalculateNeighborSidePenalty(
        kCandidateRight, FVector::ZeroVector, kMaxSpeed, ECk_AvoidanceSidePreference::PassLeft);
    const auto ZeroSpeedPenalty = CalculateNeighborSidePenalty(
        kCandidateRight, kNeighborOnPositiveX, 0.0f, ECk_AvoidanceSidePreference::PassLeft);
    const auto NegativeSpeedPenalty = CalculateNeighborSidePenalty(
        kCandidateRight, kNeighborOnPositiveX, -kMaxSpeed, ECk_AvoidanceSidePreference::PassLeft);
    AddExpectedError(
        TEXT("Invalid crowd avoidance side preference"),
        EAutomationExpectedErrorFlags::Contains,
        2);
    const auto InvalidPreferencePenalty = CalculateNeighborSidePenalty(
        kCandidateRight,
        kNeighborOnPositiveX,
        kMaxSpeed,
        static_cast<ECk_AvoidanceSidePreference>(255));
    TestTrue(TEXT("Zero XY offset returns zero"), FMath::IsNearlyZero(ZeroOffsetPenalty));
    TestTrue(TEXT("Zero max speed returns zero"), FMath::IsNearlyZero(ZeroSpeedPenalty));
    TestTrue(TEXT("Negative max speed returns zero"), FMath::IsNearlyZero(NegativeSpeedPenalty));
    TestTrue(TEXT("Unknown side preference fails closed"), FMath::IsNearlyZero(InvalidPreferencePenalty));

    const auto BaselinePenalty = CalculateNeighborSidePenalty(
        kCandidateRight, kNeighborOnPositiveX, kMaxSpeed, ECk_AvoidanceSidePreference::PassLeft);
    const auto ScaledOffsetPenalty = CalculateNeighborSidePenalty(
        kCandidateRight, FVector{10000.0f, 0.0f, 9000.0f}, kMaxSpeed, ECk_AvoidanceSidePreference::PassLeft);
    TestTrue(TEXT("Offset magnitude and Z do not affect planar orientation"),
        FMath::IsNearlyEqual(ScaledOffsetPenalty, BaselinePenalty));

    const auto OverspeedPenalty = CalculateNeighborSidePenalty(
        FVector{0.0f, -1000.0f, 0.0f}, kNeighborOnPositiveX, kMaxSpeed, ECk_AvoidanceSidePreference::PassLeft);
    TestTrue(TEXT("Penalty clamps to the normalized range"), OverspeedPenalty >= 0.0f && OverspeedPenalty <= 1.0f);
    TestTrue(TEXT("Overspeed opposing candidate clamps at one"), FMath::IsNearlyEqual(OverspeedPenalty, 1.0f));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
