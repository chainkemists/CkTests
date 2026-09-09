// The index is deliberately tested only against the exact, forced-linear implementation on a snapshot copy.

#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"

#include "../CkUnitTest_Common.h"

#include <HAL/PlatformTime.h>
#include <Math/RandomStream.h>

#include <limits>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

static_assert(sizeof(decltype(FVector{}.Z)) == sizeof(double));

namespace ck_test_groundnav_dynamicobstacle_broadphase
{
    using ck::groundnav::ECk_GroundNav_DynamicUnionEdge;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleDisc;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleObb;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot;
    using ck::groundnav::Get_DynamicUnionEdge;
    using ck::groundnav::Get_IsDynamicObstacleCoveringCell;
    using ck::groundnav::Try_MakeDynamicObstacleSnapshot;

    auto MakeDisc(const FVector& InCentre, float InRadius = 25.0f, float InHalfHeight = 30.0f)
        -> FCk_GroundNav_DynamicObstacleDisc
    {
        return FCk_GroundNav_DynamicObstacleDisc{InCentre, InRadius, InHalfHeight};
    }

    auto MakeObb(const FVector& InCentre) -> FCk_GroundNav_DynamicObstacleObb
    {
        return FCk_GroundNav_DynamicObstacleObb{
            FTransform{FRotator{0.0f, 31.0f, 0.0f}, InCentre, FVector::OneVector}, FVector{11.0f, 23.0f, 17.0f}};
    }

    auto MakeSnapshot(FAutomationTestBase& InTest, TArray<FCk_GroundNav_DynamicObstacleDisc> InDiscs,
        TArray<FCk_GroundNav_DynamicObstacleObb> InObbs = {}) -> FCk_GroundNav_DynamicObstacleSnapshot
    {
        const auto Snapshot = Try_MakeDynamicObstacleSnapshot(InDiscs, InObbs);
        InTest.TestTrue(TEXT("the broad-phase fixture is valid"), Snapshot.IsSet());
        return Snapshot.IsSet() ? Snapshot.GetValue() : FCk_GroundNav_DynamicObstacleSnapshot{};
    }

    auto CheckEqual(FAutomationTestBase& InTest, const TCHAR* InLabel,
        const TOptional<ECk_GroundNav_DynamicUnionEdge>& InIndexed,
        const TOptional<ECk_GroundNav_DynamicUnionEdge>& InLinear) -> void
    {
        InTest.TestEqual(FString::Printf(TEXT("%s has the same validity"), InLabel), InIndexed.IsSet(), InLinear.IsSet());
        if (InIndexed.IsSet() && InLinear.IsSet())
        { InTest.TestEqual(FString::Printf(TEXT("%s has the same union answer"), InLabel), InIndexed.GetValue(), InLinear.GetValue()); }
    }

    auto CheckEqual(FAutomationTestBase& InTest, const TCHAR* InLabel, const TOptional<bool>& InIndexed,
        const TOptional<bool>& InLinear) -> void
    {
        InTest.TestEqual(FString::Printf(TEXT("%s has the same validity"), InLabel), InIndexed.IsSet(), InLinear.IsSet());
        if (InIndexed.IsSet() && InLinear.IsSet())
        { InTest.TestEqual(FString::Printf(TEXT("%s has the same cell answer"), InLabel), InIndexed.GetValue(), InLinear.GetValue()); }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DynamicObstacleBroadPhase,
    "CkTests.UnitTests.CkGroundNav.Query.DynamicObstacleBroadPhase",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DynamicObstacleBroadPhase::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_dynamicobstacle_broadphase;

    auto Random = FRandomStream{73821};
    auto Discs = TArray<FCk_GroundNav_DynamicObstacleDisc>{};
    Discs.Reserve(195);
    for (auto Index = 0; Index < 195; ++Index)
    {
        Discs.Add(MakeDisc(FVector{Random.FRandRange(-700.0f, 700.0f), Random.FRandRange(-700.0f, 700.0f),
            Random.FRandRange(-50.0f, 50.0f)}, Random.FRandRange(40.0f, 80.0f), Random.FRandRange(40.0f, 80.0f)));
    }
    const auto Indexed = MakeSnapshot(*this, Discs, {MakeObb(FVector{700.0f, -900.0f, 0.0f})});
    auto Linear = Indexed;
    Linear._HasDiscBroadPhase = false;
    Linear._DiscBroadPhaseNodes.Reset();
    Linear._DiscBroadPhaseIndices.Reset();
    TestTrue(TEXT("the nonempty copied snapshot carries an index before the test-only disable"),
        Indexed._HasDiscBroadPhase && NOT Linear._HasDiscBroadPhase);

    const auto Cases = TArray<TPair<FVector, FVector>>{
        TPair<FVector, FVector>{FVector{-900.0f, -900.0f, 0.0f}, FVector{-875.0f, -900.0f, 0.0f}},
        TPair<FVector, FVector>{FVector{-700.0f, 0.0f, 0.0f}, FVector{700.0f, 0.0f, 0.0f}},
        TPair<FVector, FVector>{FVector{0.0f, 0.0f, 1000.0f}, FVector{100.0f, 0.0f, 1000.0f}},
        TPair<FVector, FVector>{FVector{0.0f, 0.0f, 0.0f}, FVector{0.0f, 0.0f, 0.0f}}};
    for (auto Index = 0; Index < Cases.Num(); ++Index)
    {
        CheckEqual(*this, *FString::Printf(TEXT("seeded edge %d"), Index),
            Get_DynamicUnionEdge(Indexed, Cases[Index].Key, Cases[Index].Value),
            Get_DynamicUnionEdge(Linear, Cases[Index].Key, Cases[Index].Value));
    }
    for (auto Index = 0; Index < 64; ++Index)
    {
        const auto Minimum = FVector2D{Random.FRandRange(-800.0f, 800.0f), Random.FRandRange(-800.0f, 800.0f)};
        const auto Size = Random.FRandRange(1.0f, 200.0f);
        const auto Z = Random.FRandRange(-500.0f, 500.0f);
        CheckEqual(*this, *FString::Printf(TEXT("seeded cell %d"), Index),
            Get_IsDynamicObstacleCoveringCell(Indexed, Minimum, Size, Z),
            Get_IsDynamicObstacleCoveringCell(Linear, Minimum, Size, Z));
    }

    const auto Tangent = MakeSnapshot(*this, {MakeDisc(FVector::ZeroVector, 5.0f, 5.0f)});
    auto TangentLinear = Tangent;
    TangentLinear._HasDiscBroadPhase = false;
    TestTrue(TEXT("the tangent fixture has an enabled disc index"), Tangent._HasDiscBroadPhase);
    CheckEqual(*this, TEXT("closed tangency"), Get_DynamicUnionEdge(Tangent, FVector{-5.0f, 5.0f, 0.0f}, FVector{5.0f, 5.0f, 0.0f}),
        Get_DynamicUnionEdge(TangentLinear, FVector{-5.0f, 5.0f, 0.0f}, FVector{5.0f, 5.0f, 0.0f}));
    const auto TangentAnswer = Get_DynamicUnionEdge(Tangent, FVector{-5.0, 5.0, 0.0}, FVector{5.0, 5.0, 0.0});
    TestEqual(TEXT("the closed tangent segment is nonmonotonic"), TangentAnswer.GetValue(), ECk_GroundNav_DynamicUnionEdge::NonMonotonic);
    constexpr auto Gap = 1.0e-10;
    const auto GapAnswer = Get_DynamicUnionEdge(Tangent, FVector{-5.0, 5.0 + Gap, 0.0}, FVector{5.0, 5.0 + Gap, 0.0});
    TestEqual(TEXT("a positive double gap remains clear"), GapAnswer.GetValue(), ECk_GroundNav_DynamicUnionEdge::Clear);
    CheckEqual(*this, TEXT("tiny positive gap"), GapAnswer,
        Get_DynamicUnionEdge(TangentLinear, FVector{-5.0, 5.0 + Gap, 0.0}, FVector{5.0, 5.0 + Gap, 0.0}));
    CheckEqual(*this, TEXT("finite high Z"), Get_IsDynamicObstacleCoveringCell(Tangent, FVector2D{-1.0f, -1.0f}, 2.0f, 100.0f),
        Get_IsDynamicObstacleCoveringCell(TangentLinear, FVector2D{-1.0f, -1.0f}, 2.0f, 100.0f));
    CheckEqual(*this, TEXT("inside overlap"), Get_DynamicUnionEdge(Tangent, FVector::ZeroVector, FVector{2.0f, 0.0f, 0.0f}),
        Get_DynamicUnionEdge(TangentLinear, FVector::ZeroVector, FVector{2.0f, 0.0f, 0.0f}));

    const auto FarZ = MakeSnapshot(*this, {MakeDisc(FVector{0.0, 0.0, 100000000000000000.0}, 5.0f, 5.0f)});
    auto FarZLinear = FarZ;
    FarZLinear._HasDiscBroadPhase = false;
    TestTrue(TEXT("the far-Z tiny-delta fixture has an enabled disc index"), FarZ._HasDiscBroadPhase);
    const auto IndexedMixedDelta = Get_DynamicUnionEdge(FarZ, FVector::ZeroVector, FVector{10.0, 0.0, 1.0e-300});
    const auto LinearMixedDelta = Get_DynamicUnionEdge(FarZLinear, FVector::ZeroVector, FVector{10.0, 0.0, 1.0e-300});
    TestFalse(TEXT("the forced-linear far-disc interval rejects the tiny normal secondary delta"), LinearMixedDelta.IsSet());
    TestFalse(TEXT("the indexed far-disc interval retains that tiny normal secondary rejection"), IndexedMixedDelta.IsSet());
    CheckEqual(*this, TEXT("mixed normal and sub-floor delta retains the far-disc rejection"),
        IndexedMixedDelta, LinearMixedDelta);

    const auto Extreme = std::numeric_limits<float>::max() / 4.0f;
    CheckEqual(*this, TEXT("finite overflow falls back to the linear rejection"),
        Get_DynamicUnionEdge(Indexed, FVector{-Extreme, 0.0f, 0.0f}, FVector{Extreme, 0.0f, 0.0f}),
        Get_DynamicUnionEdge(Linear, FVector{-Extreme, 0.0f, 0.0f}, FVector{Extreme, 0.0f, 0.0f}));

    const auto Empty = FCk_GroundNav_DynamicObstacleSnapshot{};
    const auto EmptyCopy = Empty;
    CheckEqual(*this, TEXT("default empty snapshot"), Get_DynamicUnionEdge(Empty, FVector::ZeroVector, FVector{10.0f, 0.0f, 0.0f}),
        Get_DynamicUnionEdge(EmptyCopy, FVector::ZeroVector, FVector{10.0f, 0.0f, 0.0f}));

    constexpr auto Iterations = 200;
    auto BenchmarkEdges = TArray<TPair<FVector, FVector>>{};
    BenchmarkEdges.Reserve(Iterations);
    const auto HitStart = Discs[0]._Centre;
    BenchmarkEdges.Add({HitStart, HitStart + FVector{25.0f, 0.0f, 0.0f}});
    BenchmarkEdges.Add({FVector{-800.0f, -800.0f, 0.0f}, FVector{-775.0f, -800.0f, 0.0f}});
    for (auto Index = BenchmarkEdges.Num(); Index < Iterations; ++Index)
    {
        const auto Start = FVector{Random.FRandRange(-800.0f, 800.0f), Random.FRandRange(-800.0f, 800.0f),
            Random.FRandRange(-25.0f, 25.0f)};
        BenchmarkEdges.Add({Start, Start + FVector{25.0f, 0.0f, 0.0f}});
    }
    const auto BenchmarkStart = FPlatformTime::Seconds();
    auto IndexedAnswers = TArray<TOptional<ECk_GroundNav_DynamicUnionEdge>>{};
    IndexedAnswers.Reserve(Iterations);
    for (auto Index = 0; Index < Iterations; ++Index)
    {
        IndexedAnswers.Add(Get_DynamicUnionEdge(Indexed, BenchmarkEdges[Index].Key, BenchmarkEdges[Index].Value));
    }
    const auto IndexedMilliseconds = (FPlatformTime::Seconds() - BenchmarkStart) * 1000.0;
    const auto LinearBenchmarkStart = FPlatformTime::Seconds();
    auto LinearAnswers = TArray<TOptional<ECk_GroundNav_DynamicUnionEdge>>{};
    LinearAnswers.Reserve(Iterations);
    for (auto Index = 0; Index < Iterations; ++Index)
    {
        LinearAnswers.Add(Get_DynamicUnionEdge(Linear, BenchmarkEdges[Index].Key, BenchmarkEdges[Index].Value));
    }
    const auto LinearMilliseconds = (FPlatformTime::Seconds() - LinearBenchmarkStart) * 1000.0;
    auto HasHit = false;
    auto HasClear = false;
    for (auto Index = 0; Index < Iterations; ++Index)
    {
        if (NOT TestTrue(TEXT("each indexed benchmark edge is valid"), IndexedAnswers[Index].IsSet()) ||
            NOT TestTrue(TEXT("each forced-linear benchmark edge is valid"), LinearAnswers[Index].IsSet()))
        { return false; }
        if (NOT TestEqual(TEXT("each benchmark edge preserves its exact union answer"),
            LinearAnswers[Index].GetValue(), IndexedAnswers[Index].GetValue()))
        { return false; }
        HasHit |= IndexedAnswers[Index].GetValue() != ECk_GroundNav_DynamicUnionEdge::Clear;
        HasClear |= IndexedAnswers[Index].GetValue() == ECk_GroundNav_DynamicUnionEdge::Clear;
    }
    TestTrue(TEXT("the local benchmark contains blocked or inside edges"), HasHit);
    TestTrue(TEXT("the local benchmark contains clear edges"), HasClear);
    AddInfo(FString::Printf(TEXT("Dynamic obstacle broad phase: indexed %.3f ms, linear %.3f ms over %d identical edges."),
        IndexedMilliseconds, LinearMilliseconds, Iterations));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
