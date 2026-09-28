#include "CkProceduralAnimation/Core/CkProceduralChainClearance.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_chain_clearance
{
    constexpr auto Tolerance = 1.0e-4;
    const auto Hip = FVector{0.0, 0.0, 0.0};
    const auto Foot = FVector{100.0, 0.0, 0.0};
    const auto Pole = FVector{50.0, 40.0, 0.0};

    auto
        Get_IsSameBits(
            const FVector& InA,
            const FVector& InB)
        -> bool
    {
        return FMemory::Memcmp(&InA, &InB, sizeof(FVector)) == 0;
    }

    auto
        Get_Order(
            float InLastClearDegrees)
        -> TArray<float>
    {
        auto Order = TArray<float>{};
        Order.Init(TNumericLimits<float>::Max(), static_cast<int32>(UE_ARRAY_COUNT(ck::ProceduralPoleSwivelFanDegrees)));
        const auto Count = ck::Get_ProceduralPoleSwivelOrder(InLastClearDegrees, Order);
        Order.SetNum(FMath::Clamp(Count, 0, Order.Num()));
        return Order;
    }

    auto
        Get_OrderText(
            const TArray<float>& InOrder)
        -> FString
    {
        return FString::JoinBy(InOrder, TEXT(", "), [](float InDegrees)
        {
            return FString::Printf(TEXT("%.0f"), InDegrees);
        });
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceSwivelKeepsTheDistanceToTheAxisTest,
    "Ck.ProceduralAnimation.ChainClearance.SwivelKeepsTheDistanceToTheAxis",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceSwivelKeepsTheDistanceToTheAxisTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto Axis = (Foot - Hip).GetSafeNormal();
    for (const auto Degrees : ck::ProceduralPoleSwivelFanDegrees)
    {
        const auto Swivelled = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, Degrees);
        const auto Along = FVector::DotProduct(Swivelled - Hip, Axis);
        const auto FromAxis = (Swivelled - Hip - Axis * Along).Size();
        TestTrue(FString::Printf(TEXT("At %.0f degrees the pole stays 40 cm from the axis (got %.6f)"), Degrees, FromAxis),
            FMath::IsNearlyEqual(FromAxis, 40.0, Tolerance));
        TestTrue(FString::Printf(TEXT("At %.0f degrees the pole projects 50 cm along the axis (got %.6f)"), Degrees, Along),
            FMath::IsNearlyEqual(Along, 50.0, Tolerance));
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceSwivelSignIsRightHandedTest,
    "Ck.ProceduralAnimation.ChainClearance.SwivelSignIsRightHanded",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceSwivelSignIsRightHandedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto Swivelled = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 90.0f);
    TestTrue(FString::Printf(TEXT("+90 degrees about +X takes (50, 40, 0) to (50, 0, 40) (got %s)"), *Swivelled.ToString()),
        Swivelled.Equals(FVector{50.0, 0.0, 40.0}, Tolerance));

    const auto Back = ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, -90.0f);
    TestTrue(FString::Printf(TEXT("-90 degrees about +X takes (50, 40, 0) to (50, 0, -40) (got %s)"), *Back.ToString()),
        Back.Equals(FVector{50.0, 0.0, -40.0}, Tolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceSwivelZeroAndDegenerateReturnInputTest,
    "Ck.ProceduralAnimation.ChainClearance.SwivelZeroAndDegenerateReturnInput",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceSwivelZeroAndDegenerateReturnInputTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto NaN = std::numeric_limits<double>::quiet_NaN();

    TestTrue(TEXT("0 degrees returns the input pole"), Get_IsSameBits(ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 0.0f), Pole));
    TestTrue(TEXT("A hip on the foot returns the input pole"),
        Get_IsSameBits(ck::ComputeProceduralPoleSwivel(Foot, Foot, Pole, 60.0f), Pole));

    const auto NaNPole = FVector{NaN, 40.0, 0.0};
    TestTrue(TEXT("A NaN pole returns the input pole"), Get_IsSameBits(ck::ComputeProceduralPoleSwivel(Hip, Foot, NaNPole, 60.0f), NaNPole));

    TestTrue(TEXT("Positive control: 60 degrees moves the pole"),
        NOT ck::ComputeProceduralPoleSwivel(Hip, Foot, Pole, 60.0f).Equals(Pole, 1.0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceOrderTriesLastClearFirstTest,
    "Ck.ProceduralAnimation.ChainClearance.OrderTriesLastClearFirst",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceOrderTriesLastClearFirstTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_chain_clearance;

    const auto Fan = TArray<float>{0.0f, 30.0f, -30.0f, 60.0f, -60.0f, 90.0f, -90.0f, 120.0f, -120.0f, 150.0f, -150.0f};

    const auto AfterSixty = Get_Order(60.0f);
    TestTrue(FString::Printf(TEXT("Last clear 60 orders 60, 0, 30, -30, -60, 90, -90, 120, -120, 150, -150 (got %s)"),
        *Get_OrderText(AfterSixty)),
        AfterSixty == TArray<float>{60.0f, 0.0f, 30.0f, -30.0f, -60.0f, 90.0f, -90.0f, 120.0f, -120.0f, 150.0f, -150.0f});

    const auto AfterOneFifty = Get_Order(150.0f);
    TestTrue(FString::Printf(TEXT("Last clear 150 is tried first, then 0 and the fan (got %s)"), *Get_OrderText(AfterOneFifty)),
        AfterOneFifty == TArray<float>{150.0f, 0.0f, 30.0f, -30.0f, 60.0f, -60.0f, 90.0f, -90.0f, 120.0f, -120.0f, -150.0f});

    const auto AfterZero = Get_Order(0.0f);
    TestTrue(FString::Printf(TEXT("Last clear 0 is the fan order (got %s)"), *Get_OrderText(AfterZero)), AfterZero == Fan);

    const auto AfterNonFanAngle = Get_Order(45.0f);
    TestTrue(FString::Printf(TEXT("Last clear 45, not a fan angle, is the fan order (got %s)"), *Get_OrderText(AfterNonFanAngle)),
        AfterNonFanAngle == Fan);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceBodySelectionKeepsEndpointsAndStablePriorityTest,
    "Ck.ProceduralAnimation.ChainClearance.BodySelectionKeepsEndpointsAndStablePriority",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceBodySelectionKeepsEndpointsAndStablePriorityTest::
    RunTest(const FString&)
    -> bool
{
    const auto LeftInitial = TArray<FVector>{{-10.0, 0.0, 0.0}, {0.0, 0.0, 10.0}, {10.0, 0.0, 0.0}};
    const auto LeftClear = TArray<FVector>{{-10.0, 0.0, 0.0}, {0.0, 10.0, 0.0}, {10.0, 0.0, 0.0}};
    const auto RightInitial = TArray<FVector>{{-10.0, 0.0, 10.0}, {0.0, 0.0, 0.0}, {10.0, 0.0, 10.0}};
    const auto RightClear = TArray<FVector>{{-10.0, 0.0, 10.0}, {0.0, -10.0, 10.0}, {10.0, 0.0, 10.0}};
    const auto LeftCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{LeftInitial},
        ck::FProceduralChainPoseCandidate{LeftClear}};
    const auto RightCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{RightInitial},
        ck::FProceduralChainPoseCandidate{RightClear}};
    const auto Radii = TArray<float>{1.0f, 1.0f};
    const auto Left = ck::FProceduralChainAvoidanceLeg{10, LeftCandidates, Radii, 0};
    const auto Right = ck::FProceduralChainAvoidanceLeg{20, RightCandidates, Radii, 0};
    const auto Legs = TArray<ck::FProceduralChainAvoidanceLeg>{Left, Right};
    auto Scratch = ck::FProceduralChainAvoidanceScratch{};
    auto Outcome = ck::FProceduralChainAvoidanceOutcome{};
    auto Choices = TArray<int32>{-1, -1};
    auto Crossings = TArray<int32>{-1, -1};
    TestTrue(TEXT("Intersecting initial chains admit a clear, length-preserving assignment"),
        ck::SelectProceduralChainPoses(Legs, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("The lower stable id yields; the now-clear neighbor keeps its initial pose"),
        Choices == TArray<int32>{1, 0});
    TestTrue(TEXT("Both chosen chains are clear"), Crossings == TArray<int32>{0, 0});
    TestEqual(TEXT("No capsule penetration remains"), Outcome.Get_MaxPenetration(), 0.0);
    TestEqual(TEXT("No squared overlap remains"), Outcome.Get_TotalPenalty(), 0.0);
    TestTrue(TEXT("Search obeys the three-pass candidate-evaluation bound"),
        Outcome.Get_Passes() <= 3 && Outcome.Get_CandidateEvaluations() <= 3 * 2 * (2 - 1));
    TestTrue(TEXT("The alternative retains hip and foot"),
        LeftInitial[0] == LeftClear[0] && LeftInitial.Last() == LeftClear.Last());
    for (auto Link = 0; Link < Radii.Num(); ++Link)
    {
        TestTrue(TEXT("The alternative retains each rigid link length"),
            FMath::IsNearlyEqual(FVector::Distance(LeftInitial[Link], LeftInitial[Link + 1]),
                FVector::Distance(LeftClear[Link], LeftClear[Link + 1]), 1.0e-8));
    }

    const auto ReversedLegs = TArray<ck::FProceduralChainAvoidanceLeg>{Right, Left};
    TestTrue(TEXT("The same reusable scratch accepts permuted legs"),
        ck::SelectProceduralChainPoses(ReversedLegs, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("Permutation preserves each stable id's chosen pose"), Choices == TArray<int32>{0, 1});

    const auto FixedLeft = ck::FProceduralChainAvoidanceLeg{10, MakeArrayView(LeftCandidates).Left(1), Radii, 0};
    const auto NeighborYields = TArray<ck::FProceduralChainAvoidanceLeg>{FixedLeft, Right};
    TestTrue(TEXT("A fixed leg allows its flexible neighbor to resolve the overlap"),
        ck::SelectProceduralChainPoses(NeighborYields, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("The neighbor selects its alternative without modifying the fixed pose"), Choices == TArray<int32>{0, 1});
    TestEqual(TEXT("The neighbor's alternative removes the overlap"), Outcome.Get_TotalPenalty(), 0.0);

    const auto ClearInitial = TArray<ck::FProceduralChainAvoidanceLeg>{
        ck::FProceduralChainAvoidanceLeg{10, LeftCandidates, Radii, 1}, Right};
    TestTrue(TEXT("An already-clear retained choice remains stable"),
        ck::SelectProceduralChainPoses(ClearInitial, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("Equal zero scores do not reset the retained choice"), Choices == TArray<int32>{1, 0});
    TestEqual(TEXT("A clear assignment needs no coordinate pass"), Outcome.Get_Passes(), 0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceBodyOverlapCountsAndScratchReuseTest,
    "Ck.ProceduralAnimation.ChainClearance.BodyOverlapCountsAndScratchReuse",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceBodyOverlapCountsAndScratchReuseTest::
    RunTest(const FString&)
    -> bool
{
    const auto LeftJoints = TArray<FVector>{{-10.0, 0.0, 0.0}, {0.0, 0.0, 10.0}, {10.0, 0.0, 0.0}};
    const auto RightJoints = TArray<FVector>{{-3.0, -3.0, 10.0}, {3.0, 3.0, 10.0}};
    const auto LeftCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{LeftJoints}};
    const auto RightCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{RightJoints}};
    const auto LeftRadii = TArray<float>{1.0f, 1.0f};
    const auto RightRadii = TArray<float>{1.0f};
    const auto Legs = TArray<ck::FProceduralChainAvoidanceLeg>{{1, LeftCandidates, LeftRadii, 0},
        {2, RightCandidates, RightRadii, 0}};
    auto Scratch = ck::FProceduralChainAvoidanceScratch{};
    auto Outcome = ck::FProceduralChainAvoidanceOutcome{};
    auto Choices = TArray<int32>{-1, -1};
    auto Crossings = TArray<int32>{-1, -1};
    TestTrue(TEXT("Unavoidable overlap is returned honestly"),
        ck::SelectProceduralChainPoses(Legs, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("Counts are distinct links, not pair multiplicity"), Crossings == TArray<int32>{2, 1});
    TestTrue(TEXT("Two intersecting pairs contribute two squared 2 cm penetrations"),
        FMath::IsNearlyEqual(Outcome.Get_TotalPenalty(), 8.0, 1.0e-8));
    TestTrue(TEXT("Worst capsule penetration is 2 cm"), FMath::IsNearlyEqual(Outcome.Get_MaxPenetration(), 2.0, 1.0e-8));

    const auto EqualCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{LeftJoints},
        ck::FProceduralChainPoseCandidate{LeftJoints}};
    const auto EqualLegs = TArray<ck::FProceduralChainAvoidanceLeg>{{1, EqualCandidates, LeftRadii, 1}, Legs[1]};
    TestTrue(TEXT("Unresolved equal-score alternatives are valid"),
        ck::SelectProceduralChainPoses(EqualLegs, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("Equal positive penalties preserve the retained candidate"), Choices == TArray<int32>{1, 0});

    const auto Point = TArray<FVector>{FVector::ZeroVector, FVector::ZeroVector};
    const auto TangentPoint = TArray<FVector>{{2.0, 0.0, 0.0}, {2.0, 0.0, 0.0}};
    const auto PointCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{Point}};
    const auto TangentCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{TangentPoint}};
    const auto TangentLegs = TArray<ck::FProceduralChainAvoidanceLeg>{{1, PointCandidates, RightRadii, 0},
        {2, TangentCandidates, RightRadii, 0}};
    TestTrue(TEXT("Degenerate tangent capsules are valid"),
        ck::SelectProceduralChainPoses(TangentLegs, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("Scratch reuse clears the old crossing masks"), Crossings == TArray<int32>{0, 0});
    TestEqual(TEXT("Tangency has zero penalty"), Outcome.Get_TotalPenalty(), 0.0);

    const auto ZeroRadii = TArray<float>{0.0f, 0.0f};
    const auto ZeroRightRadii = TArray<float>{0.0f};
    const auto ZeroLegs = TArray<ck::FProceduralChainAvoidanceLeg>{{1, LeftCandidates, ZeroRadii, 0},
        {2, RightCandidates, ZeroRightRadii, 0}};
    TestTrue(TEXT("Explicit zero thickness preserves the supplied choices"),
        ck::SelectProceduralChainPoses(ZeroLegs, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("Zero thickness produces no crossing links"), Crossings == TArray<int32>{0, 0});
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralChainClearanceBodyRejectsMalformedInputAtomicallyTest,
    "Ck.ProceduralAnimation.ChainClearance.BodyRejectsMalformedInputAtomically",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralChainClearanceBodyRejectsMalformedInputAtomicallyTest::
    RunTest(const FString&)
    -> bool
{
    const auto Joints = TArray<FVector>{FVector::ZeroVector, FVector::UpVector};
    const auto Candidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{Joints}};
    const auto Radii = TArray<float>{1.0f};
    auto Scratch = ck::FProceduralChainAvoidanceScratch{};
    auto Outcome = ck::FProceduralChainAvoidanceOutcome{};
    Outcome.Set_MaxPenetration(19.0);
    Outcome.Set_TotalPenalty(23.0);
    Outcome.Set_CandidateEvaluations(29);
    Outcome.Set_Passes(31);
    auto Choices = TArray<int32>{37};
    auto Crossings = TArray<int32>{41};
    const auto CheckRejected = [&](const TCHAR* InLabel, TArrayView<const ck::FProceduralChainAvoidanceLeg> InLegs)
    {
        TestFalse(InLabel, ck::SelectProceduralChainPoses(InLegs, Scratch, Choices, Crossings, Outcome));
        TestTrue(TEXT("Rejected input preserves both output arrays"), Choices == TArray<int32>{37} && Crossings == TArray<int32>{41});
        TestTrue(TEXT("Rejected input preserves the complete outcome"), Outcome.Get_MaxPenetration() == 19.0
            && Outcome.Get_TotalPenalty() == 23.0 && Outcome.Get_CandidateEvaluations() == 29 && Outcome.Get_Passes() == 31);
    };
    const auto WrongChoice = TArray<ck::FProceduralChainAvoidanceLeg>{{1, Candidates, Radii, 1}};
    CheckRejected(TEXT("Out-of-range retained choice rejects"), WrongChoice);
    const auto WrongSize = TArray<float>{1.0f, 1.0f};
    const auto WrongShape = TArray<ck::FProceduralChainAvoidanceLeg>{{1, Candidates, WrongSize, 0}};
    CheckRejected(TEXT("Link radii must match every candidate"), WrongShape);
    const auto NegativeRadii = TArray<float>{-1.0f};
    const auto Negative = TArray<ck::FProceduralChainAvoidanceLeg>{{1, Candidates, NegativeRadii, 0}};
    CheckRejected(TEXT("Negative thickness rejects"), Negative);
    const auto InfiniteRadii = TArray<float>{std::numeric_limits<float>::infinity()};
    const auto Infinite = TArray<ck::FProceduralChainAvoidanceLeg>{{1, Candidates, InfiniteRadii, 0}};
    CheckRejected(TEXT("Infinite thickness rejects"), Infinite);
    const auto NaNJoints = TArray<FVector>{FVector::ZeroVector, FVector{std::numeric_limits<double>::quiet_NaN(), 0.0, 0.0}};
    const auto NaNCandidates = TArray<ck::FProceduralChainPoseCandidate>{ck::FProceduralChainPoseCandidate{NaNJoints}};
    const auto NaNLeg = TArray<ck::FProceduralChainAvoidanceLeg>{{1, NaNCandidates, Radii, 0}};
    CheckRejected(TEXT("Nonfinite geometry rejects"), NaNLeg);
    const auto EmptyCandidates = TArray<ck::FProceduralChainPoseCandidate>{};
    const auto EmptyLeg = TArray<ck::FProceduralChainAvoidanceLeg>{{1, EmptyCandidates, Radii, 0}};
    CheckRejected(TEXT("Empty candidate lists reject"), EmptyLeg);
    auto TooManyCandidates = TArray<ck::FProceduralChainPoseCandidate>{};
    TooManyCandidates.Init(ck::FProceduralChainPoseCandidate{Joints}, 25);
    const auto TooMany = TArray<ck::FProceduralChainAvoidanceLeg>{{1, TooManyCandidates, Radii, 0}};
    CheckRejected(TEXT("Candidate count is bounded"), TooMany);
    const auto Valid = TArray<ck::FProceduralChainAvoidanceLeg>{{1, Candidates, Radii, 0}};
    TestFalse(TEXT("Output storage cannot alias"), ck::SelectProceduralChainPoses(Valid, Scratch, Choices, Choices, Outcome));
    TestTrue(TEXT("Aliasing rejection preserves output"), Choices == TArray<int32>{37});

    Choices.Add(37);
    Crossings.Add(41);
    const auto DuplicateIds = TArray<ck::FProceduralChainAvoidanceLeg>{Valid[0], Valid[0]};
    TestFalse(TEXT("Stable ids must be unique"), ck::SelectProceduralChainPoses(DuplicateIds, Scratch, Choices, Crossings, Outcome));
    TestTrue(TEXT("Duplicate-id rejection preserves outputs"), Choices == TArray<int32>{37, 37} && Crossings == TArray<int32>{41, 41});

    auto NoChoices = TArray<int32>{};
    auto NoCrossings = TArray<int32>{};
    TestTrue(TEXT("An empty body accepts without retaining a prior outcome"),
        ck::SelectProceduralChainPoses({}, Scratch, NoChoices, NoCrossings, Outcome));
    TestTrue(TEXT("An empty body has no work or overlap"), Outcome.Get_MaxPenetration() == 0.0
        && Outcome.Get_TotalPenalty() == 0.0 && Outcome.Get_CandidateEvaluations() == 0 && Outcome.Get_Passes() == 0);
    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
