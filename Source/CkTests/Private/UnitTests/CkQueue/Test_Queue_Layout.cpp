#include "CkQueue/Queue/CkQueue_Layout_Algorithm.h"

#include "../CkUnitTest_Common.h"

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_queue_layout
{
    using ck::queue::layout::Build;
    using ck::queue::layout::EBuildOutcome;

    auto MakeOrigin(const FVector& InLocation, int32 InWeight = 1, int32 InCap = INDEX_NONE) -> FCk_Queue_Origin
    {
        return FCk_Queue_Origin{FTransform{InLocation}}.Set_Weight(InWeight).Set_HardLimitOverride(InCap);
    }

    auto AcceptAll(const FTransform&, const TOptional<FTransform>&) -> bool
    { return true; }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_LinearOpen, "Ck.Queue.Layout.LinearOpen", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_LinearOpen::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Result = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector)}, 3, 100.0f, 32, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("open linear succeeds"), Result.Outcome == EBuildOutcome::Success);
    TestEqual(TEXT("three placements"), Result.Placements.Num(), 3);
    TestEqual(TEXT("front is at the authored origin"), Result.Placements[0].TargetWorldTransform.GetLocation(), FVector::ZeroVector);
    TestEqual(TEXT("third extends behind the front"), Result.Placements[2].TargetWorldTransform.GetLocation(), FVector{-200.0f, 0.0f, 0.0f});
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_SnakeTurns, "Ck.Queue.Layout.SnakeTurns", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_SnakeTurns::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Result = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector)}, 4, 100.0f, 64, ECk_Queue_LayoutAlgorithm::OrthogonalSnake,
        [](const FTransform& Candidate, const TOptional<FTransform>&)
        { return Candidate.GetLocation() != FVector{-100.0f, 0.0f, 0.0f}; });
    TestTrue(TEXT("snake routes around blocked forward cell"), Result.Outcome == EBuildOutcome::Success);
    TestEqual(TEXT("four snake placements"), Result.Placements.Num(), 4);
    for (auto Index = 1; Index < Result.Placements.Num(); ++Index)
    {
        const auto Delta = Result.Placements[Index].TargetWorldTransform.GetLocation() - Result.Placements[Index - 1].TargetWorldTransform.GetLocation();
        TestTrue(TEXT("every snake edge is exact spacing"), FMath::IsNearlyEqual(Delta.Size(), 100.0f));
        TestTrue(TEXT("every snake edge is axis aligned"), FMath::IsNearlyZero(Delta.X) || FMath::IsNearlyZero(Delta.Y));
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_AtomicBudgetAndNoViable, "Ck.Queue.Layout.AtomicBudgetAndNoViable", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_AtomicBudgetAndNoViable::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Impossible = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector)}, 1, 100.0f, 8, ECk_Queue_LayoutAlgorithm::Linear,
        [](const FTransform&, const TOptional<FTransform>&) { return false; });
    TestTrue(TEXT("blocked formation is no-viable"), Impossible.Outcome == EBuildOutcome::NoViablePlacement);
    TestEqual(TEXT("no partial output"), Impossible.Placements.Num(), 0);
    const auto Budget = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector)}, 2, 100.0f, 1, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("insufficient budget is explicit"), Budget.Outcome == EBuildOutcome::SearchBudgetExhausted);
    TestEqual(TEXT("budget failure is atomic"), Budget.Placements.Num(), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_TightSpaceAndNoDuplicates, "Ck.Queue.Layout.TightSpaceAndNoDuplicates", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_TightSpaceAndNoDuplicates::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    // The direct-behind path is closed after the front; only alternating left/right turns fit.
    const auto Result = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector)}, 5, 100.0f, 128, ECk_Queue_LayoutAlgorithm::OrthogonalSnake,
        [](const FTransform& Candidate, const TOptional<FTransform>&)
        {
            const auto Location = Candidate.GetLocation();
            return Location != FVector{-100.0f, 0.0f, 0.0f}
                && Location != FVector{-100.0f, 100.0f, 0.0f};
        });
    TestTrue(TEXT("tight turn-only space remains viable"), Result.Outcome == EBuildOutcome::Success);
    for (auto A = 0; A < Result.Placements.Num(); ++A)
    {
        for (auto B = A + 1; B < Result.Placements.Num(); ++B)
        {
            TestNotEqual(TEXT("snake never revisits a lattice cell"),
                Result.Placements[A].TargetWorldTransform.GetLocation(),
                Result.Placements[B].TargetWorldTransform.GetLocation());
        }
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_OriginsCapsAndOverlap, "Ck.Queue.Layout.OriginsCapsAndOverlap", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_OriginsCapsAndOverlap::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Split = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector, 2), MakeOrigin(FVector{0.0f, 500.0f, 0.0f}, 1)}, 3, 100.0f, 64, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("weighted split succeeds"), Split.Outcome == EBuildOutcome::Success);
    TestEqual(TEXT("weighted origin zero receives two ranks"), Split.Placements[0].OriginIndex, 0);
    TestEqual(TEXT("second ticket uses the lower normalized-load origin"), Split.Placements[1].OriginIndex, 1);
    TestEqual(TEXT("third ticket returns to weighted origin zero"), Split.Placements[2].OriginIndex, 0);
    const auto Capped = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector, 1, 1)}, 2, 100.0f, 64, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("origin capacity failure is atomic"), Capped.Outcome == EBuildOutcome::NoViablePlacement);
    const auto Overlap = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector), MakeOrigin(FVector::ZeroVector)}, 2, 100.0f, 64, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("cross-origin collision rejects entire layout"), Overlap.Outcome == EBuildOutcome::NoViablePlacement);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_OriginTieIsStable, "Ck.Queue.Layout.OriginTieIsStable", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_OriginTieIsStable::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Result = Build(FTransform::Identity, {MakeOrigin(FVector::ZeroVector), MakeOrigin(FVector{0.0f, 500.0f, 0.0f})}, 1, 100.0f, 16, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("equal normalized loads choose the lower origin index"), Result.Outcome == EBuildOutcome::Success);
    TestEqual(TEXT("first ticket belongs to origin zero"), Result.Placements[0].OriginIndex, 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_ProjectedPlacementsCannotCollapse, "Ck.Queue.Layout.ProjectedPlacementsCannotCollapse", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_ProjectedPlacementsCannotCollapse::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Result = Build(
        FTransform::Identity,
        {MakeOrigin(FVector::ZeroVector)},
        2,
        100.0f,
        32,
        ECk_Queue_LayoutAlgorithm::OrthogonalSnake,
        [](FTransform& Candidate, const TOptional<FTransform>& Previous)
        {
            if (Previous.IsSet())
            { Candidate.SetLocation(FVector::ZeroVector); }
            return true;
        });

    TestTrue(
        TEXT("validator-adjusted same-origin overlaps reject the whole formation"),
        Result.Outcome == EBuildOutcome::NoViablePlacement);
    TestEqual(TEXT("collapsed formation publishes no partial targets"), Result.Placements.Num(), 0);
    return true;
}
