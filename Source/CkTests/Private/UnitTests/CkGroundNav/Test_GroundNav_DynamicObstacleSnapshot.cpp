#include "CkGroundNav/Query/CkGroundNav_Query_DynamicObstacles.h"

#include "../CkUnitTest_Common.h"

#include <limits>
#include <cmath>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_dynamicobstacles
{
    using ck::groundnav::ECk_GroundNav_DynamicUnionEdge;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleDisc;
    using ck::groundnav::FCk_GroundNav_DynamicObstacleObb;
    using ck::groundnav::Get_DynamicUnionEdge;
    using ck::groundnav::Get_IsDynamicObstacleCoveringCell;
    using ck::groundnav::Try_MakeDynamicObstacleSnapshot;

    auto Make_Disc(FVector InCentre, float InRadius, float InVerticalHalfExtent) -> FCk_GroundNav_DynamicObstacleDisc
    {
        return FCk_GroundNav_DynamicObstacleDisc{InCentre, InRadius, InVerticalHalfExtent};
    }

    auto Make_Obb(FVector InCentre, float InYawDegrees, FVector InHalfExtents) -> FCk_GroundNav_DynamicObstacleObb
    {
        return FCk_GroundNav_DynamicObstacleObb{
            FTransform{FRotator{0.0f, InYawDegrees, 0.0f}, InCentre, FVector::OneVector}, InHalfExtents};
    }

    auto Get_Snapshot(
        FAutomationTestBase& InTest,
        TArray<FCk_GroundNav_DynamicObstacleDisc> InDiscs = {},
        TArray<FCk_GroundNav_DynamicObstacleObb>  InObbs = {})
        -> ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot
    {
        const auto Snapshot = Try_MakeDynamicObstacleSnapshot(InDiscs, InObbs);
        InTest.TestTrue(TEXT("a valid obstacle snapshot is constructed"), Snapshot.IsSet());
        return Snapshot.IsSet() ? Snapshot.GetValue() : ck::groundnav::FCk_GroundNav_DynamicObstacleSnapshot{};
    }

    template <typename Type>
    auto Get_Value(FAutomationTestBase& InTest, const TOptional<Type>& InOptional) -> Type
    {
        InTest.TestTrue(TEXT("a valid obstacle query returns a value"), InOptional.IsSet());
        return InOptional.IsSet() ? InOptional.GetValue() : Type{};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_DynamicObstacleSnapshot,
    "CkTests.UnitTests.CkGroundNav.Query.DynamicObstacleSnapshot",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_DynamicObstacleSnapshot::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_dynamicobstacles;

    const auto Empty = Get_Snapshot(*this);
    TestTrue(TEXT("the empty validated snapshot is constructed"),
        Try_MakeDynamicObstacleSnapshot(
            TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{},
            TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{}).IsSet());
    TestTrue(TEXT("the empty snapshot carries no obstacles"), Empty.Get_IsEmpty());
    TestEqual(TEXT("an empty snapshot leaves a finite cell clear"),
        Get_Value(*this, Get_IsDynamicObstacleCoveringCell(Empty, FVector2D::ZeroVector, 10.0f, 0.0f)), false);
    TestEqual(TEXT("an empty snapshot leaves a finite edge clear"),
        Get_Value(*this, Get_DynamicUnionEdge(Empty, FVector::ZeroVector, FVector{10.0f, 0.0f, 0.0f})),
        ECk_GroundNav_DynamicUnionEdge::Clear);

    const auto ValidDisc = Make_Disc(FVector::ZeroVector, 10.0f, 5.0f);
    auto InvalidLaterDisc = ValidDisc;
    InvalidLaterDisc._RadiusUu = std::numeric_limits<float>::quiet_NaN();
    const auto AtomicDiscs = TArray<FCk_GroundNav_DynamicObstacleDisc>{ValidDisc, InvalidLaterDisc};
    TestFalse(TEXT("a malformed later disc rejects the complete snapshot"),
        Try_MakeDynamicObstacleSnapshot(AtomicDiscs, TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{}).IsSet());

    auto InvalidObb = Make_Obb(FVector::ZeroVector, 0.0f, FVector{10.0f, 10.0f, 10.0f});
    InvalidObb._WorldHalfExtents.Z = 0.0f;
    const auto ValidDiscs = TArray<FCk_GroundNav_DynamicObstacleDisc>{ValidDisc};
    const auto InvalidObbs = TArray<FCk_GroundNav_DynamicObstacleObb>{InvalidObb};
    TestFalse(TEXT("a nonpositive OBB extent rejects the complete snapshot"),
        Try_MakeDynamicObstacleSnapshot(ValidDiscs, InvalidObbs).IsSet());
    auto NonUnitObb = Make_Obb(FVector::ZeroVector, 0.0f, FVector{10.0f, 10.0f, 10.0f});
    NonUnitObb._YawTransform.SetScale3D(FVector{2.0f, 1.0f, 1.0f});
    const auto NonUnitObbs = TArray<FCk_GroundNav_DynamicObstacleObb>{NonUnitObb};
    TestFalse(TEXT("a nonunit OBB transform is rejected"),
        Try_MakeDynamicObstacleSnapshot(
            TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{},
            NonUnitObbs).IsSet());
    auto TinyPitchObb = Make_Obb(FVector::ZeroVector, 0.0f, FVector{10.0f, 10.0f, 10.0f});
    TinyPitchObb._YawTransform.SetRotation(FQuat{FRotator{0.001f, 0.0f, 0.0f}});
    const auto TinyPitchObbs = TArray<FCk_GroundNav_DynamicObstacleObb>{TinyPitchObb};
    TestFalse(TEXT("a tiny non-yaw OBB rotation is rejected"),
        Try_MakeDynamicObstacleSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{}, TinyPitchObbs).IsSet());
    auto TinyScaleObb = Make_Obb(FVector::ZeroVector, 0.0f, FVector{10.0f, 10.0f, 10.0f});
    TinyScaleObb._YawTransform.SetScale3D(FVector{1.00001f, 1.0f, 1.0f});
    const auto TinyScaleObbs = TArray<FCk_GroundNav_DynamicObstacleObb>{TinyScaleObb};
    TestFalse(TEXT("a tiny nonunit OBB scale is rejected"),
        Try_MakeDynamicObstacleSnapshot(TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{}, TinyScaleObbs).IsSet());
    const auto Overflow = std::numeric_limits<double>::max();
    const auto BoundsOverflowObb = Make_Obb(FVector{Overflow, 0.0, 0.0}, 0.0f, FVector{Overflow, 1.0, 1.0});
    const auto BoundsOverflowObbs = TArray<FCk_GroundNav_DynamicObstacleObb>{BoundsOverflowObb};
    TestFalse(TEXT("a finite OBB whose bounds overflow is rejected"),
        Try_MakeDynamicObstacleSnapshot(
            TConstArrayView<FCk_GroundNav_DynamicObstacleDisc>{},
            BoundsOverflowObbs).IsSet());

    const auto Stacked = Get_Snapshot(*this, {Make_Disc(FVector{0.0f, 0.0f, 100.0f}, 10.0f, 50.0f)});
    TestEqual(TEXT("the lower closed Z boundary is covered"),
        Get_Value(*this, Get_IsDynamicObstacleCoveringCell(Stacked, FVector2D{-1.0f, -1.0f}, 2.0f, 50.0f)), true);
    TestEqual(TEXT("a surface below the finite disc box is clear"),
        Get_Value(*this, Get_IsDynamicObstacleCoveringCell(Stacked, FVector2D{-1.0f, -1.0f}, 2.0f, 49.0f)), false);
    TestEqual(TEXT("a tangent closed cell is covered"),
        Get_Value(*this, Get_IsDynamicObstacleCoveringCell(Get_Snapshot(*this, {ValidDisc}), FVector2D{10.0f, 0.0f}, 1.0f, 0.0f)), true);

    const auto RotatedObb = Make_Obb(FVector::ZeroVector, 45.0f, FVector{10.0f, 10.0f, 5.0f});
    const auto Rotated = Get_Snapshot(*this, {}, {RotatedObb});
    const auto RotatedTangent = RotatedObb._YawTransform.TransformPositionNoScale(FVector{10.0f, -10.0f, 0.0f});
    TestEqual(TEXT("a rotated OBB counts tangent cell contact"),
        Get_Value(*this, Get_IsDynamicObstacleCoveringCell(Rotated, FVector2D{RotatedTangent}, 1.0f, 0.0f)), true);

    const auto Overlap = Get_Snapshot(*this,
        {Make_Disc(FVector{-5.0f, 0.0f, 0.0f}, 8.0f, 5.0f)},
        {Make_Obb(FVector{5.0f, 0.0f, 0.0f}, 0.0f, FVector{8.0f, 3.0f, 5.0f})});
    TestEqual(TEXT("overlapping disc and OBB form one continuous initial union"),
        Get_Value(*this, Get_DynamicUnionEdge(Overlap, FVector{-10.0f, 0.0f, 0.0f}, FVector{10.0f, 0.0f, 0.0f})),
        ECk_GroundNav_DynamicUnionEdge::InsideAll);
    const auto TangentUnion = Get_Snapshot(*this, {
        Make_Disc(FVector::ZeroVector, 5.0f, 5.0f),
        Make_Disc(FVector{10.0f, 0.0f, 0.0f}, 5.0f, 5.0f)});
    TestEqual(TEXT("closed tangent intervals merge into one escape union"),
        Get_Value(*this, Get_DynamicUnionEdge(TangentUnion, FVector{-5.0f, 0.0f, 0.0f}, FVector{15.0f, 0.0f, 0.0f})),
        ECk_GroundNav_DynamicUnionEdge::InsideAll);
    const auto NextFloat = std::nextafter(10.0f, std::numeric_limits<float>::infinity());
    const auto MinimalGap = Get_Snapshot(*this, {
        Make_Disc(FVector::ZeroVector, 5.0f, 5.0f),
        Make_Disc(FVector{NextFloat, 0.0f, 0.0f}, 5.0f, 5.0f)});
    TestEqual(TEXT("the smallest source-representable disc gap is not epsilon-bridged"),
        Get_Value(*this, Get_DynamicUnionEdge(MinimalGap, FVector{-5.0f, 0.0f, 0.0f}, FVector{15.0f, 0.0f, 0.0f})),
        ECk_GroundNav_DynamicUnionEdge::NonMonotonic);
    constexpr auto DoubleCentreGap = 1.0e-10;
    const auto DoubleCentreGapUnion = Get_Snapshot(*this, {
        Make_Disc(FVector::ZeroVector, 1.0f, 5.0f),
        Make_Disc(FVector{2.0 + DoubleCentreGap, 0.0, 0.0}, 1.0f, 5.0f)});
    TestEqual(TEXT("a positive double-precision centre gap smaller than float t precision remains separate"),
        Get_Value(*this, Get_DynamicUnionEdge(
            DoubleCentreGapUnion, FVector{-1.0, 0.0, 0.0}, FVector{3.0 + DoubleCentreGap, 0.0, 0.0})),
        ECk_GroundNav_DynamicUnionEdge::NonMonotonic);

    const auto LargeDisc = Get_Snapshot(*this, {Make_Disc(FVector::ZeroVector, 126.0f, 5.0f)});
    TestEqual(TEXT("a large disc supports an initial multi-cell inside segment"),
        Get_Value(*this, Get_DynamicUnionEdge(LargeDisc, FVector::ZeroVector, FVector{100.0f, 0.0f, 0.0f})),
        ECk_GroundNav_DynamicUnionEdge::InsideAll);
    TestEqual(TEXT("the next segment can exit that same disc once"),
        Get_Value(*this, Get_DynamicUnionEdge(LargeDisc, FVector{100.0f, 0.0f, 0.0f}, FVector{200.0f, 0.0f, 0.0f})),
        ECk_GroundNav_DynamicUnionEdge::ExitsOnce);

    const auto Separated = Get_Snapshot(*this, {
        Make_Disc(FVector{-5.0f, 0.0f, 0.0f}, 2.0f, 5.0f),
        Make_Disc(FVector{5.0f, 0.0f, 0.0f}, 2.0f, 5.0f)});
    TestEqual(TEXT("separated blockers cannot be bridged by escape"),
        Get_Value(*this, Get_DynamicUnionEdge(Separated, FVector{-6.0f, 0.0f, 0.0f}, FVector{6.0f, 0.0f, 0.0f})),
        ECk_GroundNav_DynamicUnionEdge::NonMonotonic);
    TestEqual(TEXT("a clear start that enters a blocker is not an escape edge"),
        Get_Value(*this, Get_DynamicUnionEdge(LargeDisc, FVector{200.0f, 0.0f, 0.0f}, FVector::ZeroVector)),
        ECk_GroundNav_DynamicUnionEdge::NonMonotonic);

    TestFalse(TEXT("a nonfinite cell query is rejected"),
        Get_IsDynamicObstacleCoveringCell(Empty, FVector2D{std::numeric_limits<float>::quiet_NaN(), 0.0f}, 1.0f, 0.0f).IsSet());
    TestFalse(TEXT("a zero-size cell query is rejected"),
        Get_IsDynamicObstacleCoveringCell(Empty, FVector2D::ZeroVector, 0.0f, 0.0f).IsSet());
    TestFalse(TEXT("a collapsed finite cell maximum is rejected"),
        Get_IsDynamicObstacleCoveringCell(Empty, FVector2D{std::numeric_limits<double>::max(), 0.0}, 1.0f, 0.0f).IsSet());
    TestFalse(TEXT("a nonfinite edge query is rejected"),
        Get_DynamicUnionEdge(Empty, FVector::ZeroVector, FVector{std::numeric_limits<float>::infinity(), 0.0f, 0.0f}).IsSet());
    TestFalse(TEXT("a finite edge whose delta overflows is rejected"),
        Get_DynamicUnionEdge(Empty, FVector{-Overflow, 0.0, 0.0}, FVector{Overflow, 0.0, 0.0}).IsSet());

    auto MutableInput = TArray<FCk_GroundNav_DynamicObstacleDisc>{Make_Disc(FVector::ZeroVector, 10.0f, 5.0f)};
    const auto Copied = Get_Value(*this, Try_MakeDynamicObstacleSnapshot(
        MutableInput, TConstArrayView<FCk_GroundNav_DynamicObstacleObb>{}));
    MutableInput[0]._RadiusUu = 0.0f;
    TestFalse(TEXT("copying retains an immutable nonempty snapshot"), Copied.Get_IsEmpty());
    TestEqual(TEXT("copying retains every disc"), Copied.Get_Discs().Num(), 1);
    TestEqual(TEXT("the snapshot owns a source-array copy"),
        Get_Value(*this, Get_IsDynamicObstacleCoveringCell(Copied, FVector2D::ZeroVector, 1.0f, 0.0f)), true);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
