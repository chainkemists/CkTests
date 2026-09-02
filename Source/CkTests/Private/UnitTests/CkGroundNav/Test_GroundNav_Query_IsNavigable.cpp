// The column lookup, and the two promises that make it worth having beside projection.
//
// It has to AGREE with a projection of zero horizontal extent over the same reach, or a caller has two
// answers to one question and no way to tell which is the real one; and it has to be measurably
// CHEAPER, or there was never a reason to offer it. The first is pinned over ten thousand points
// rather than a handful, because a disagreement that only shows up over a hole, at a seam or under an
// overhang is exactly the one a hand-picked point set misses. The second is pinned on cells read
// rather than on time, because cells read is deterministic and time is a fact about this machine.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Query/CkGroundNav_Query_BuildStatus.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_isnavigable
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_IsNavigableResult;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_IsNavigable_Batch;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_RegionStatusAt;

    // Big enough that most points over the field find something, small enough that the agreement is
    // being tested over a real vertical window rather than the whole slab.
    constexpr auto kTolerance = 100.0f;

    constexpr auto kAgreementPointCount = 10000;
    constexpr auto kBatchPointCount = 500;

    constexpr auto kAgreementSeed = 20260902;
    constexpr auto kBatchSeed = 74113;

    auto Make_ColumnQuery(
        const FVector& InLocation,
        float          InTolerance,
        float          InRadius) -> FCk_GroundNav_IsNavigableQuery
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = InTolerance;
        Query._Agent._RadiusUu = InRadius;

        return Query;
    }

    /** The projection the column lookup claims to agree with: no ring, the same reach both ways. */
    auto Make_EquivalentProjection(
        const FVector& InLocation,
        float          InTolerance,
        float          InRadius) -> FCk_GroundNav_ProjectionQuery
    {
        auto Query = FCk_GroundNav_ProjectionQuery{};

        Query._Location = InLocation;
        Query._HorizontalExtentUu = 0.0f;
        Query._UpExtentUu = InTolerance;
        Query._DownExtentUu = InTolerance;
        Query._Mode = ECk_NavSurface_ProjectionMode::Closest;
        Query._Agent._RadiusUu = InRadius;

        return Query;
    }

    auto Make_MixedColumnQuery(const FVector& InLocation, int32 InIndex) -> FCk_GroundNav_IsNavigableQuery
    {
        constexpr float Tolerances[] = {0.0f, 25.0f, 100.0f, 250.0f};
        constexpr float Radii[] = {0.0f, 20.0f, 60.0f, 120.0f};

        return Make_ColumnQuery(InLocation, Tolerances[InIndex % 4], Radii[(InIndex + 1) % 4]);
    }

    auto Get_ResultsMatch(
        const FCk_GroundNav_IsNavigableResult& InLeft,
        const FCk_GroundNav_IsNavigableResult& InRight) -> bool
    {
        return InLeft._Status == InRight._Status &&
               InLeft._Surface == InRight._Surface &&
               InLeft._SurfaceZUu == InRight._SurfaceZUu &&
               InLeft._ClearanceUu == InRight._ClearanceUu &&
               InLeft._Cost._CellsRead == InRight._Cost._CellsRead;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_IsNavigable_AgreesWithZeroExtentProjectionOver10kPoints,
    "CkTests.UnitTests.CkGroundNav.Query.IsNavigable_AgreesWithZeroExtentProjectionOver10kPoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_IsNavigable_AgreesWithZeroExtentProjectionOver10kPoints::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_isnavigable;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Points = Make_RandomPointsOverField(Field, kAgreementPointCount, kAgreementSeed);

    auto StatusMismatches = 0;
    auto SurfaceMismatches = 0;
    auto SuccessCount = 0;
    auto FirstMismatch = int32{INDEX_NONE};

    for (auto Index = 0; Index < Points.Num(); ++Index)
    {
        const auto Column = Get_IsNavigable(Field, Make_ColumnQuery(Points[Index], kTolerance, 0.0f));
        const auto Projected = Get_ProjectPoint(
            Field, Make_EquivalentProjection(Points[Index], kTolerance, 0.0f));

        auto Agrees = true;

        if (Column._Status != Projected._Status)
        {
            ++StatusMismatches;
            Agrees = false;
        }
        else if (Column.Get_IsSuccess())
        {
            ++SuccessCount;

            if (NOT (Column._Surface == Projected._Surface))
            {
                ++SurfaceMismatches;
                Agrees = false;
            }
        }

        if (NOT Agrees && FirstMismatch == INDEX_NONE)
        { FirstMismatch = Index; }
    }

    const auto Report = FString::Printf(
        TEXT("agreement over %d points: %d status disagreements, %d surface disagreements, %d agreed successes, first disagreement at %d"),
        Points.Num(), StatusMismatches, SurfaceMismatches, SuccessCount, FirstMismatch);

    ck::groundnav::Display(TEXT("{}"), Report);

    // A point set that found nothing would agree trivially, so the sample has to be shown to be worth
    // something before its agreement means anything.
    if (NOT TestTrue(FString::Printf(TEXT("the sample actually stands on ground somewhere [%s]"), *Report),
        SuccessCount > 0))
    { return false; }

    TestEqual(FString::Printf(TEXT("the column lookup and a zero-extent projection never disagree on status [%s]"), *Report),
        StatusMismatches, 0);

    TestEqual(FString::Printf(TEXT("nor on which surface they found [%s]"), *Report),
        SurfaceMismatches, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_IsNavigable_IsMeasuredCheaperThanProjection,
    "CkTests.UnitTests.CkGroundNav.Query.IsNavigable_IsMeasuredCheaperThanProjection",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_IsNavigable_IsMeasuredCheaperThanProjection::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_isnavigable;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Points = Make_RandomPointsOverField(Field, kAgreementPointCount, kAgreementSeed);

    // The projection is given a real horizontal extent, which is what a caller reaching for it instead
    // would have used. That ring is the whole difference the cheap sibling exists to avoid paying for.
    constexpr auto kProjectionExtent = 100.0f;

    auto ColumnCells = int64{0};
    auto ProjectionCells = int64{0};

    const auto ColumnStartedAt = FPlatformTime::Seconds();

    for (const auto& Point : Points)
    { ColumnCells += Get_IsNavigable(Field, Make_ColumnQuery(Point, kTolerance, 0.0f))._Cost._CellsRead; }

    const auto ColumnMilliseconds = (FPlatformTime::Seconds() - ColumnStartedAt) * 1000.0;

    const auto ProjectionStartedAt = FPlatformTime::Seconds();

    for (const auto& Point : Points)
    {
        auto Query = Make_EquivalentProjection(Point, kTolerance, 0.0f);
        Query._HorizontalExtentUu = kProjectionExtent;

        ProjectionCells += Get_ProjectPoint(Field, Query)._Cost._CellsRead;
    }

    const auto ProjectionMilliseconds = (FPlatformTime::Seconds() - ProjectionStartedAt) * 1000.0;

    const auto Report = FString::Printf(
        TEXT("over %d points: is-navigable read %lld cells in %.2f ms, projection at %.0f uu extent read %lld cells in %.2f ms"),
        Points.Num(), ColumnCells, ColumnMilliseconds, kProjectionExtent, ProjectionCells, ProjectionMilliseconds);

    // The wall times are this machine's and are reported, never asserted; the cell counts are the
    // field's own and are the same on every machine, which is why they are what the claim rests on.
    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestTrue(FString::Printf(TEXT("both forms read cells worth counting [%s]"), *Report),
        ColumnCells > 0 && ProjectionCells > 0))
    { return false; }

    TestTrue(FString::Printf(TEXT("and the column lookup reads strictly fewer of them [%s]"), *Report),
        ColumnCells < ProjectionCells);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_IsNavigable_OutsideEveryTileIsNoSurfaceNotUnbuilt,
    "CkTests.UnitTests.CkGroundNav.Query.IsNavigable_OutsideEveryTileIsNoSurfaceNotUnbuilt",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_IsNavigable_OutsideEveryTileIsNoSurfaceNotUnbuilt::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_isnavigable;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // Ground no tile covers will never be built, so a caller told Unbuilt here would wait forever.
    const auto FarAway = FVector{-5000.0, -5000.0, 0.0};

    const auto Result = Get_IsNavigable(Field, Make_ColumnQuery(FarAway, kTolerance, 0.0f));

    TestEqual(TEXT("a point no tile covers has nowhere to stand"),
        Result._Status, ECk_NavSurface_QueryStatus::NoSurface);

    TestTrue(TEXT("and is never called Unbuilt, because nothing is ever going to build it"),
        Result._Status != ECk_NavSurface_QueryStatus::Unbuilt);

    TestEqual(TEXT("the region status says the same thing in its own vocabulary"),
        Get_RegionStatusAt(Field, FarAway), ECk_GroundNav_RegionStatus::OutsideField);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_IsNavigable_BatchIsElementWiseIdenticalToSingles,
    "CkTests.UnitTests.CkGroundNav.Query.IsNavigable_BatchIsElementWiseIdenticalToSingles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_IsNavigable_BatchIsElementWiseIdenticalToSingles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_isnavigable;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Points = Make_RandomPointsOverField(Field, kBatchPointCount, kBatchSeed);

    auto Queries = TArray<FCk_GroundNav_IsNavigableQuery>{};
    Queries.Reserve(Points.Num());

    for (auto Index = 0; Index < Points.Num(); ++Index)
    { Queries.Emplace(Make_MixedColumnQuery(Points[Index], Index)); }

    auto BatchResults = TArray<FCk_GroundNav_IsNavigableResult>{};
    BatchResults.SetNum(Queries.Num());

    Get_IsNavigable_Batch(Field, Queries, BatchResults);

    auto MismatchCount = 0;
    auto FirstMismatch = int32{INDEX_NONE};

    for (auto Index = 0; Index < Queries.Num(); ++Index)
    {
        if (Get_ResultsMatch(Get_IsNavigable(Field, Queries[Index]), BatchResults[Index]))
        { continue; }

        ++MismatchCount;

        if (FirstMismatch == INDEX_NONE)
        { FirstMismatch = Index; }
    }

    TestEqual(FString::Printf(
        TEXT("every one of %d batched column lookups answers exactly as the single call does (first disagreement at %d)"),
        Queries.Num(), FirstMismatch),
        MismatchCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
