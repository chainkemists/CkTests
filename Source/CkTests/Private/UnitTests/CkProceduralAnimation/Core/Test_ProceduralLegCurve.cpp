#include "CkProceduralAnimation/Core/CkProceduralLegCurve.h"

#include "../../CkUnitTest_Common.h"

#include <limits>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_procedural_leg_curve
{
    constexpr auto EndTolerance = 0.5;
    constexpr auto LinkTolerance = 1.0e-3;
    constexpr auto PlaneTolerance = 0.01;
    constexpr auto StepCm = 1.0;
    constexpr auto BentMaxJointMovePerStep = 5.0;
    // Near the fold the hip->foot direction turns fast (a 1 cm move at 7 cm from the hip turns it by about 8 degrees) and the
    // whole arch turns with it; the Python port of the solver measured up to 8.5 cm per 1 cm step for the gym chains.
    constexpr auto FoldedMaxJointMovePerStep = 15.0;
    constexpr auto FoldedLowRatio = 0.05;
    constexpr auto FoldedHighRatio = 0.3;
    constexpr auto BentHighRatio = 0.9;
    // Chains with few, uneven links have no closing arch below about 0.38 of their length (the Python port found the first
    // gap at 0.37 for 40/40/60 and 30/35/30/25); the eight-link and four-link spider chains close down to 0.3.
    constexpr auto BentLowRatio = 0.4;
    constexpr auto BentLowRatioLongChains = 0.3;
    const auto Hip = FVector{120.0, -40.0, 300.0};
    const auto Bend = FVector{30.0, -20.0, 100.0};
    const auto Sentinel = FVector{1234.0, 5678.0, 91011.0};

    struct FChain
    {
        const TCHAR* Name = TEXT("");
        TArray<float> Lengths;
        double LowRatio = BentLowRatio;
    };

    auto
        Get_Chains()
        -> TArray<FChain>
    {
        auto Tentacle = TArray<float>{};
        Tentacle.Init(18.0f, 8);
        return TArray<FChain>{
            FChain{TEXT("Crawler 40/40/60"), TArray<float>{40.0f, 40.0f, 60.0f}, BentLowRatio},
            FChain{TEXT("Beast rear 30/35/30/25"), TArray<float>{30.0f, 35.0f, 30.0f, 25.0f}, BentLowRatio},
            FChain{TEXT("Spider 50/60/60/50"), TArray<float>{50.0f, 60.0f, 60.0f, 50.0f}, BentLowRatioLongChains},
            FChain{TEXT("Tentacle 8 x 18"), Tentacle, BentLowRatioLongChains}};
    }

    auto
        Get_FootDirections()
        -> TArray<FVector>
    {
        return TArray<FVector>{
            FVector{1.0, 0.3, -1.0}.GetSafeNormal(),
            FVector{0.2, 1.0, -0.8}.GetSafeNormal(),
            FVector{-0.5, -0.5, -1.0}.GetSafeNormal(),
            FVector{1.0, 0.0, 0.4}.GetSafeNormal()};
    }

    auto
        Get_Length(
            TArrayView<const float> InLengths)
        -> double
    {
        auto Length = 0.0;
        for (const auto Segment : InLengths)
        { Length += Segment; }
        return Length;
    }

    auto
        Solve(
            const FVector& InHip,
            const FVector& InFoot,
            const FVector& InBend,
            TArrayView<const float> InLengths,
            TArray<FVector>& OutJoints)
        -> bool
    {
        OutJoints.Init(Sentinel, InLengths.Num() + 1);
        return ck::SolveProceduralLegCurve(InHip, InFoot, InBend, InLengths, OutJoints);
    }

    auto
        Get_MaxJointMove(
            const TArray<FVector>& InA,
            const TArray<FVector>& InB)
        -> double
    {
        auto Move = 0.0;
        for (auto Index = 0; Index < InA.Num() && Index < InB.Num(); ++Index)
        { Move = FMath::Max(Move, FVector::Dist(InA[Index], InB[Index])); }
        return Move;
    }

    auto
        Get_MaxLinkError(
            TArrayView<const FVector> InJoints,
            TArrayView<const float> InLengths)
        -> double
    {
        auto Error = 0.0;
        for (auto Index = 0; Index < InLengths.Num(); ++Index)
        { Error = FMath::Max(Error, FMath::Abs(FVector::Dist(InJoints[Index], InJoints[Index + 1]) - InLengths[Index])); }
        return Error;
    }

    auto
        Get_AreJointsFinite(
            TArrayView<const FVector> InJoints)
        -> bool
    {
        for (const auto& Joint : InJoints)
        {
            if (Joint.ContainsNaN())
            { return false; }
        }
        return true;
    }

    auto
        Get_MaxPlaneError(
            TArrayView<const FVector> InJoints,
            const FVector& InHip,
            const FVector& InFoot,
            const FVector& InBend)
        -> double
    {
        const auto Normal = FVector::CrossProduct(InFoot - InHip, InBend).GetSafeNormal();
        auto Error = 0.0;
        for (const auto& Joint : InJoints)
        { Error = FMath::Max(Error, FMath::Abs(FVector::DotProduct(Joint - InHip, Normal))); }
        return Error;
    }

    auto
        Get_IsUntouched(
            const TArray<FVector>& InJoints)
        -> bool
    {
        for (const auto& Joint : InJoints)
        {
            if (NOT Joint.Equals(Sentinel, 0.0))
            { return false; }
        }
        return true;
    }

    // The worst joint move for a 1 cm foot step while the foot walks radially from InLowRatio to InHighRatio of the chain.
    auto
        Get_WorstRadialMove(
            TArrayView<const float> InLengths,
            const FVector& InDirection,
            double InLowRatio,
            double InHighRatio,
            FString& OutWhere)
        -> double
    {
        const auto Length = Get_Length(InLengths);
        auto Worst = 0.0;
        auto Previous = TArray<FVector>{};
        auto Current = TArray<FVector>{};
        for (auto Distance = InLowRatio * Length; Distance <= InHighRatio * Length; Distance += StepCm)
        {
            if (NOT Solve(Hip, Hip + InDirection * Distance, Bend, InLengths, Current))
            {
                OutWhere = FString::Printf(TEXT("rejected at D/L %.3f"), Distance / Length);
                return TNumericLimits<double>::Max();
            }
            if (Previous.Num() > 0)
            {
                const auto Move = Get_MaxJointMove(Previous, Current);
                if (Move > Worst)
                {
                    Worst = Move;
                    OutWhere = FString::Printf(TEXT("D/L %.3f"), Distance / Length);
                }
            }
            Previous = Current;
        }
        return Worst;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveEndsOnTargetTest,
    "Ck.ProceduralAnimation.LegCurve.EndsOnTargetAndKeepsLengths",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveEndsOnTargetTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    for (const auto& Chain : Get_Chains())
    {
        const auto Length = Get_Length(Chain.Lengths);
        auto Solved = true;
        auto WorstEnd = 0.0;
        auto WorstLink = 0.0;
        auto WorstPlane = 0.0;
        auto WorstHip = 0.0;
        auto WorstEndAt = FString{};
        for (const auto Ratio : {Chain.LowRatio, 0.45, 0.6, 0.75, 0.9, 0.95, 0.98})
        {
            for (const auto& Direction : Get_FootDirections())
            {
                const auto Foot = Hip + Direction * (Ratio * Length);
                auto Joints = TArray<FVector>{};
                if (NOT Solve(Hip, Foot, Bend, Chain.Lengths, Joints))
                {
                    Solved = false;
                    continue;
                }

                const auto Normal = FVector::CrossProduct(Foot - Hip, Bend).GetSafeNormal();
                WorstHip = FMath::Max(WorstHip, FVector::Dist(Joints[0], Hip));
                const auto End = FVector::Dist(Joints.Last(), Foot);
                if (End > WorstEnd)
                {
                    WorstEnd = End;
                    WorstEndAt = FString::Printf(TEXT("D/L %.2f, direction %s"), Ratio, *Direction.ToString());
                }
                for (auto Index = 0; Index < Chain.Lengths.Num(); ++Index)
                {
                    WorstLink = FMath::Max(WorstLink, FMath::Abs(FVector::Dist(Joints[Index], Joints[Index + 1]) - Chain.Lengths[Index]));
                }
                for (const auto& Joint : Joints)
                { WorstPlane = FMath::Max(WorstPlane, FMath::Abs(FVector::DotProduct(Joint - Hip, Normal))); }
            }
        }

        TestTrue(FString::Printf(TEXT("%s: every reachable foot solves"), Chain.Name), Solved);
        TestTrue(FString::Printf(TEXT("%s: the chain starts on the hip (worst %.6f cm)"), Chain.Name, WorstHip), WorstHip < LinkTolerance);
        TestTrue(FString::Printf(TEXT("%s: the chain ends on the foot (worst %.4f cm at %s)"), Chain.Name, WorstEnd, *WorstEndAt),
            WorstEnd < EndTolerance);
        TestTrue(FString::Printf(TEXT("%s: every link keeps its length (worst %.6f cm)"), Chain.Name, WorstLink), WorstLink < LinkTolerance);
        TestTrue(FString::Printf(TEXT("%s: every joint lies in the hip-foot-bend plane (worst %.6f cm)"), Chain.Name, WorstPlane),
            WorstPlane < PlaneTolerance);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveContinuousWhenBentTest,
    "Ck.ProceduralAnimation.LegCurve.IsContinuousWhenBent",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveContinuousWhenBentTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    for (const auto& Chain : Get_Chains())
    {
        auto Worst = 0.0;
        auto WorstAt = FString{};
        for (const auto& Direction : Get_FootDirections())
        {
            auto Where = FString{};
            const auto Move = Get_WorstRadialMove(Chain.Lengths, Direction, Chain.LowRatio, BentHighRatio, Where);
            if (Move > Worst)
            {
                Worst = Move;
                WorstAt = FString::Printf(TEXT("%s along %s"), *Where, *Direction.ToString());
            }
        }

        // The foot also slides sideways across the bend plane at a mid bend.
        const auto Length = Get_Length(Chain.Lengths);
        const auto Radial = Get_FootDirections()[0];
        const auto Sideways = FVector::CrossProduct(Radial, Bend).GetSafeNormal();
        auto Previous = TArray<FVector>{};
        auto Current = TArray<FVector>{};
        for (auto Offset = -40.0; Offset <= 40.0; Offset += StepCm)
        {
            if (NOT Solve(Hip, Hip + Radial * (0.6 * Length) + Sideways * Offset, Bend, Chain.Lengths, Current))
            {
                Worst = TNumericLimits<double>::Max();
                WorstAt = TEXT("a sideways foot was rejected");
                break;
            }
            if (Previous.Num() > 0 && Get_MaxJointMove(Previous, Current) > Worst)
            {
                Worst = Get_MaxJointMove(Previous, Current);
                WorstAt = FString::Printf(TEXT("sideways offset %.0f cm"), Offset);
            }
            Previous = Current;
        }

        AddInfo(FString::Printf(TEXT("%s: worst joint move %.3f cm per 1 cm foot step for D/L %.2f..%.2f (%s)"),
            Chain.Name, Worst, Chain.LowRatio, BentHighRatio, *WorstAt));
        TestTrue(FString::Printf(TEXT("%s: a 1 cm foot step moves no joint more than %.1f cm while bent (worst %.3f at %s)"),
            Chain.Name, BentMaxJointMovePerStep, Worst, *WorstAt), Worst <= BentMaxJointMovePerStep);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveContinuousWhenFoldedTest,
    "Ck.ProceduralAnimation.LegCurve.IsContinuousWhenFolded",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveContinuousWhenFoldedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    for (const auto& Chain : Get_Chains())
    {
        auto Worst = 0.0;
        auto WorstAt = FString{};
        for (const auto& Direction : Get_FootDirections())
        {
            auto Where = FString{};
            const auto Move = Get_WorstRadialMove(Chain.Lengths, Direction, FoldedLowRatio, FoldedHighRatio, Where);
            if (Move > Worst)
            {
                Worst = Move;
                WorstAt = FString::Printf(TEXT("%s along %s"), *Where, *Direction.ToString());
            }
        }

        AddInfo(FString::Printf(TEXT("%s: worst joint move %.3f cm per 1 cm foot step for D/L %.2f..%.2f (%s)"),
            Chain.Name, Worst, FoldedLowRatio, FoldedHighRatio, *WorstAt));
        TestTrue(FString::Printf(TEXT("%s: a 1 cm foot step moves no joint more than %.1f cm while folded (worst %.3f at %s)"),
            Chain.Name, FoldedMaxJointMovePerStep, Worst, *WorstAt), Worst <= FoldedMaxJointMovePerStep);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurvePreservesRecordedBeastProximalLinkTest,
    "Ck.ProceduralAnimation.LegCurve.PreservesRecordedBeastProximalLink",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurvePreservesRecordedBeastProximalLinkTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    // Flat/Beast RL frame 802: full-chain closure pulled the first link through the body's visual box.
    // The recorded pre-closure curve's first joint is the shape-preserving anchor for suffix closure.
    const auto RecordedHip = FVector{1110.7383126269115, -48.22601038492473, 27.8628513};
    const auto RecordedFoot = FVector{1133.7, -66.0, 25.3};
    const auto RecordedPole = FVector{1155.0850294649085, -85.32223317308407, 40.5671617};
    const auto RecordedFirstJoint = FVector{1111.3102690143294, -53.3146252248031, 57.422602058459745};
    const auto Lengths = TArray<float>{30.0f, 35.0f, 30.0f, 25.0f};
    auto Joints = TArray<FVector>{};
    if (NOT TestTrue(TEXT("The recorded Flat Beast rear chain solves"),
        Solve(RecordedHip, RecordedFoot, RecordedPole - RecordedHip, Lengths, Joints)))
    { return false; }

    TestTrue(TEXT("The recorded foot closes while the first joint remains on the original curve"),
        FVector::Dist(Joints.Last(), RecordedFoot) < 0.1 && FVector::Dist(Joints[1], RecordedFirstJoint) < 0.2);
    TestTrue(TEXT("The recorded first link retains its exact length"),
        FMath::Abs(FVector::Dist(Joints[0], Joints[1]) - Lengths[0]) < LinkTolerance);
    TestTrue(TEXT("Every recorded joint remains finite and rigid"),
        Get_AreJointsFinite(Joints) && Get_MaxLinkError(Joints, Lengths) < LinkTolerance);
    TestTrue(TEXT("The suffix correction stays in the authored bend plane"),
        Get_MaxPlaneError(Joints, RecordedHip, RecordedFoot, RecordedPole - RecordedHip) < PlaneTolerance);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveClosesRecordedBeastTouchdownTest,
    "Ck.ProceduralAnimation.LegCurve.ClosesRecordedBeastTouchdown",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveClosesRecordedBeastTouchdownTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    // Flat/Beast RL touchdown from the real-Jolt telemetry frame 805: the former curve ended 9 cm off the foot.
    const auto RecordedHip = FVector{1111.3847134806206, -44.02420429030417, 30.7841064};
    const auto RecordedFoot = FVector{1135.0, -30.5, 0.0};
    const auto RecordedPole = FVector{1162.48611941862, -70.74775483312705, 44.1442872};
    const auto Lengths = TArray<float>{30.0f, 35.0f, 30.0f, 25.0f};
    auto Joints = TArray<FVector>{};
    if (NOT TestTrue(TEXT("The recorded Beast rear chain solves"),
        Solve(RecordedHip, RecordedFoot, RecordedPole - RecordedHip, Lengths, Joints)))
    { return false; }

    TestTrue(TEXT("The recorded Beast endpoint closes to within 0.1 cm"), FVector::Dist(Joints.Last(), RecordedFoot) < 0.1);
    TestTrue(TEXT("The recorded Beast first joint stays on the original curve"),
        FVector::Dist(Joints[1], FVector{1135.3985831431503, -59.07507010118864, 40.623085115994314}) < 0.2);
    TestTrue(TEXT("The recorded Beast joints stay finite"), Get_AreJointsFinite(Joints));
    TestTrue(TEXT("The corrected Beast keeps every rigid link"), Get_MaxLinkError(Joints, Lengths) < LinkTolerance);
    TestTrue(TEXT("The corrected Beast stays in its authored bend plane"),
        Get_MaxPlaneError(Joints, RecordedHip, RecordedFoot, RecordedPole - RecordedHip) < PlaneTolerance);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveClosesFoldedReachableTargetsTest,
    "Ck.ProceduralAnimation.LegCurve.ClosesFoldedReachableTargets",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveClosesFoldedReachableTargetsTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    for (const auto& Chain : Get_Chains())
    {
        const auto Length = Get_Length(Chain.Lengths);
        auto WorstEnd = 0.0;
        auto WorstLink = 0.0;
        auto WorstPlane = 0.0;
        auto AllFinite = true;
        auto WorstWhere = FString{};
        for (const auto& Direction : Get_FootDirections())
        {
            for (auto Distance = 0.05 * Length; Distance <= 0.95 * Length; Distance += 1.0)
            {
                const auto Foot = Hip + Direction * Distance;
                auto Joints = TArray<FVector>{};
                if (NOT TestTrue(FString::Printf(TEXT("%s at %.1f cm solves"), Chain.Name, Distance),
                    Solve(Hip, Foot, Bend, Chain.Lengths, Joints)))
                { continue; }

                const auto End = FVector::Dist(Joints.Last(), Foot);
                if (End > WorstEnd)
                {
                    WorstEnd = End;
                    WorstWhere = FString::Printf(TEXT("D/L %.3f direction %s"), Distance / Length, *Direction.ToString());
                }
                WorstLink = FMath::Max(WorstLink, Get_MaxLinkError(Joints, Chain.Lengths));
                WorstPlane = FMath::Max(WorstPlane, Get_MaxPlaneError(Joints, Hip, Foot, Bend));
                AllFinite &= Get_AreJointsFinite(Joints);
            }
        }
        TestTrue(FString::Printf(TEXT("%s closes across its reachable 5-95%% radial sweep (worst %.4f cm at %s)"),
            Chain.Name, WorstEnd, *WorstWhere), WorstEnd < 0.1);
        TestTrue(FString::Printf(TEXT("%s preserves rigid links across the sweep (worst %.6f cm)"),
            Chain.Name, WorstLink), WorstLink < LinkTolerance);
        TestTrue(FString::Printf(TEXT("%s stays planar across the sweep (worst %.6f cm)"),
            Chain.Name, WorstPlane), WorstPlane < PlaneTolerance);
        TestTrue(FString::Printf(TEXT("%s stays finite across the sweep"), Chain.Name), AllFinite);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveFoldedBranchRemainsBoundedTest,
    "Ck.ProceduralAnimation.LegCurve.FoldedBranchRemainsBounded",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveFoldedBranchRemainsBoundedTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    const auto Lengths = TArray<float>{40.0f, 40.0f, 60.0f};
    const auto Direction = Get_FootDirections()[0];
    auto Before = TArray<FVector>{};
    auto After = TArray<FVector>{};
    TestTrue(TEXT("The Crawler curve solves before its folded branch switch"),
        Solve(Hip, Hip + Direction * 52.30, Bend, Lengths, Before));
    TestTrue(TEXT("The Crawler curve solves after its folded branch switch"),
        Solve(Hip, Hip + Direction * 52.35, Bend, Lengths, After));
    if (Before.Num() == 0 || After.Num() == 0)
    { return false; }
    TestTrue(TEXT("The 0.05 cm target change keeps the branch joint jump below 0.5 cm"),
        Get_MaxJointMove(Before, After) < 0.5);
    TestTrue(TEXT("The original proximal link varies continuously through the branch"),
        FVector::Dist(Before[1], After[1]) < 0.1);
    TestTrue(TEXT("Both sides of the folded branch still close"),
        FVector::Dist(Before.Last(), Hip + Direction * 52.30) < 0.1 &&
        FVector::Dist(After.Last(), Hip + Direction * 52.35) < 0.1);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurvePreservesUnreachableAndCoincidentTest,
    "Ck.ProceduralAnimation.LegCurve.PreservesUnreachableAndCoincident",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurvePreservesUnreachableAndCoincidentTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    const auto Uneven = TArray<float>{10.0f, 1.0f};
    const auto Inside = Hip + Get_FootDirections()[0] * 1.1;
    auto Unreachable = TArray<FVector>{};
    if (TestTrue(TEXT("A target inside the 9 cm inner reach keeps a finite pose"),
        Solve(Hip, Inside, Bend, Uneven, Unreachable)))
    {
        TestTrue(TEXT("Every inner-unreachable joint is finite"), Get_AreJointsFinite(Unreachable));
        TestTrue(TEXT("The unreachable pose preserves both rigid links"),
            Get_MaxLinkError(Unreachable, Uneven) < LinkTolerance);
        TestTrue(TEXT("The unreachable foot is not falsely reported as closed"),
            FVector::Dist(Unreachable.Last(), Inside) >= 9.0 - 1.1 - 0.01);
    }

    const auto Folded = TArray<float>{30.0f, 35.0f, 30.0f, 25.0f};
    auto Coincident = TArray<FVector>{};
    if (TestTrue(TEXT("A coincident hip and foot keeps its finite curve pose"),
        Solve(Hip, Hip, Bend, Folded, Coincident)))
    {
        TestTrue(TEXT("Every coincident joint is finite"), Get_AreJointsFinite(Coincident));
        TestTrue(TEXT("The coincident pose retains rigid links without inventing a bend axis"),
            Get_MaxLinkError(Coincident, Folded) < LinkTolerance);
        TestTrue(TEXT("The coincident pose keeps its hip fixed"),
            FVector::Dist(Coincident[0], Hip) < LinkTolerance);
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveStraightensBeyondReachTest,
    "Ck.ProceduralAnimation.LegCurve.StraightensBeyondReach",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveStraightensBeyondReachTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    for (const auto& Chain : Get_Chains())
    {
        const auto Length = Get_Length(Chain.Lengths);
        for (const auto Ratio : {1.0, 1.25})
        {
            const auto Direction = Get_FootDirections()[1];
            auto Joints = TArray<FVector>{};
            if (NOT TestTrue(FString::Printf(TEXT("%s at %.2f of its length solves"), Chain.Name, Ratio),
                Solve(Hip, Hip + Direction * (Ratio * Length), Bend, Chain.Lengths, Joints)))
            { continue; }

            auto Along = 0.0;
            auto WorstOffLine = 0.0;
            for (auto Index = 0; Index < Joints.Num(); ++Index)
            {
                WorstOffLine = FMath::Max(WorstOffLine, FVector::Dist(Joints[Index], Hip + Direction * Along));
                if (Chain.Lengths.IsValidIndex(Index))
                { Along += Chain.Lengths[Index]; }
            }
            TestTrue(FString::Printf(TEXT("%s at %.2f of its length lies straight toward the foot (worst %.6f cm)"),
                Chain.Name, Ratio, WorstOffLine), WorstOffLine < LinkTolerance);
        }
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveRejectsDegenerateBendTest,
    "Ck.ProceduralAnimation.LegCurve.RejectsDegenerateBend",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveRejectsDegenerateBendTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    const auto Lengths = TArray<float>{50.0f, 60.0f, 60.0f, 50.0f};
    const auto Foot = Hip + Get_FootDirections()[0] * (0.6 * Get_Length(Lengths));
    const auto Along = Foot - Hip;
    const auto Across = FVector::CrossProduct(Along, FVector::UpVector).GetSafeNormal() * Along.Size();

    auto Joints = TArray<FVector>{};
    TestTrue(TEXT("Positive control: a bend two degrees off the hip-foot line solves"),
        Solve(Hip, Foot, Along + Across * FMath::Tan(FMath::DegreesToRadians(2.0)), Lengths, Joints));
    TestTrue(TEXT("Positive control: that chain ends on the foot"), FVector::Dist(Joints.Last(), Foot) < EndTolerance);

    const auto DoExpectRejected = [&](const FVector& InBend, const TCHAR* InCase)
    {
        auto Rejected = TArray<FVector>{};
        TestFalse(FString::Printf(TEXT("%s is rejected"), InCase), Solve(Hip, Foot, InBend, Lengths, Rejected));
        TestTrue(FString::Printf(TEXT("%s leaves the joints untouched"), InCase), Get_IsUntouched(Rejected));
    };

    DoExpectRejected(Along, TEXT("A bend along hip->foot"));
    DoExpectRejected(-Along * 3.0, TEXT("A bend against hip->foot"));
    DoExpectRejected(Along + Across * 1.0e-6, TEXT("A bend a micro-degree off hip->foot"));
    DoExpectRejected(FVector::ZeroVector, TEXT("A zero bend"));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkProceduralLegCurveRejectsMalformedInputTest,
    "Ck.ProceduralAnimation.LegCurve.RejectsMalformedInput",
    ck::tests::kCkUnitTestFlags)

auto
    FCkProceduralLegCurveRejectsMalformedInputTest::
    RunTest(const FString&)
    -> bool
{
    using namespace ck_test_procedural_leg_curve;

    const auto Lengths = TArray<float>{40.0f, 40.0f, 60.0f};
    const auto Foot = Hip + Get_FootDirections()[0] * 80.0;
    const auto NaN = std::numeric_limits<double>::quiet_NaN();
    const auto Infinity = std::numeric_limits<double>::infinity();

    auto Joints = TArray<FVector>{};
    TestTrue(TEXT("Positive control: a well-formed chain solves"), Solve(Hip, Foot, Bend, Lengths, Joints));

    const auto DoExpectRejected = [&](const FVector& InHip, const FVector& InFoot, const FVector& InBend,
        const TArray<float>& InLengths, int32 InJointCount, const TCHAR* InCase)
    {
        auto Rejected = TArray<FVector>{};
        Rejected.Init(Sentinel, InJointCount);
        TestFalse(FString::Printf(TEXT("%s is rejected"), InCase),
            ck::SolveProceduralLegCurve(InHip, InFoot, InBend, InLengths, Rejected));
        TestTrue(FString::Printf(TEXT("%s leaves the joints untouched"), InCase), Get_IsUntouched(Rejected));
    };

    DoExpectRejected(Hip, Foot, Bend, TArray<float>{}, 1, TEXT("No links"));
    auto NineLinks = TArray<float>{};
    NineLinks.Init(10.0f, 9);
    DoExpectRejected(Hip, Foot, Bend, NineLinks, 10, TEXT("Nine links"));
    DoExpectRejected(Hip, Foot, Bend, Lengths, Lengths.Num(), TEXT("One joint too few"));
    DoExpectRejected(Hip, Foot, Bend, Lengths, Lengths.Num() + 2, TEXT("One joint too many"));
    DoExpectRejected(FVector{NaN, 0.0, 0.0}, Foot, Bend, Lengths, Lengths.Num() + 1, TEXT("A NaN hip"));
    DoExpectRejected(Hip, FVector{0.0, Infinity, 0.0}, Bend, Lengths, Lengths.Num() + 1, TEXT("An infinite foot"));
    DoExpectRejected(Hip, Foot, FVector{0.0, 0.0, NaN}, Lengths, Lengths.Num() + 1, TEXT("A NaN bend"));
    DoExpectRejected(Hip, Foot, Bend, TArray<float>{40.0f, 0.0f, 60.0f}, 4, TEXT("A zero length"));
    DoExpectRejected(Hip, Foot, Bend, TArray<float>{40.0f, -40.0f, 60.0f}, 4, TEXT("A negative length"));
    DoExpectRejected(Hip, Foot, Bend, TArray<float>{40.0f, std::numeric_limits<float>::quiet_NaN(), 60.0f}, 4, TEXT("A NaN length"));

    return true;
}

#endif

// --------------------------------------------------------------------------------------------------------------------
