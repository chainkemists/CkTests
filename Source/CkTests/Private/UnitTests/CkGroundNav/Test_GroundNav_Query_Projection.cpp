// Projecting a point onto ground, and the ranking that decides which ground.
//
// The ordering is the contract: vertical band first, then horizontal distance. Anything that ranked on
// straight-line distance would snap an agent standing near a stairwell down to the floor below it, and
// nothing about the result would say so. So the tests here put two floors in one column at known
// heights and assert which one comes back, put two floors either side of a wall at known unequal
// distances and assert the nearer one, and pin the three refusals apart from one another: an unbuilt
// tile answers Unbuilt and never NoSurface, a body wider than the field's ceiling answers Blocked, and
// a box that reaches only built ground with nothing in it answers NoSurface.

#include "CkGroundNav/Query/CkGroundNav_QueryCore.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Attributes.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_projection
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_ProjectionQuery;
    using ck::groundnav::FCk_GroundNav_ProjectionResult;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_ProjectPoint;
    using ck::groundnav::Get_ProjectPoints_Batch;
    using ck::groundnav::Get_SurfaceAttributesAt;
    using ck::groundnav::Get_SurfaceCentre;

    // Tight enough that a wrong cell cannot pass, loose enough that the float the field stores and the
    // double the test computes agree.
    constexpr auto kPositionTolerance = 1.0e-3f;
    constexpr auto kNormalTolerance = 1.0e-3;

    auto Make_Query(
        const FVector& InLocation,
        double         InHorizontalExtent,
        double         InUpExtent,
        double         InDownExtent,
        ECk_NavSurface_ProjectionMode InMode) -> FCk_GroundNav_ProjectionQuery
    {
        auto Query = FCk_GroundNav_ProjectionQuery{};

        Query._Location = InLocation;
        Query._HorizontalExtentUu = static_cast<float>(InHorizontalExtent);
        Query._UpExtentUu = static_cast<float>(InUpExtent);
        Query._DownExtentUu = static_cast<float>(InDownExtent);
        Query._Mode = InMode;

        return Query;
    }

    /** The vertical reach a two-layer test needs: both floors of the column are inside the box. */
    constexpr auto kWholeSlabExtent = 300.0;

    // Mixed on purpose. A batch that agreed with the single form only for one mode, one extent or one
    // radius would pass a test that varied none of them.
    auto Make_MixedQuery(const FVector& InLocation, int32 InIndex) -> FCk_GroundNav_ProjectionQuery
    {
        constexpr ECk_NavSurface_ProjectionMode Modes[] = {
            ECk_NavSurface_ProjectionMode::Closest,
            ECk_NavSurface_ProjectionMode::Down,
            ECk_NavSurface_ProjectionMode::Up};

        constexpr float Radii[] = {0.0f, 20.0f, 60.0f, 120.0f};

        auto Query = Make_Query(
            InLocation,
            25.0 * static_cast<double>(InIndex % 5),
            50.0 + (25.0 * static_cast<double>(InIndex % 4)),
            50.0 + (25.0 * static_cast<double>((InIndex + 2) % 4)),
            Modes[InIndex % 3]);

        Query._Agent._RadiusUu = Radii[InIndex % 4];

        return Query;
    }

    auto Get_ResultsMatch(
        const FCk_GroundNav_ProjectionResult& InLeft,
        const FCk_GroundNav_ProjectionResult& InRight) -> bool
    {
        return InLeft._Status == InRight._Status &&
               InLeft._Location == InRight._Location &&
               InLeft._Surface == InRight._Surface &&
               InLeft._ClearanceUu == InRight._ClearanceUu &&
               InLeft._Cost._CellsRead == InRight._Cost._CellsRead;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_PointAboveFloorLandsOnItWithUpNormal,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_PointAboveFloorLandsOnItWithUpNormal",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_PointAboveFloorLandsOnItWithUpNormal::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake_FlatScene(Field)))
    { return false; }

    const auto Location = FVector{kFlatProbeX, kFlatProbeY, 200.0};
    const auto Result = Get_ProjectPoint(Field, Make_Query(
        Location, 50.0, 250.0, 250.0, ECk_NavSurface_ProjectionMode::Closest));

    if (NOT TestEqual(TEXT("a point above flat floor finds it"),
        Result._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("landing on the floor's own height, within one cell height of it (%.3f)"), Result._Location.Z),
        FMath::Abs(Result._Location.Z - kGroundZ) <= static_cast<double>(kCellHeight));

    TestTrue(FString::Printf(
        TEXT("with a normal pointing straight up (%s)"), *Result._SurfaceNormal.ToString()),
        Result._SurfaceNormal.Equals(FVector::UpVector, kNormalTolerance));

    // The query XY is inside the answering cell, so the clamp into that cell has to leave it alone.
    TestTrue(FString::Printf(
        TEXT("and its XY unmoved, because the query already stood inside the answering cell (%s)"),
        *Result._Location.ToString()),
        FMath::Abs(Result._Location.X - Location.X) <= static_cast<double>(kPositionTolerance) &&
        FMath::Abs(Result._Location.Y - Location.Y) <= static_cast<double>(kPositionTolerance));

    TestTrue(TEXT("the answer names a real surface"), Result._Surface.Get_IsValid());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_InsideWallPicksHorizontallyNearerFloor,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_InsideWallPicksHorizontallyNearerFloor",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_InsideWallPicksHorizontallyNearerFloor::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // Both queries stand inside the wall's footprint at floor height, where there is nothing to stand
    // on. The vertical reach is deliberately short so the wall's own top, 290 uu overhead, is out of
    // the box and the only candidates are the floors either side.
    constexpr auto kInsideWallY = 810.0;
    constexpr auto kShortVerticalReach = 50.0;
    constexpr auto kWideEnoughToReachBothSides = 150.0;

    const auto NearerWest = FVector{735.0, kInsideWallY, 10.0};
    const auto NearerEast = FVector{765.0, kInsideWallY, 10.0};

    const auto West = Get_ProjectPoint(Field, Make_Query(
        NearerWest, kWideEnoughToReachBothSides, kShortVerticalReach, kShortVerticalReach,
        ECk_NavSurface_ProjectionMode::Closest));

    if (NOT TestEqual(TEXT("a point inside the wall still finds floor beside it"),
        West._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("choosing the west floor, 35 uu away, over the east floor 65 uu away (cell centre %.2f)"),
        Get_SurfaceCentre(Field, West._Surface).X),
        Get_SurfaceCentre(Field, West._Surface).X < kWallMinX);

    TestTrue(FString::Printf(
        TEXT("and reporting a position no further east than the wall's west face (%.3f)"), West._Location.X),
        West._Location.X <= kWallMinX + static_cast<double>(kPositionTolerance));

    const auto East = Get_ProjectPoint(Field, Make_Query(
        NearerEast, kWideEnoughToReachBothSides, kShortVerticalReach, kShortVerticalReach,
        ECk_NavSurface_ProjectionMode::Closest));

    if (NOT TestEqual(TEXT("and the mirrored point does too"),
        East._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("choosing the east floor this time (cell centre %.2f)"),
        Get_SurfaceCentre(Field, East._Surface).X),
        Get_SurfaceCentre(Field, East._Surface).X > kWallMaxX);

    TestTrue(FString::Printf(
        TEXT("and reporting a position no further west than the wall's east face (%.3f)"), East._Location.X),
        East._Location.X >= kWallMaxX - static_cast<double>(kPositionTolerance));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_OverHoleRespectsExtent,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_OverHoleRespectsExtent",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_OverHoleRespectsExtent::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // The middle of the hole is 100 uu from the nearest rim in every direction, so the extent alone
    // decides whether there is an answer at all.
    const auto OverTheHole = FVector{0.5 * (kHoleMin + kHoleMax), 0.5 * (kHoleMin + kHoleMax), 50.0};

    const auto TooShort = Get_ProjectPoint(Field, Make_Query(
        OverTheHole, 50.0, 100.0, 100.0, ECk_NavSurface_ProjectionMode::Closest));

    TestEqual(TEXT("a box that cannot reach the rim finds no surface"),
        TooShort._Status, ECk_NavSurface_QueryStatus::NoSurface);

    // The distinction the whole status set exists for: every tile this box touched IS built, so the
    // absence of ground is knowledge, not a hole in the data.
    TestTrue(TEXT("and says so as NoSurface rather than Unbuilt, because every tile it read is built"),
        TooShort._Status != ECk_NavSurface_QueryStatus::Unbuilt);

    const auto LongEnough = Get_ProjectPoint(Field, Make_Query(
        OverTheHole, 150.0, 100.0, 100.0, ECk_NavSurface_ProjectionMode::Closest));

    if (NOT TestEqual(TEXT("a box that reaches the rim finds it"),
        LongEnough._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    const auto OnRim =
        FMath::Abs(LongEnough._Location.X - kHoleMin) <= static_cast<double>(kCellSize) ||
        FMath::Abs(LongEnough._Location.X - kHoleMax) <= static_cast<double>(kCellSize) ||
        FMath::Abs(LongEnough._Location.Y - kHoleMin) <= static_cast<double>(kCellSize) ||
        FMath::Abs(LongEnough._Location.Y - kHoleMax) <= static_cast<double>(kCellSize);

    TestTrue(FString::Printf(
        TEXT("answering on the hole's rim, within one cell of its edge (%s)"), *LongEnough._Location.ToString()),
        OnRim);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_OverUnbuiltTileAnswersUnbuiltNeverNoSurface,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_OverUnbuiltTileAnswersUnbuiltNeverNoSurface",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_OverUnbuiltTileAnswersUnbuiltNeverNoSurface::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto OverTheTakenTile = FVector{kFarTileProbeX, kFarTileProbeY, 50.0};

    const auto TakenTile = Do_MakeTileUnbuiltAt(Field, OverTheTakenTile);

    if (NOT TestTrue(TEXT("the probe stands over a tile the field actually has"), TakenTile != INDEX_NONE))
    { return false; }

    // The box is small enough to stay inside the tile that was taken away, so no built tile can supply
    // an answer and the only question is which refusal comes back.
    const auto Projection = Get_ProjectPoint(Field, Make_Query(
        OverTheTakenTile, 50.0, 100.0, 100.0, ECk_NavSurface_ProjectionMode::Closest));

    TestEqual(TEXT("projecting over an unbuilt tile answers Unbuilt"),
        Projection._Status, ECk_NavSurface_QueryStatus::Unbuilt);

    auto ColumnQuery = FCk_GroundNav_IsNavigableQuery{};
    ColumnQuery._Location = OverTheTakenTile;
    ColumnQuery._VerticalToleranceUu = 100.0f;

    const auto Navigable = Get_IsNavigable(Field, ColumnQuery);

    TestEqual(TEXT("asking whether the same point is navigable answers Unbuilt too"),
        Navigable._Status, ECk_NavSurface_QueryStatus::Unbuilt);

    const auto Attributes = Get_SurfaceAttributesAt(Field, ColumnQuery);

    TestEqual(TEXT("and so does asking what the ground there is like"),
        Attributes._Status, ECk_NavSurface_QueryStatus::Unbuilt);

    // Stated as its own assertion because this is the failure that matters: a consumer told NoSurface
    // gives up on ground that may simply not have been baked yet.
    TestTrue(TEXT("none of the three entry points calls unbuilt ground NoSurface"),
        Projection._Status != ECk_NavSurface_QueryStatus::NoSurface &&
        Navigable._Status != ECk_NavSurface_QueryStatus::NoSurface &&
        Attributes._Status != ECk_NavSurface_QueryStatus::NoSurface);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_BatchIsElementWiseIdenticalToSingles,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_BatchIsElementWiseIdenticalToSingles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_BatchIsElementWiseIdenticalToSingles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    constexpr auto kQueryCount = 500;
    constexpr auto kSeed = 20260902;

    const auto Points = Make_RandomPointsOverField(Field, kQueryCount, kSeed);

    auto Queries = TArray<FCk_GroundNav_ProjectionQuery>{};
    Queries.Reserve(kQueryCount);

    for (auto Index = 0; Index < Points.Num(); ++Index)
    { Queries.Emplace(Make_MixedQuery(Points[Index], Index)); }

    auto BatchResults = TArray<FCk_GroundNav_ProjectionResult>{};
    BatchResults.SetNum(Queries.Num());

    Get_ProjectPoints_Batch(Field, Queries, BatchResults);

    auto MismatchCount = 0;
    auto FirstMismatch = int32{INDEX_NONE};

    for (auto Index = 0; Index < Queries.Num(); ++Index)
    {
        if (Get_ResultsMatch(Get_ProjectPoint(Field, Queries[Index]), BatchResults[Index]))
        { continue; }

        ++MismatchCount;

        if (FirstMismatch == INDEX_NONE)
        { FirstMismatch = Index; }
    }

    TestEqual(FString::Printf(
        TEXT("every one of %d batched projections answers exactly as the single call does (first disagreement at %d)"),
        Queries.Num(), FirstMismatch),
        MismatchCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_VerticalBandBeatsHorizontalDistance,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_VerticalBandBeatsHorizontalDistance",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_VerticalBandBeatsHorizontalDistance::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // One column, two floors: the deck at 260 and the ground at 0. Both are directly under or over the
    // query, so horizontal distance is zero for both and the vertical band is the only thing deciding.
    constexpr auto kJustAboveTheDeck = kDeckTopZ + 2.0;
    constexpr auto kBetweenTheFloors = 100.0;

    const auto Above = Get_ProjectPoint(Field, Make_Query(
        FVector{kDeckColumnX, kDeckColumnY, kJustAboveTheDeck},
        60.0, kWholeSlabExtent, kWholeSlabExtent, ECk_NavSurface_ProjectionMode::Closest));

    if (NOT TestEqual(TEXT("a point just above the deck finds ground"),
        Above._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("and it is the deck 2 uu below, not the floor 262 uu below (%.2f)"), Above._Location.Z),
        FMath::Abs(Above._Location.Z - kDeckTopZ) <= static_cast<double>(kCellHeight));

    // Halfway up the column the ground is 100 uu down and the deck 160 uu up: two and a half step
    // heights against four, so the ground's band is lower and wins even though neither is close.
    const auto Between = Get_ProjectPoint(Field, Make_Query(
        FVector{kDeckColumnX, kDeckColumnY, kBetweenTheFloors},
        60.0, kWholeSlabExtent, kWholeSlabExtent, ECk_NavSurface_ProjectionMode::Closest));

    if (NOT TestEqual(TEXT("a point between the two floors finds ground"),
        Between._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("and it is the floor below, whose vertical band is two steps against the deck's four (%.2f)"),
        Between._Location.Z),
        FMath::Abs(Between._Location.Z - kGroundZ) <= static_cast<double>(kCellHeight));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_DownAndUpModesRefuseTheOtherSide,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_DownAndUpModesRefuseTheOtherSide",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_DownAndUpModesRefuseTheOtherSide::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto BetweenTheFloors = FVector{kDeckColumnX, kDeckColumnY, 100.0};

    const auto Down = Get_ProjectPoint(Field, Make_Query(
        BetweenTheFloors, 60.0, kWholeSlabExtent, kWholeSlabExtent, ECk_NavSurface_ProjectionMode::Down));

    if (NOT TestEqual(TEXT("looking down from between the floors finds ground"),
        Down._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(TEXT("and it is the floor below (%.2f)"), Down._Location.Z),
        FMath::Abs(Down._Location.Z - kGroundZ) <= static_cast<double>(kCellHeight));

    const auto Up = Get_ProjectPoint(Field, Make_Query(
        BetweenTheFloors, 60.0, kWholeSlabExtent, kWholeSlabExtent, ECk_NavSurface_ProjectionMode::Up));

    if (NOT TestEqual(TEXT("looking up from the same point finds ground too"),
        Up._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    // The point of the modes: each refuses the surface the other returns, from the identical box.
    TestTrue(FString::Printf(TEXT("but it is the deck above, not the floor below (%.2f)"), Up._Location.Z),
        FMath::Abs(Up._Location.Z - kDeckTopZ) <= static_cast<double>(kCellHeight));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_RadiusAboveClearanceCapIsBlocked,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_RadiusAboveClearanceCapIsBlocked",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_RadiusAboveClearanceCapIsBlocked::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // Above the ceiling the field baked under, every open cell reads exactly the ceiling, so a wider
    // body cannot be admitted on clearance alone and must be refused rather than mis-admitted.
    constexpr auto kOverTheCap = 250.0f;
    constexpr auto kAtTheCap = 200.0f;

    const auto Standing = FVector{400.0, 400.0, 10.0};

    auto TooWide = Make_Query(Standing, 100.0, 100.0, 100.0, ECk_NavSurface_ProjectionMode::Closest);
    TooWide._Agent._RadiusUu = kOverTheCap;

    TestEqual(TEXT("a body wider than the field's clearance ceiling is refused as Blocked"),
        Get_ProjectPoint(Field, TooWide)._Status, ECk_NavSurface_QueryStatus::Blocked);

    auto ColumnQuery = FCk_GroundNav_IsNavigableQuery{};
    ColumnQuery._Location = Standing;
    ColumnQuery._VerticalToleranceUu = 100.0f;
    ColumnQuery._Agent._RadiusUu = kOverTheCap;

    TestEqual(TEXT("and the is-navigable lookup refuses it the same way"),
        Get_IsNavigable(Field, ColumnQuery)._Status, ECk_NavSurface_QueryStatus::Blocked);

    TestEqual(TEXT("and so does reading the ground's attributes there"),
        Get_SurfaceAttributesAt(Field, ColumnQuery)._Status, ECk_NavSurface_QueryStatus::Blocked);

    auto AtTheCap = TooWide;
    AtTheCap._Agent._RadiusUu = kAtTheCap;

    TestTrue(TEXT("a body exactly at the ceiling is answerable, whatever the answer turns out to be"),
        Get_ProjectPoint(Field, AtTheCap)._Status != ECk_NavSurface_QueryStatus::Blocked);

    ColumnQuery._Agent._RadiusUu = kAtTheCap;

    TestTrue(TEXT("and the column lookup agrees it is answerable"),
        Get_IsNavigable(Field, ColumnQuery)._Status != ECk_NavSurface_QueryStatus::Blocked);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Query_Projection_ClearanceAdmissionRejectsNarrowCells,
    "CkTests.UnitTests.CkGroundNav.Query.Projection_ClearanceAdmissionRejectsNarrowCells",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Query_Projection_ClearanceAdmissionRejectsNarrowCells::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_queryfixtures;
    using namespace ck_test_groundnav_query_projection;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    // One cell east of the hole's rim: standable, but with only a cell's worth of room to the edge.
    const auto BesideTheHole = FVector{kNarrowProbeX, kNarrowProbeY, kGroundZ};
    const auto HoleRect = Get_HoleRectXY();

    constexpr auto kWideSearch = 300.0;
    constexpr auto kNarrowThreshold = 50.0f;
    constexpr auto kWideBodyRadius = 60.0f;

    const auto PointBody = Get_ProjectPoint(Field, Make_Query(
        BesideTheHole, kWideSearch, 100.0, 100.0, ECk_NavSurface_ProjectionMode::Closest));

    if (NOT TestEqual(TEXT("a body of no width stands where it is asked"),
        PointBody._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("on a cell with less than %.0f uu of room, because the hole starts one cell away (%.2f)"),
        kNarrowThreshold, PointBody._ClearanceUu),
        PointBody._ClearanceUu < kNarrowThreshold);

    auto WideBody = Make_Query(
        BesideTheHole, kWideSearch, 100.0, 100.0, ECk_NavSurface_ProjectionMode::Closest);
    WideBody._Agent._RadiusUu = kWideBodyRadius;

    const auto Wide = Get_ProjectPoint(Field, WideBody);

    if (NOT TestEqual(TEXT("a body that needs room finds some further out"),
        Wide._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("on a cell that actually has the %.0f uu it asked for (%.2f)"),
        kWideBodyRadius, Wide._ClearanceUu),
        Wide._ClearanceUu >= kWideBodyRadius);

    const auto PointDistance = Get_DistanceToRectXY(HoleRect, PointBody._Location);
    const auto WideDistance = Get_DistanceToRectXY(HoleRect, Wide._Location);

    // The admission has to MOVE the answer, not merely relabel it: a wide body standing where a point
    // body stood is a wide body clipping the edge.
    TestTrue(FString::Printf(
        TEXT("standing further from the hole than the point body did (%.2f against %.2f)"),
        WideDistance, PointDistance),
        WideDistance > PointDistance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
