// Pure coverage for the sampler-to-actuator contract. World-dependent avoidance behavior remains
// covered by the Crowd AutoTests.

#include <limits>

#include "CkCrowd/Agent/CkCrowdAgent_AvoidanceSample_Algorithm.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_crowd_avoidance_reachability
{
    using ck::ck_crowd_agent_accel_clamp_algorithm::ProjectVelocity;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FReachabilityParameters;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FScoringParameters;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FSampleCloud;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::FSampleDepthResults;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::BuildSampleCloud;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::MakeReachabilityParameters;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::ResolveScoredCandidateVelocity;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::SelectWinner;
    using ck::ck_crowd_agent_avoidance_sample_algorithm::SelectWinnerForCloud;
    using ck::FFragment_CrowdAgent_NeighborCache;

    constexpr auto kMaxSpeed = 100.0f;

    auto VelocityAtDegrees(const float InDegrees) -> FVector
    {
        const auto Angle = FMath::DegreesToRadians(InDegrees);
        return FVector{
            kMaxSpeed * FMath::Cos(Angle),
            kMaxSpeed * FMath::Sin(Angle),
            0.0f};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_ReachabilityProjection,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.ReachabilityProjection",
    kCkUnitTestFlags)

bool FCkTest_Crowd_AvoidanceSample_ReachabilityProjection::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_avoidance_reachability;

    const auto QuarterTurn = ProjectVelocity(
        FVector{kMaxSpeed, 0.0f, 0.0f},
        FVector{0.0f, kMaxSpeed, 0.0f},
        kMaxSpeed,
        200.0f,
        4.0f,
        0.05f);
    const auto ExpectedTurn = FVector{
        kMaxSpeed * FMath::Cos(0.2f),
        kMaxSpeed * FMath::Sin(0.2f),
        0.0f};
    TestTrue(TEXT("Projection uses the same turn-rate-limited velocity as AccelClamp"),
        QuarterTurn.Equals(ExpectedTurn, 0.001f));

    const auto TurnLimitedCloseGoal = ProjectVelocity(
        FVector{kMaxSpeed, 0.0f, 0.0f},
        FVector{0.0f, 60.0f, 0.0f},
        kMaxSpeed,
        200.0f,
        4.0f,
        0.05f);
    const auto ImmediateDirection = ProjectVelocity(
        FVector{kMaxSpeed, 0.0f, 0.0f},
        FVector{0.0f, 60.0f, 0.0f},
        kMaxSpeed,
        200.0f,
        4.0f,
        0.05f,
        true);
    TestTrue(TEXT("Ordinary close-goal movement remains turn limited"),
        TurnLimitedCloseGoal.X > 0.0f && TurnLimitedCloseGoal.Y < ImmediateDirection.Y);
    TestTrue(TEXT("Close-goal strafe bypasses only the angular turn clamp"),
        ImmediateDirection.Equals(FVector{0.0f, 90.0f, 0.0f}, 0.001f));
    TestTrue(TEXT("Close-goal strafe still respects the maximum scalar speed"),
        ImmediateDirection.Size() <= kMaxSpeed + KINDA_SMALL_NUMBER);
    TestTrue(TEXT("Close-goal strafe still respects the scalar acceleration budget"),
        FMath::Abs(ImmediateDirection.Size() - kMaxSpeed) <= 200.0f * 0.05f + KINDA_SMALL_NUMBER);

    const auto FirstFrame = ProjectVelocity(
        FVector::ZeroVector,
        FVector{0.0f, kMaxSpeed, 0.0f},
        kMaxSpeed,
        200.0f,
        4.0f,
        0.05f);
    TestTrue(TEXT("Projection preserves target-aligned first-frame acceleration"),
        FirstFrame.Equals(FVector{0.0f, 10.0f, 0.0f}, 0.001f));

    const auto IdleBraking = ProjectVelocity(
        FVector{kMaxSpeed, 0.0f, 0.0f},
        FVector::ZeroVector,
        kMaxSpeed,
        200.0f,
        4.0f,
        0.05f);
    TestTrue(TEXT("Projection preserves straight idle braking"),
        IdleBraking.Equals(FVector{90.0f, 0.0f, 0.0f}, 0.001f));

    AddExpectedError(
        TEXT("Invalid crowd acceleration projection inputs"),
        EAutomationExpectedErrorFlags::Contains,
        8);
    const auto InvalidProjection = ProjectVelocity(
        FVector{kMaxSpeed, 0.0f, 0.0f},
        FVector{0.0f, kMaxSpeed, 0.0f},
        kMaxSpeed,
        200.0f,
        4.0f,
        -0.05f);
    TestTrue(TEXT("Invalid projection inputs fail closed"),
        InvalidProjection.IsNearlyZero());

    const auto NotANumber = std::numeric_limits<float>::quiet_NaN();
    const auto Infinity = std::numeric_limits<float>::infinity();
    const auto InvalidLastVelocity = ProjectVelocity(
        FVector{NotANumber, 0.0f, 0.0f},
        FVector{0.0f, kMaxSpeed, 0.0f},
        kMaxSpeed,
        200.0f,
        4.0f,
        0.05f);
    const auto InvalidRequestedVelocity = ProjectVelocity(
        FVector{kMaxSpeed, 0.0f, 0.0f},
        FVector{Infinity, 0.0f, 0.0f},
        kMaxSpeed,
        200.0f,
        4.0f,
        0.05f);
    const auto InvalidConstraint = ProjectVelocity(
        FVector{kMaxSpeed, 0.0f, 0.0f},
        FVector{0.0f, kMaxSpeed, 0.0f},
        Infinity,
        200.0f,
        4.0f,
        0.05f);
    TestTrue(TEXT("A non-finite last velocity fails closed"),
        InvalidLastVelocity.IsNearlyZero());
    TestTrue(TEXT("A non-finite requested velocity fails closed"),
        InvalidRequestedVelocity.IsNearlyZero());
    TestTrue(TEXT("A non-finite constraint fails closed"),
        InvalidConstraint.IsNearlyZero());

    const auto EnabledReachability = MakeReachabilityParameters(
        ECk_AccelClampMode::Enabled,
        FVector{kMaxSpeed, 0.0f, 0.0f},
        200.0f,
        4.0f,
        0.05f);
    const auto DisabledReachability = MakeReachabilityParameters(
        ECk_AccelClampMode::Disabled,
        FVector{kMaxSpeed, 0.0f, 0.0f},
        200.0f,
        4.0f,
        0.05f);
    TestTrue(TEXT("Enabled AccelClamp mode enables reachable scoring"),
        EnabledReachability._Enabled);
    TestFalse(TEXT("Disabled AccelClamp mode preserves raw scoring"),
        DisabledReachability._Enabled);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_Crowd_AvoidanceSample_ReachabilityChangesWinner,
    "CkTests.UnitTests.CkCrowd.AvoidanceSample.ReachabilityChangesWinner",
    kCkUnitTestFlags)

bool FCkTest_Crowd_AvoidanceSample_ReachabilityChangesWinner::RunTest(const FString& Parameters)
{
    using namespace ck_tests_crowd_avoidance_reachability;

    const auto DesiredVelocity = VelocityAtDegrees(90.0f);
    const auto CurrentVelocity = VelocityAtDegrees(0.0f);
    const auto NeighborCache = FFragment_CrowdAgent_NeighborCache{};
    auto Cloud = FSampleCloud{};
    Cloud._Candidates.Add(VelocityAtDegrees(10.0f));
    Cloud._Candidates.Add(VelocityAtDegrees(90.0f));

    const auto RawParameters = FScoringParameters{
        25.0f,
        kMaxSpeed,
        2.0f,
        2.0f,
        2.0f,
        0.0f,
        0.0f,
        ECk_AvoidanceSidePreference::Disabled};
    const auto RawWinner = SelectWinnerForCloud(
        Cloud,
        DesiredVelocity,
        CurrentVelocity,
        NeighborCache,
        RawParameters);
    TestEqual(TEXT("Raw scoring prefers the unreachable desired-heading target"),
        RawWinner._CandidateIndex,
        1);

    auto ReachableParameters = RawParameters;
    ReachableParameters._Reachability = FReachabilityParameters{
        true,
        CurrentVelocity,
        1000.0f,
        4.0f,
        PI / 36.0f};
    const auto ReachableWinner = SelectWinnerForCloud(
        Cloud,
        DesiredVelocity,
        CurrentVelocity,
        NeighborCache,
        ReachableParameters);
    TestEqual(TEXT("Reachable scoring can select a different raw command"),
        ReachableWinner._CandidateIndex,
        0);
    TestTrue(TEXT("The returned scored velocity is the projected selected command"),
        ReachableWinner._ScoredVelocity.Equals(
            ResolveScoredCandidateVelocity(
                Cloud._Candidates[ReachableWinner._CandidateIndex],
                ReachableParameters),
            0.001f));

    auto RefinedCloud = BuildSampleCloud(
        DesiredVelocity,
        kMaxSpeed,
        0.5f,
        8,
        2,
        3);
    auto RefinedDepths = FSampleDepthResults{};
    SelectWinner(
        RefinedCloud,
        DesiredVelocity,
        CurrentVelocity,
        NeighborCache,
        ReachableParameters,
        nullptr,
        &RefinedDepths);
    TestEqual(TEXT("Reachable refinement records every configured depth"),
        RefinedDepths.Num(),
        3);
    if (RefinedDepths.Num() == 3)
    {
        TestFalse(TEXT("The constructed first-depth raw winner is not immediately reachable"),
            RefinedDepths[0]._WinnerVelocity.Equals(
                RefinedDepths[0]._WinnerScoredVelocity,
                0.001f));
        for (int32 DepthIndex = 1; DepthIndex < RefinedDepths.Num(); ++DepthIndex)
        {
            TestTrue(TEXT("Reachable refinement recentres on the prior actuator output"),
                RefinedDepths[DepthIndex]._Centre.Equals(
                    RefinedDepths[DepthIndex - 1]._WinnerScoredVelocity,
                    0.001f));
        }
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
