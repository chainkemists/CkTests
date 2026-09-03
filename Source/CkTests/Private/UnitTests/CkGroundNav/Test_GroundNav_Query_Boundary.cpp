// Asking the field where the walls are, and the one answer a steering consumer cannot check for
// itself.
//
// A boundary query is read by avoidance code that has no other source of truth about the geometry
// around it: whatever the query says is a wall IS the wall, so a run returned from another storey, a
// run that is further than it claims, or a cap that keeps the wrong three would each steer a body into
// something it never saw. The agreement with brute force is therefore stated over ten thousand seeded
// points rather than a handful — an index that drops a bucket at a tile boundary is exactly what a
// hand-picked set does not contain — and the remaining tests pin the shape around it: a wall is found
// within a cell of its own face, a cap is a prefix of the uncapped answer, another storey's rim is not
// a wall, and open floor is an empty SUCCESS rather than a failure.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Boundary.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_boundary
{
    using ck::groundnav::FCk_GroundNav_BoundaryQuery;
    using ck::groundnav::FCk_GroundNav_BoundarySegment;
    using ck::groundnav::FCk_GroundNav_ClosestBoundaryQuery;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::Get_BoundarySegments;
    using ck::groundnav::Get_ClosestBoundary;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_ProjectPoint;

    using ck_test_groundnav_queryfixtures::Bake_FlatScene;
    using ck_test_groundnav_queryfixtures::Bake_QueryScene;
    using ck_test_groundnav_queryfixtures::Make_RandomPointsOverField;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::kWallMinX;

    // The vertical window that separates the ground from the deck 260 uu above it. Nothing in the
    // fixture sits near its edge, so no assertion here rests on which side of the window a run falls.
    constexpr auto kWindow = 50.0f;

    constexpr auto kRoomRadius = 300.0f;
    constexpr auto kStoreyRadius = 300.0f;

    // The room query: west of the dividing wall, with the wall's west face 200 uu away and the field
    // rim no nearer than 500 in any direction.
    constexpr auto kRoomProbeX = 500.0;
    constexpr auto kRoomProbeY = 800.0;

    // Under the raised deck and inside its footprint, so ONE point asks both storeys: the ground here
    // has the dividing wall 250 uu away, and the deck above it has its own west rim 50 uu away.
    constexpr auto kStoreyProbeX = 1050.0;
    constexpr auto kStoreyProbeY = 450.0;
    constexpr auto kStoreyDeckZ = 262.0;

    constexpr auto kGroundCeilingZ = 100.0;
    constexpr auto kDeckFloorZ = 200.0;

    constexpr auto kCapSegments = 3;

    constexpr auto kBruteForcePointCount = 10000;
    constexpr auto kBruteForceSeed = 20260902;
    constexpr auto kBruteForceRadius = 2000.0f;

    // Endpoints and the closest point are derived from the same integer cell lines, so the only slack
    // allowed anywhere here is the float-to-double widening of a stored height.
    constexpr auto kDistanceTolerance = 1.0e-3;

    // The projection that turns a random point in the slab into a place a body is actually standing.
    constexpr auto kProjectionExtentUu = 100.0f;
    constexpr auto kProjectionReachUu = 300.0f;

    // Well inside the flat scene's single tile: its own rim is 400 uu away in every direction, which
    // is four times the radius asked for.
    constexpr auto kFlatProbeX = 400.0;
    constexpr auto kFlatProbeY = 400.0;
    constexpr auto kFlatProbeRadius = 100.0f;

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_BoundaryQuery(
        const FVector& InLocation,
        float          InRadiusUu,
        int32          InMaxSegments) -> FCk_GroundNav_BoundaryQuery
    {
        auto Query = FCk_GroundNav_BoundaryQuery{};

        Query._Location = InLocation;
        Query._RadiusUu = InRadiusUu;
        Query._VerticalWindowUu = kWindow;
        Query._MaxSegments = InMaxSegments;

        return Query;
    }

    auto Get_DistanceToSegmentXY(
        const FCk_GroundNav_BoundarySegment& InSegment,
        const FVector2D&                     InPoint) -> double
    {
        constexpr auto kDegenerateLengthSquared = 1.0e-12;

        const auto Start = FVector2D{InSegment._Start.X, InSegment._Start.Y};
        const auto End = FVector2D{InSegment._End.X, InSegment._End.Y};
        const auto Along = End - Start;
        const auto LengthSquared = Along.SizeSquared();

        if (LengthSquared <= kDegenerateLengthSquared)
        { return FVector2D::Distance(Start, InPoint); }

        const auto Alpha = FMath::Clamp(FVector2D::DotProduct(InPoint - Start, Along) / LengthSquared, 0.0, 1.0);

        return FVector2D::Distance(Start + (Along * Alpha), InPoint);
    }

    auto Get_SegmentsAreIdentical(
        const FCk_GroundNav_BoundarySegment& InLeft,
        const FCk_GroundNav_BoundarySegment& InRight) -> bool
    {
        return InLeft._PlateIndex == InRight._PlateIndex &&
               InLeft._LayerIndex == InRight._LayerIndex &&
               InLeft._Side == InRight._Side &&
               InLeft._FromCell == InRight._FromCell &&
               InLeft._ToCell == InRight._ToCell &&
               InLeft._Start == InRight._Start &&
               InLeft._End == InRight._End &&
               InLeft._InwardNormalXY == InRight._InwardNormalXY;
    }

    auto Get_XY(
        const FVector& InLocation) -> FVector2D
    {
        return FVector2D{InLocation.X, InLocation.Y};
    }

    /** Whether a run's own height band lies within the window of a query height. */
    auto Get_IsInsideWindow(
        const FCk_GroundNav_BoundarySegment& InSegment,
        double                               InReferenceZ,
        double                               InWindowUu) -> bool
    {
        const auto MinZ = FMath::Min(InSegment._Start.Z, InSegment._End.Z);
        const auto MaxZ = FMath::Max(InSegment._Start.Z, InSegment._End.Z);

        return FMath::Abs(FMath::Clamp(InReferenceZ, MinZ, MaxZ) - InReferenceZ) <= InWindowUu;
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FBruteForceAnswer
    {
        double _DistanceUu = 0.0;
        bool _Found = false;
    };

    /**
     * The nearest run to a point over EVERY run of every built tile, with no index and no early out.
     *
     * The same filters the query states: the reachability component the point stands on, the vertical
     * window, and the search radius. Deliberately the slowest possible formulation — the point of it is
     * that it cannot share a bug with the bucketed ring walk it is checking.
     */
    auto Get_ClosestBoundaryByBruteForce(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation,
        int32                      InLabel,
        double                     InMaxRadiusUu,
        double                     InWindowUu) -> FBruteForceAnswer
    {
        const auto PointXY = Get_XY(InLocation);

        auto Answer = FBruteForceAnswer{};

        const auto Do_Consider = [&](int32 InTileIndex, const FCk_GroundNav_BoundarySegment& InSegment) -> void
        {
            if (InField.Get_ReachabilityLabel(InTileIndex, InSegment._PlateIndex) != InLabel)
            { return; }

            if (NOT Get_IsInsideWindow(InSegment, InLocation.Z, InWindowUu))
            { return; }

            const auto Distance = Get_DistanceToSegmentXY(InSegment, PointXY);

            if (Distance > InMaxRadiusUu)
            { return; }

            if (NOT Answer._Found || Distance < Answer._DistanceUu)
            {
                Answer._DistanceUu = Distance;
                Answer._Found = true;
            }
        };

        for (auto TileIndex = 0; TileIndex < InField._Tiles.Num(); ++TileIndex)
        {
            if (NOT InField._Tiles[TileIndex].Get_IsBuilt())
            { continue; }

            for (const auto& Segment : InField._Tiles[TileIndex]._Boundary._Segments)
            { Do_Consider(TileIndex, Segment); }

            for (const auto& Segment : InField.Get_TileEdgeBoundary(TileIndex))
            { Do_Consider(TileIndex, Segment); }
        }

        return Answer;
    }

    auto Make_Projection(
        const FVector& InLocation) -> FCk_GroundNav_ProjectionQuery
    {
        auto Query = FCk_GroundNav_ProjectionQuery{};

        Query._Location = InLocation;
        Query._HorizontalExtentUu = kProjectionExtentUu;
        Query._UpExtentUu = kProjectionReachUu;
        Query._DownExtentUu = kProjectionReachUu;
        Query._Mode = ECk_NavSurface_ProjectionMode::Closest;

        return Query;
    }

    auto Make_IsNavigableQuery(
        const FVector& InLocation) -> FCk_GroundNav_IsNavigableQuery
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStepHeight;

        return Query;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_QueryBoundary_RoomWallsAreReturnedWithinACell,
    "CkTests.UnitTests.CkGroundNav.Query.Boundary_RoomWallsAreReturnedWithinACell",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_QueryBoundary_RoomWallsAreReturnedWithinACell::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Location = FVector{kRoomProbeX, kRoomProbeY, 0.0};

    auto Segments = TArray<FCk_GroundNav_BoundarySegment>{};

    const auto Status = Get_BoundarySegments(Field, Make_BoundaryQuery(Location, kRoomRadius, 0), Segments);

    if (NOT TestEqual(TEXT("a point on open ground west of the wall answers Success"),
        Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    const auto PointXY = Get_XY(Location);

    auto WallFacingRuns = 0;
    auto OutOfRange = 0;
    auto OutOfOrder = 0;

    auto PreviousDistance = 0.0;

    for (const auto& Segment : Segments)
    {
        const auto Distance = Get_DistanceToSegmentXY(Segment, PointXY);

        if (Distance > kRoomRadius + kDistanceTolerance)
        { ++OutOfRange; }

        if (Distance + kDistanceTolerance < PreviousDistance)
        { ++OutOfOrder; }

        PreviousDistance = Distance;

        const auto FacesWest = Segment._InwardNormalXY.Equals(FVector2D{-1.0, 0.0}, kDistanceTolerance);

        if (FacesWest && FMath::Abs(Segment._Start.X - kWallMinX) <= kCellSize)
        { ++WallFacingRuns; }
    }

    const auto Report = FString::Printf(
        TEXT("segments %d, wall-facing %d, out of range %d, out of order %d"),
        Segments.Num(), WallFacingRuns, OutOfRange, OutOfOrder);

    ck::groundnav::Display(TEXT("{}"), Report);

    // The wall's west face is a cell line, and the run that walls the room ends on it — so this is
    // "within a cell", not "somewhere over there".
    TestTrue(FString::Printf(TEXT("the dividing wall is returned within a cell of its own face [%s]"), *Report),
        WallFacingRuns > 0);

    TestEqual(FString::Printf(TEXT("no returned run lies outside the query radius [%s]"), *Report),
        OutOfRange, 0);
    TestEqual(FString::Printf(TEXT("and the answer is ordered nearest first [%s]"), *Report),
        OutOfOrder, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_QueryBoundary_CapKeepsTheNearestFirst,
    "CkTests.UnitTests.CkGroundNav.Query.Boundary_CapKeepsTheNearestFirst",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_QueryBoundary_CapKeepsTheNearestFirst::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Location = FVector{kRoomProbeX, kRoomProbeY, 0.0};

    auto Uncapped = TArray<FCk_GroundNav_BoundarySegment>{};
    auto UncappedAgain = TArray<FCk_GroundNav_BoundarySegment>{};
    auto Capped = TArray<FCk_GroundNav_BoundarySegment>{};

    const auto UncappedStatus =
        Get_BoundarySegments(Field, Make_BoundaryQuery(Location, kRoomRadius, 0), Uncapped);
    const auto UncappedAgainStatus =
        Get_BoundarySegments(Field, Make_BoundaryQuery(Location, kRoomRadius, 0), UncappedAgain);
    const auto CappedStatus =
        Get_BoundarySegments(Field, Make_BoundaryQuery(Location, kRoomRadius, kCapSegments), Capped);

    if (NOT TestEqual(TEXT("the uncapped query succeeds"), UncappedStatus, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestEqual(TEXT("the capped query succeeds too"), CappedStatus, ECk_NavSurface_QueryStatus::Success);
    TestEqual(TEXT("two identical calls agree on their status"), UncappedAgainStatus, UncappedStatus);

    auto RepeatMismatches = 0;

    if (Uncapped.Num() != UncappedAgain.Num())
    { RepeatMismatches = FMath::Abs(Uncapped.Num() - UncappedAgain.Num()); }
    else
    {
        for (auto Index = 0; Index < Uncapped.Num(); ++Index)
        {
            if (NOT Get_SegmentsAreIdentical(Uncapped[Index], UncappedAgain[Index]))
            { ++RepeatMismatches; }
        }
    }

    TestEqual(FString::Printf(TEXT("two identical calls return identical segments (%d differ)"), RepeatMismatches),
        RepeatMismatches, 0);

    const auto ExpectedCount = FMath::Min(kCapSegments, Uncapped.Num());

    if (NOT TestEqual(FString::Printf(TEXT("the cap keeps %d of the %d runs in range"),
        ExpectedCount, Uncapped.Num()), Capped.Num(), ExpectedCount))
    { return false; }

    auto PrefixMismatches = 0;

    for (auto Index = 0; Index < Capped.Num(); ++Index)
    {
        if (NOT Get_SegmentsAreIdentical(Capped[Index], Uncapped[Index]))
        { ++PrefixMismatches; }
    }

    // The cap is a truncation of one ordering, not a second ordering: a consumer that raises its cap
    // must see the answer it already had, extended.
    TestEqual(FString::Printf(TEXT("a capped answer is the prefix of the uncapped one (%d differ)"),
        PrefixMismatches), PrefixMismatches, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_QueryBoundary_AnotherStoreysRimIsNotAWall,
    "CkTests.UnitTests.CkGroundNav.Query.Boundary_AnotherStoreysRimIsNotAWall",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_QueryBoundary_AnotherStoreysRimIsNotAWall::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    auto GroundSegments = TArray<FCk_GroundNav_BoundarySegment>{};
    auto DeckSegments = TArray<FCk_GroundNav_BoundarySegment>{};

    const auto GroundStatus = Get_BoundarySegments(Field,
        Make_BoundaryQuery(FVector{kStoreyProbeX, kStoreyProbeY, 0.0}, kStoreyRadius, 0), GroundSegments);

    const auto DeckStatus = Get_BoundarySegments(Field,
        Make_BoundaryQuery(FVector{kStoreyProbeX, kStoreyProbeY, kStoreyDeckZ}, kStoreyRadius, 0), DeckSegments);

    if (NOT TestEqual(TEXT("the ground under the deck answers Success"),
        GroundStatus, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    if (NOT TestEqual(TEXT("the deck above it answers Success"),
        DeckStatus, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    auto DeckRunsInGroundAnswer = 0;
    auto GroundRunsInDeckAnswer = 0;

    for (const auto& Segment : GroundSegments)
    {
        if (Segment._Start.Z > kGroundCeilingZ)
        { ++DeckRunsInGroundAnswer; }
    }

    for (const auto& Segment : DeckSegments)
    {
        if (Segment._Start.Z <= kDeckFloorZ)
        { ++GroundRunsInDeckAnswer; }
    }

    const auto Report = FString::Printf(
        TEXT("ground answer %d runs (%d from above), deck answer %d runs (%d from below)"),
        GroundSegments.Num(), DeckRunsInGroundAnswer, DeckSegments.Num(), GroundRunsInDeckAnswer);

    ck::groundnav::Display(TEXT("{}"), Report);

    // Both halves have to find something, or the exclusions below are true of nothing: the ground has
    // the dividing wall 250 uu away and the deck has its own rim 50 uu away, both inside the radius.
    if (NOT TestTrue(FString::Printf(TEXT("both storeys have walls in range [%s]"), *Report),
        GroundSegments.Num() > 0 && DeckSegments.Num() > 0))
    { return false; }

    TestEqual(FString::Printf(TEXT("standing on the ground, the deck's rim is not a wall [%s]"), *Report),
        DeckRunsInGroundAnswer, 0);
    TestEqual(FString::Printf(TEXT("standing on the deck, the ground's walls are not walls [%s]"), *Report),
        GroundRunsInDeckAnswer, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_QueryBoundary_ClosestEdgeAgreesWithBruteForce,
    "CkTests.UnitTests.CkGroundNav.Query.Boundary_ClosestEdgeAgreesWithBruteForceOver10kPoints",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_QueryBoundary_ClosestEdgeAgreesWithBruteForce::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Points = Make_RandomPointsOverField(Field, kBruteForcePointCount, kBruteForceSeed);

    auto NotOnAnySurface = 0;
    auto NoBoundaryInRange = 0;
    auto Compared = 0;
    auto DistanceMismatches = 0;
    auto ClosestPointOffItsSegment = 0;
    auto WorstDistanceDelta = 0.0;

    for (const auto& Point : Points)
    {
        const auto Projection = Get_ProjectPoint(Field, Make_Projection(Point));

        if (NOT Projection.Get_IsSuccess())
        {
            ++NotOnAnySurface;
            continue;
        }

        const auto Standing = Projection._Location;
        const auto Navigable = Get_IsNavigable(Field, Make_IsNavigableQuery(Standing));

        if (NOT Navigable.Get_IsSuccess())
        {
            ++NotOnAnySurface;
            continue;
        }

        auto Query = FCk_GroundNav_ClosestBoundaryQuery{};
        Query._Location = Standing;
        Query._MaxRadiusUu = kBruteForceRadius;
        Query._VerticalWindowUu = kWindow;

        const auto Result = Get_ClosestBoundary(Field, Query);

        if (NOT Result.Get_IsSuccess())
        {
            ++NoBoundaryInRange;
            continue;
        }

        ++Compared;

        const auto Label = Field.Get_ReachabilityLabel(
            Navigable._Surface._TileIndex, Navigable._Surface._PlateIndex);

        const auto Brute = Get_ClosestBoundaryByBruteForce(
            Field, Standing, Label, kBruteForceRadius, kWindow);

        const auto Delta = Brute._Found
            ? FMath::Abs(static_cast<double>(Result._DistanceUu) - Brute._DistanceUu)
            : TNumericLimits<double>::Max();

        if (NOT Brute._Found || Delta > kDistanceTolerance)
        { ++DistanceMismatches; }

        if (Brute._Found)
        { WorstDistanceDelta = FMath::Max(WorstDistanceDelta, Delta); }

        if (Get_DistanceToSegmentXY(Result._Segment, Get_XY(Result._ClosestPoint)) > kDistanceTolerance)
        { ++ClosestPointOffItsSegment; }
    }

    const auto Report = FString::Printf(
        TEXT("points %d, compared %d, not on a surface %d, no boundary in range %d, ")
        TEXT("distance mismatches %d (worst delta %.6f), closest point off its run %d"),
        Points.Num(), Compared, NotOnAnySurface, NoBoundaryInRange,
        DistanceMismatches, WorstDistanceDelta, ClosestPointOffItsSegment);

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestTrue(FString::Printf(TEXT("the sample reaches the ground often enough to mean something [%s]"),
        *Report), Compared > 0))
    { return false; }

    // The bucketed ring walk and the exhaustive scan are two independent routes to one number. They
    // are compared exactly, not within a tolerance: a ring that stops one bucket early is off by a
    // real distance, and a test that accepted "close enough" would pass straight through it.
    TestEqual(FString::Printf(TEXT("the indexed answer is the exhaustive answer at every point [%s]"), *Report),
        DistanceMismatches, 0);

    TestEqual(FString::Printf(TEXT("and the closest point it reports lies on the run it names [%s]"), *Report),
        ClosestPointOffItsSegment, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_QueryBoundary_OpenFloorFarFromWallsIsAnEmptySuccess,
    "CkTests.UnitTests.CkGroundNav.Query.Boundary_OpenFloorFarFromWallsIsAnEmptySuccess",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_QueryBoundary_OpenFloorFarFromWallsIsAnEmptySuccess::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(Field)))
    { return false; }

    auto Segments = TArray<FCk_GroundNav_BoundarySegment>{};

    const auto Status = Get_BoundarySegments(Field,
        Make_BoundaryQuery(FVector{kFlatProbeX, kFlatProbeY, 0.0}, kFlatProbeRadius, 0), Segments);

    // No walls in range is an ANSWER, not a failure: a consumer that read NoSurface here would treat
    // the middle of an open room as a place it knows nothing about.
    TestEqual(TEXT("the middle of an open floor answers Success"),
        Status, ECk_NavSurface_QueryStatus::Success);

    TestEqual(FString::Printf(TEXT("with no runs at all (%d returned)"), Segments.Num()),
        Segments.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
