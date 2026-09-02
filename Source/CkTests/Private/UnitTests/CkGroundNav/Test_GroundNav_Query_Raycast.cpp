// Walking a straight segment over the ground without the slide, and the four things that makes it good for.
//
// A raycast is the walk with its recovery removed: the first refused step is the hit. So it answers a
// question a walk cannot — is this whole segment walkable — and every property it is worth having for
// is a property of that answer rather than of the traversal. It has to be CLEAR over open ground and
// bill the segment's own length as its cost; it has to hit a wall on the wall's plane rather than a
// cell or two early; it has to refuse for a body the gap beside a pillar cannot take while admitting
// one it can; it has to agree with itself run backwards, or a caller has two answers to one question;
// it must not leak between the deck and the ground underneath it, which is the failure a flat ground
// query cannot even represent; and it has to stop where the cost cap says rather than where the
// geometry does, with the flag saying which of the two stopped it.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_SurfaceWalk.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_raycast
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_IsNavigableResult;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::FCk_GroundNav_RaycastQuery;
    using ck::groundnav::FCk_GroundNav_RaycastResult;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_SurfaceRaycast;

    // A hit is placed on a cell boundary, so anything tighter than a cell is what a wrong cell would
    // have to beat and anything looser would let one through.
    constexpr auto kOneCellUu = static_cast<double>(ck_test_groundnav_queryfixtures::kCellSize);
    constexpr auto kPositionTolerance = 1.0e-3;

    // The normal is a lattice axis, so it is exact but for the float that carries it.
    constexpr auto kNormalTolerance = 1.0e-3;

    // The cost of a clear ray is the segment's own length, accumulated one cell at a time in float over
    // tens of cells. A bound of 1e-2 over a 700 uu segment is a relative 1.4e-5 — far tighter than any
    // off-by-a-cell error the assertion exists to catch, and clear of the accumulation's own noise.
    constexpr auto kCostTolerance = 1.0e-2;

    // Comfortably more than one cell height, so an end taken straight off a surface resolves to that
    // surface and to nothing else.
    constexpr auto kStartTolerance = 20.0f;

    constexpr auto kSymmetrySampleCount = 10000;
    constexpr auto kSymmetryPairCount = 200;
    constexpr auto kSymmetrySeed = 5150211;

    // Long enough to cross cells and meet the wall, the hole and the pillar; short enough that the
    // sample is not simply every segment blocked by something.
    constexpr auto kMinSegmentUu = 50.0;
    constexpr auto kMaxSegmentUu = 500.0;

    constexpr auto kStartSearchExtentUu = 100.0f;
    constexpr auto kStartSearchReachUu = 300.0f;

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Ray(
        const FVector& InStart,
        const FVector& InEnd,
        float          InRadiusUu,
        float          InMaxCost) -> FCk_GroundNav_RaycastQuery
    {
        auto Query = FCk_GroundNav_RaycastQuery{};

        Query._Start = InStart;
        Query._End = InEnd;
        Query._StartVerticalToleranceUu = kStartTolerance;
        Query._Agent._RadiusUu = InRadiusUu;
        Query._MaxCost = InMaxCost;

        return Query;
    }

    auto Make_ColumnQuery(
        const FVector& InLocation,
        float          InRadiusUu) -> FCk_GroundNav_IsNavigableQuery
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kStartTolerance;
        Query._Agent._RadiusUu = InRadiusUu;

        return Query;
    }

    auto Make_Projection(
        const FVector& InLocation) -> FCk_GroundNav_ProjectionQuery
    {
        auto Query = FCk_GroundNav_ProjectionQuery{};

        Query._Location = InLocation;
        Query._HorizontalExtentUu = kStartSearchExtentUu;
        Query._UpExtentUu = kStartSearchReachUu;
        Query._DownExtentUu = kStartSearchReachUu;
        Query._Mode = ECk_NavSurface_ProjectionMode::Closest;

        return Query;
    }

    /** The point on the ground under an XY, so a ray is stated in the plane it is actually walked in. */
    auto Get_GroundPoint(
        const FCk_GroundNav_Field&       InField,
        double                           InX,
        double                           InY,
        double                           InHeightHint,
        FCk_GroundNav_IsNavigableResult& OutColumn) -> FVector
    {
        OutColumn = Get_IsNavigable(InField, Make_ColumnQuery(FVector{InX, InY, InHeightHint}, 0.0f));

        return FVector{InX, InY, static_cast<double>(OutColumn._SurfaceZUu)};
    }

    auto Get_DistanceXY(
        const FVector& InLeft,
        const FVector& InRight) -> double
    {
        return FVector2D::Distance(
            FVector2D{InLeft.X, InLeft.Y}, FVector2D{InRight.X, InRight.Y});
    }

    /** How far a hit sits off the segment it was found on, in XY. A hit on the segment answers zero. */
    auto Get_DistanceToSegmentXY(
        const FVector& InStart,
        const FVector& InEnd,
        const FVector& InPoint) -> double
    {
        const auto Start = FVector2D{InStart.X, InStart.Y};
        const auto End = FVector2D{InEnd.X, InEnd.Y};
        const auto Point = FVector2D{InPoint.X, InPoint.Y};

        const auto Along = End - Start;
        const auto LengthSquared = Along.SizeSquared();

        if (LengthSquared <= 0.0)
        { return FVector2D::Distance(Point, Start); }

        const auto Fraction = FMath::Clamp(FVector2D::DotProduct(Point - Start, Along) / LengthSquared, 0.0, 1.0);

        return FVector2D::Distance(Point, Start + (Along * Fraction));
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Raycast_OpenPlaneIsClear,
    "CkTests.UnitTests.CkGroundNav.Query.Raycast_OpenPlaneIsClear",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Raycast_OpenPlaneIsClear::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_raycast;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(Field)))
    { return false; }

    auto StartColumn = FCk_GroundNav_IsNavigableResult{};
    auto EndColumn = FCk_GroundNav_IsNavigableResult{};

    // Both ends well inside the single 800 uu tile, so the only thing that can stop this ray is a
    // defect in the ray.
    const auto Start = Get_GroundPoint(Field, 200.0, 200.0, kGroundZ, StartColumn);
    const auto End = Get_GroundPoint(Field, 700.0, 700.0, kGroundZ, EndColumn);

    if (NOT TestTrue(TEXT("both ends of the diagonal stand on the flat floor"),
        StartColumn.Get_IsSuccess() && EndColumn.Get_IsSuccess()))
    { return false; }

    const auto Result = Get_SurfaceRaycast(Field, Make_Ray(Start, End, 0.0f, 0.0f));

    if (NOT TestTrue(FString::Printf(TEXT("a diagonal over open floor is clear (hit %s)"),
        *Result._HitLocation.ToString()),
        Result.Get_IsClear()))
    { return false; }

    TestTrue(FString::Printf(TEXT("with no hit normal, because nothing was hit (%s)"),
        *Result._HitNormal.ToString()),
        Result._HitNormal.IsNearlyZero());

    // Every cell of the flat scene carries a cost multiplier of one, so the accumulated cost IS the
    // segment's length — and a traversal that skipped or double-counted a cell could not report it.
    const auto SegmentLength = Get_DistanceXY(Start, End);

    TestTrue(FString::Printf(TEXT("billing the segment's own length as its cost (%.4f against %.4f)"),
        Result._AccumulatedCost, SegmentLength),
        FMath::Abs(static_cast<double>(Result._AccumulatedCost) - SegmentLength) <= kCostTolerance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Raycast_WallIsHitWithinOneCellOfItsPlane,
    "CkTests.UnitTests.CkGroundNav.Query.Raycast_WallIsHitWithinOneCellOfItsPlane",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Raycast_WallIsHitWithinOneCellOfItsPlane::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_raycast;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    auto StartColumn = FCk_GroundNav_IsNavigableResult{};

    const auto Start = Get_GroundPoint(Field, 600.0, 800.0, kGroundZ, StartColumn);
    const auto End = FVector{900.0, 800.0, Start.Z};

    if (NOT TestTrue(TEXT("the ray starts on the floor west of the wall"), StartColumn.Get_IsSuccess()))
    { return false; }

    const auto Result = Get_SurfaceRaycast(Field, Make_Ray(Start, End, 0.0f, 0.0f));

    if (NOT TestEqual(TEXT("a ray driven into the wall is blocked"),
        Result._Status, ECk_NavSurface_QueryStatus::Blocked))
    { return false; }

    TestFalse(TEXT("by the geometry rather than by a cost cap it was never given"), Result._StoppedOnCost);

    // The wall's west face is the east edge of the last walkable cell, so the hit belongs on that plane
    // and nowhere earlier: a hit a cell short is a body stopping in mid-air as far as a consumer knows.
    TestTrue(FString::Printf(TEXT("hitting no further east than the wall's plane (%.4f)"), Result._HitLocation.X),
        Result._HitLocation.X <= kWallMinX + kPositionTolerance);

    TestTrue(FString::Printf(TEXT("and within one cell of it (%.4f)"), Result._HitLocation.X),
        Result._HitLocation.X >= kWallMinX - kOneCellUu);

    TestTrue(FString::Printf(TEXT("with the crossed edge's normal facing back along the ray (%s)"),
        *Result._HitNormal.ToString()),
        Result._HitNormal.Equals(FVector{-1.0, 0.0, 0.0}, kNormalTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Raycast_NarrowGapBlocksAFatBody,
    "CkTests.UnitTests.CkGroundNav.Query.Raycast_NarrowGapBlocksAFatBody",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Raycast_NarrowGapBlocksAFatBody::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_raycast;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // A lane 20 uu north of the pillar's north face: the cells beside the pillar are standable but have
    // only a cell's worth of room, which is the whole distinction between a walkable set and a walkable
    // set FOR A BODY.
    constexpr auto kLaneY = 1420.0;

    auto StartColumn = FCk_GroundNav_IsNavigableResult{};

    const auto Start = Get_GroundPoint(Field, 200.0, kLaneY, kGroundZ, StartColumn);
    const auto End = FVector{500.0, kLaneY, Start.Z};

    if (NOT TestTrue(TEXT("the lane beside the pillar is standable ground"), StartColumn.Get_IsSuccess()))
    { return false; }

    const auto PointBody = Get_SurfaceRaycast(Field, Make_Ray(Start, End, 0.0f, 0.0f));

    if (NOT TestTrue(FString::Printf(TEXT("a body of no width crosses the lane (hit %s)"),
        *PointBody._HitLocation.ToString()),
        PointBody.Get_IsClear()))
    { return false; }

    constexpr auto kFatBodyRadius = 60.0f;

    const auto FatBody = Get_SurfaceRaycast(Field, Make_Ray(Start, End, kFatBodyRadius, 0.0f));

    TestEqual(FString::Printf(
        TEXT("and a body of %.0f uu does not, because the cells beside the pillar have less room than that (hit %s)"),
        kFatBodyRadius, *FatBody._HitLocation.ToString()),
        FatBody._Status, ECk_NavSurface_QueryStatus::Blocked);

    TestFalse(TEXT("refused on clearance rather than on a cost cap it was never given"),
        FatBody._StoppedOnCost);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Raycast_IsSymmetricWhenClearAndHitsAgreeWithinACell,
    "CkTests.UnitTests.CkGroundNav.Query.Raycast_IsSymmetricWhenClearAndHitsAgreeWithinACell",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Raycast_IsSymmetricWhenClearAndHitsAgreeWithinACell::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_raycast;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Points = Make_RandomPointsOverField(Field, kSymmetrySampleCount, kSymmetrySeed);

    // Both ends are put on the GROUND floor rather than wherever the projection landed, because a
    // segment whose ends sit on different storeys is a question about two worlds and the symmetry it
    // would fail is the fixture's, not the ray's.
    auto Anchors = TArray<FVector>{};
    Anchors.Reserve(Points.Num());

    for (const auto& Point : Points)
    {
        const auto Projected = Get_ProjectPoint(Field, Make_Projection(Point));

        if (NOT Projected.Get_IsSuccess())
        { continue; }

        if (FMath::Abs(Projected._Location.Z - kGroundZ) > static_cast<double>(kCellHeight))
        { continue; }

        Anchors.Emplace(Projected._Location);
    }

    auto Pairs = TArray<TPair<FVector, FVector>>{};
    Pairs.Reserve(kSymmetryPairCount);

    for (auto Index = 0; Index + 1 < Anchors.Num() && Pairs.Num() < kSymmetryPairCount; ++Index)
    {
        const auto Length = Get_DistanceXY(Anchors[Index], Anchors[Index + 1]);

        if (Length < kMinSegmentUu || Length > kMaxSegmentUu)
        { continue; }

        Pairs.Emplace(Anchors[Index], Anchors[Index + 1]);
    }

    if (NOT TestEqual(FString::Printf(
        TEXT("the sample yields the segments the claim is made over (%d ground anchors)"), Anchors.Num()),
        Pairs.Num(), kSymmetryPairCount))
    { return false; }

    auto VerdictMismatches = 0;
    auto OffSegmentHits = 0;
    auto ClearCount = 0;
    auto BlockedCount = 0;
    auto FirstMismatch = int32{INDEX_NONE};

    for (auto Index = 0; Index < Pairs.Num(); ++Index)
    {
        const auto& A = Pairs[Index].Key;
        const auto& B = Pairs[Index].Value;

        const auto Forward = Get_SurfaceRaycast(Field, Make_Ray(A, B, 0.0f, 0.0f));
        const auto Backward = Get_SurfaceRaycast(Field, Make_Ray(B, A, 0.0f, 0.0f));

        if (Forward.Get_IsClear() != Backward.Get_IsClear())
        {
            ++VerdictMismatches;

            if (FirstMismatch == INDEX_NONE)
            { FirstMismatch = Index; }

            continue;
        }

        if (Forward.Get_IsClear())
        {
            ++ClearCount;
            continue;
        }

        ++BlockedCount;

        // The two hits are on different faces and are not expected to coincide. What each of them owes
        // is to lie on the segment it was found on, within the cell the traversal placed it in.
        const auto ForwardOffset = Get_DistanceToSegmentXY(A, B, Forward._HitLocation);
        const auto BackwardOffset = Get_DistanceToSegmentXY(A, B, Backward._HitLocation);

        if (ForwardOffset <= kOneCellUu + kPositionTolerance &&
            BackwardOffset <= kOneCellUu + kPositionTolerance)
        { continue; }

        ++OffSegmentHits;

        if (FirstMismatch == INDEX_NONE)
        { FirstMismatch = Index; }
    }

    const auto Report = FString::Printf(
        TEXT("over %d segment pairs: %d agreed clear, %d agreed blocked, %d verdict disagreements, %d hits off the segment, first at %d"),
        Pairs.Num(), ClearCount, BlockedCount, VerdictMismatches, OffSegmentHits, FirstMismatch);

    ck::groundnav::Display(TEXT("{}"), Report);

    // A sample that was all clear or all blocked would satisfy symmetry without exercising it.
    if (NOT TestTrue(FString::Printf(TEXT("the sample contains both verdicts [%s]"), *Report),
        ClearCount > 0 && BlockedCount > 0))
    { return false; }

    TestEqual(FString::Printf(TEXT("a ray and its reverse never disagree on whether the segment is clear [%s]"), *Report),
        VerdictMismatches, 0);

    TestEqual(FString::Printf(TEXT("and every hit lies within one cell of the segment it was found on [%s]"), *Report),
        OffSegmentHits, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Raycast_DoesNotLeakBetweenLayers,
    "CkTests.UnitTests.CkGroundNav.Query.Raycast_DoesNotLeakBetweenLayers",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Raycast_DoesNotLeakBetweenLayers::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_raycast;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // The same XY run twice, once along the deck and once along the ground 260 uu beneath it. Both are
    // clear, so a ray that wandered between the two would still report clear and nothing about the
    // result would say which floor it walked — except the layer it ends on.
    constexpr auto kJustAboveTheDeck = kDeckTopZ + 2.0;
    constexpr auto kJustAboveTheGround = kGroundZ + 2.0;

    constexpr auto kWestX = 1050.0;
    constexpr auto kEastX = 1450.0;
    constexpr auto kLaneY = 450.0;

    const auto DeckStart = FVector{kWestX, kLaneY, kJustAboveTheDeck};
    const auto DeckEnd = FVector{kEastX, kLaneY, kJustAboveTheDeck};

    const auto DeckColumn = Get_IsNavigable(Field, Make_ColumnQuery(DeckStart, 0.0f));

    if (NOT TestEqual(TEXT("the deck's west end is standable"),
        DeckColumn._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    const auto AlongTheDeck = Get_SurfaceRaycast(Field, Make_Ray(DeckStart, DeckEnd, 0.0f, 0.0f));

    if (NOT TestTrue(FString::Printf(TEXT("a ray along the deck is clear (hit %s)"),
        *AlongTheDeck._HitLocation.ToString()),
        AlongTheDeck.Get_IsClear()))
    { return false; }

    TestEqual(TEXT("and ends on the layer it started on"),
        AlongTheDeck._LastSurface._LayerIndex, DeckColumn._Surface._LayerIndex);

    const auto GroundStart = FVector{kWestX, kLaneY, kJustAboveTheGround};
    const auto GroundEnd = FVector{kEastX, kLaneY, kJustAboveTheGround};

    const auto GroundColumn = Get_IsNavigable(Field, Make_ColumnQuery(GroundStart, 0.0f));

    if (NOT TestEqual(TEXT("so is the ground underneath it"),
        GroundColumn._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    const auto UnderTheDeck = Get_SurfaceRaycast(Field, Make_Ray(GroundStart, GroundEnd, 0.0f, 0.0f));

    if (NOT TestTrue(FString::Printf(TEXT("a ray along that ground is clear too (hit %s)"),
        *UnderTheDeck._HitLocation.ToString()),
        UnderTheDeck.Get_IsClear()))
    { return false; }

    TestEqual(TEXT("and it too ends on the layer it started on"),
        UnderTheDeck._LastSurface._LayerIndex, GroundColumn._Surface._LayerIndex);

    // The assertion the other two exist to make meaningful: identical XY, identical verdict, different
    // floor. Equal layers here would mean one of the two rays walked the wrong storey.
    TestTrue(FString::Printf(
        TEXT("and the two rays walked different floors of the same column (deck layer %d, ground layer %d)"),
        AlongTheDeck._LastSurface._LayerIndex, UnderTheDeck._LastSurface._LayerIndex),
        AlongTheDeck._LastSurface._LayerIndex != UnderTheDeck._LastSurface._LayerIndex);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Raycast_CostCapStopsTheRay,
    "CkTests.UnitTests.CkGroundNav.Query.Raycast_CostCapStopsTheRay",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Raycast_CostCapStopsTheRay::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_raycast;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(Field)))
    { return false; }

    auto StartColumn = FCk_GroundNav_IsNavigableResult{};
    auto EndColumn = FCk_GroundNav_IsNavigableResult{};

    // Nothing in the flat scene can stop this ray, and its end is standable ground well inside the
    // tile — so the cap is the only thing left that can end it, and where it ends is arithmetic.
    const auto Start = Get_GroundPoint(Field, 200.0, 200.0, kGroundZ, StartColumn);
    const auto End = Get_GroundPoint(Field, 700.0, 200.0, kGroundZ, EndColumn);

    if (NOT TestTrue(TEXT("both ends stand on the flat floor"),
        StartColumn.Get_IsSuccess() && EndColumn.Get_IsSuccess()))
    { return false; }

    constexpr auto kMaxCost = 300.0f;
    constexpr auto kExpectedStopX = 500.0;

    const auto Capped = Get_SurfaceRaycast(Field, Make_Ray(Start, End, 0.0f, kMaxCost));

    if (NOT TestEqual(FString::Printf(TEXT("a ray that runs out of budget is blocked (cost %.4f)"),
        Capped._AccumulatedCost),
        Capped._Status, ECk_NavSurface_QueryStatus::Blocked))
    { return false; }

    TestTrue(FString::Printf(TEXT("and says the budget is what stopped it (cost %.4f)"), Capped._AccumulatedCost),
        Capped._StoppedOnCost);

    // Every cell costs its own length here, so 300 units of budget buys 300 uu of travel and the stop
    // belongs at x = 500 to within the cell the ray was inside when the budget ran out.
    TestTrue(FString::Printf(TEXT("stopping where the budget ran out, within one cell of x = 500 (%.4f)"),
        Capped._HitLocation.X),
        FMath::Abs(Capped._HitLocation.X - kExpectedStopX) <= kOneCellUu + kPositionTolerance);

    TestTrue(FString::Printf(TEXT("with no hit normal, because no edge refused it (%s)"),
        *Capped._HitNormal.ToString()),
        Capped._HitNormal.IsNearlyZero());

    // The control: the identical segment with no cap is clear, so the cap is what changed the answer.
    const auto Uncapped = Get_SurfaceRaycast(Field, Make_Ray(Start, End, 0.0f, 0.0f));

    TestTrue(FString::Printf(TEXT("while the same segment with no cap is clear (cost %.4f)"),
        Uncapped._AccumulatedCost),
        Uncapped.Get_IsClear());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
