#include "CkQueue/Queue/CkQueue_Layout_Algorithm.h"

#include "../CkUnitTest_Common.h"

using ck::tests::kCkUnitTestFlags;

namespace ck_tests_queue_layout
{
    using ck::queue::layout::Build;
    using ck::queue::layout::EBuildOutcome;

    auto AcceptAll(const FTransform&, const TOptional<FTransform>&) -> bool
    { return true; }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_LinearOpen, "Ck.Queue.Layout.LinearOpen", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_LinearOpen::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Result = Build(FTransform::Identity, 3, 100.0f, 32, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("open linear succeeds"), Result.Outcome == EBuildOutcome::Success);
    TestEqual(TEXT("three placements"), Result.Placements.Num(), 3);
    TestEqual(TEXT("front is at the queue owner"), Result.Placements[0].TargetWorldTransform.GetLocation(), FVector::ZeroVector);
    TestEqual(TEXT("third extends behind the front"), Result.Placements[2].TargetWorldTransform.GetLocation(), FVector{-200.0f, 0.0f, 0.0f});
    for (auto Index = 0; Index < Result.Placements.Num(); ++Index)
    {
        TestEqual(TEXT("linear placements have contiguous queue-wide ranks"), Result.Placements[Index].Rank, Index);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_SnakeTurns, "Ck.Queue.Layout.SnakeTurns", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_SnakeTurns::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Result = Build(FTransform::Identity, 4, 100.0f, 64, ECk_Queue_LayoutAlgorithm::OrthogonalSnake,
        [](const FTransform& Candidate, const TOptional<FTransform>&)
        { return Candidate.GetLocation() != FVector{-100.0f, 0.0f, 0.0f}; });
    TestTrue(TEXT("snake routes around blocked forward cell"), Result.Outcome == EBuildOutcome::Success);
    TestEqual(TEXT("four snake placements"), Result.Placements.Num(), 4);
    for (auto Index = 1; Index < Result.Placements.Num(); ++Index)
    {
        const auto Delta = Result.Placements[Index].TargetWorldTransform.GetLocation() - Result.Placements[Index - 1].TargetWorldTransform.GetLocation();
        TestTrue(TEXT("every snake edge is exact spacing"), FMath::IsNearlyEqual(Delta.Size(), 100.0f));
        TestTrue(TEXT("every snake edge is axis aligned"), FMath::IsNearlyZero(Delta.X) || FMath::IsNearlyZero(Delta.Y));
        const auto ToOwner = -Result.Placements[Index].TargetWorldTransform.GetLocation().GetSafeNormal2D();
        const auto SlotForward = Result.Placements[Index].TargetWorldTransform.GetUnitAxis(EAxis::X).GetSafeNormal2D();
        TestTrue(TEXT("every non-front snake slot faces its queue owner"), FVector::DotProduct(ToOwner, SlotForward) > 0.999f);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_AtomicBudgetAndNoViable, "Ck.Queue.Layout.AtomicBudgetAndNoViable", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_AtomicBudgetAndNoViable::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Impossible = Build(FTransform::Identity, 1, 100.0f, 8, ECk_Queue_LayoutAlgorithm::Linear,
        [](const FTransform&, const TOptional<FTransform>&) { return false; });
    TestTrue(TEXT("blocked formation is no-viable"), Impossible.Outcome == EBuildOutcome::NoViablePlacement);
    TestEqual(TEXT("no partial output"), Impossible.Placements.Num(), 0);
    const auto Budget = Build(FTransform::Identity, 2, 100.0f, 1, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("insufficient budget is explicit"), Budget.Outcome == EBuildOutcome::SearchBudgetExhausted);
    TestEqual(TEXT("budget failure is atomic"), Budget.Placements.Num(), 0);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_TightSpaceAndNoDuplicates, "Ck.Queue.Layout.TightSpaceAndNoDuplicates", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_TightSpaceAndNoDuplicates::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    // The direct-behind path is closed after the front; only alternating left/right turns fit.
    const auto Result = Build(FTransform::Identity, 5, 100.0f, 128, ECk_Queue_LayoutAlgorithm::OrthogonalSnake,
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_OwnerRootedContiguousRanks, "Ck.Queue.Layout.OwnerRootedContiguousRanks", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_OwnerRootedContiguousRanks::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Owner = FTransform{FRotator{0.0f, 90.0f, 0.0f}, FVector{1200.0f, -600.0f, 50.0f}};
    const auto Result = Build(Owner, 4, 100.0f, 64, ECk_Queue_LayoutAlgorithm::Linear, AcceptAll);
    TestTrue(TEXT("owner-rooted linear formation succeeds"), Result.Outcome == EBuildOutcome::Success);
    TestEqual(TEXT("front keeps the owner location"), Result.Placements[0].TargetWorldTransform.GetLocation(), Owner.GetLocation());
    TestEqual(TEXT("tail follows the owner-local negative X direction"),
        Result.Placements[3].TargetWorldTransform.GetLocation(), Owner.TransformPosition(FVector{-300.0f, 0.0f, 0.0f}));
    for (auto Index = 0; Index < Result.Placements.Num(); ++Index)
    {
        TestEqual(TEXT("owner-rooted placements have contiguous ranks"), Result.Placements[Index].Rank, Index);
    }
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_Queue_Layout_ProjectedPlacementsCannotCollapse, "Ck.Queue.Layout.ProjectedPlacementsCannotCollapse", kCkUnitTestFlags)
auto FCkTest_Queue_Layout_ProjectedPlacementsCannotCollapse::RunTest(const FString&) -> bool
{
    using namespace ck_tests_queue_layout;
    const auto Result = Build(
        FTransform::Identity,
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
        TEXT("validator-adjusted overlaps reject the whole formation"),
        Result.Outcome == EBuildOutcome::NoViablePlacement);
    TestEqual(TEXT("collapsed formation publishes no partial targets"), Result.Placements.Num(), 0);
    return true;
}
