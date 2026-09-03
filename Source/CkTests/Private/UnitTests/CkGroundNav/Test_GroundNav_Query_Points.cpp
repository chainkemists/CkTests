// Where a generator is allowed to put a point, and how evenly it is allowed to spread them.
//
// Three generators with three separate obligations, and only one of them can be shown by example. The
// radius generator's contract is uniformity BY AREA, which no picture demonstrates and no eyeball
// checks: it is stated here as a chi-square over the plates the disc touches, against weights this file
// counts for itself out of the field's own cells, so a generator that weighted by plate count or by
// rectangle size instead of by admitted area disagrees with an independent number rather than merely
// looking plausible. The path-distance generator's obligation is that a point across a wall is far even
// when it is near, checked against a fresh flood and against the visibility-graph reference the
// reachability suite is stated on. The grid's is that two overlapping queries agree, which is the
// entire reason its lattice is phased to the field and not to the caller's box.

#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Query/CkGroundNav_QueryCore.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Points.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Projection.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"
#include "Test_GroundNav_ReferencePaths.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_query_points
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FloodQuery;
    using ck::groundnav::FCk_GroundNav_GeneratedPoint;
    using ck::groundnav::FCk_GroundNav_GridPointsQuery;
    using ck::groundnav::FCk_GroundNav_IsNavigableQuery;
    using ck::groundnav::FCk_GroundNav_PathDistancePointsQuery;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_QueryAgent;
    using ck::groundnav::FCk_GroundNav_RandomPointsQuery;
    using ck::groundnav::FCk_GroundNav_SurfaceRef;
    using ck::groundnav::Get_FlatPlateCount;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_FloodDistanceTo;
    using ck::groundnav::Get_FloodFill;
    using ck::groundnav::Get_GridPoints;
    using ck::groundnav::Get_IsAdmitted;
    using ck::groundnav::Get_IsNavigable;
    using ck::groundnav::Get_RandomPointsByPathDistance;
    using ck::groundnav::Get_RandomPointsInRadius;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Bake_QueryScene;
    using ck_test_groundnav_queryfixtures::kCellHeight;
    using ck_test_groundnav_queryfixtures::kCellSize;
    using ck_test_groundnav_queryfixtures::kDeckColumnX;
    using ck_test_groundnav_queryfixtures::kDeckColumnY;
    using ck_test_groundnav_queryfixtures::kDeckTopZ;
    using ck_test_groundnav_queryfixtures::kGroundZ;
    using ck_test_groundnav_queryfixtures::kStepHeight;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;

    using ck_test_groundnav_referencepaths::Get_ReferenceDistance;
    using ck_test_groundnav_referencepaths::Get_XY;
    using ck_test_groundnav_referencepaths::kEpsilon;
    using ck_test_groundnav_referencepaths::kGroundStoreyMaxZ;
    using ck_test_groundnav_referencepaths::Make_VisibilityGraph;

    // The disc the radius generator is asked about. Its centre is a whole number of cells from the field
    // origin, which is what keeps NO cell centre on its rim: a centre sits an odd multiple of half a cell
    // from it in each axis, so landing on the rim would need (2a+1)^2 + (2b+1)^2 = 2304, and a sum of two
    // odd squares is 2 modulo 8 and therefore never divisible by 8. The weights this file counts and the
    // ones the generator counts then agree without either side stating a tie-break.
    constexpr auto kDiscOriginX = 400.0;
    constexpr auto kDiscOriginY = 500.0;
    constexpr auto kDiscRadiusUu = 600.0f;

    // Under one cell, so the admission rule is exercised — the cells beside a wall carry exactly one cell
    // size of room — without the disc emptying out.
    constexpr auto kDiscAgentRadiusUu = 20.0f;

    constexpr auto kNavigableCount = 100000;
    constexpr auto kNavigableSeed = 20260904;

    constexpr auto kUniformCount = 40000;
    constexpr auto kUniformSeed = 20260905;

    constexpr auto kDeterminismCount = 2000;
    constexpr auto kDeterminismSeed = 20260906;

    // The point is uniform inside the square of the cell that was admitted, so it may sit up to half a
    // diagonal outside the disc its CENTRE was tested against. One cell size covers that with room over.
    constexpr auto kDiscOvershootUu = static_cast<double>(kCellSize);

    // The point's height is its cell's surface height exactly, so the only slack a navigable lookup needs
    // is enough to survive the float-to-double widening of a stored height.
    constexpr auto kNavigableToleranceUu = 1.0f;

    // The west room, clear of the dividing wall and of the field rim in every direction.
    const auto kPathOrigin = FVector{300.0, 400.0, kGroundZ};

    constexpr auto kPathMinUu = 100.0f;
    constexpr auto kPathMaxUu = 600.0f;
    constexpr auto kPathCount = 300;
    constexpr auto kPathSeed = 20260907;

    // The visibility graph is quadratic in its nodes and is solved once per target, so the reference is
    // asked about a sample of the draw rather than all of it.
    constexpr auto kPathReferenceTargetCount = 40;

    // A minimum far enough out that what it excludes is a large part of what the flood reached, so a
    // generator ignoring it would be caught within the first few draws.
    constexpr auto kFarMinUu = 200.0f;

    // Two floors in one field with a 400 uu gap that no crossing spans, so the far one is not merely far:
    // it is unreachable, and a generator drawing by radius rather than by walked distance puts points on
    // it.
    constexpr auto kIslandGapMinX = 600.0;
    constexpr auto kIslandGapMaxX = 1000.0;

    const auto kIslandOrigin = FVector{200.0, 400.0, kGroundZ};

    constexpr auto kIslandMaxUu = 2000.0f;
    constexpr auto kIslandCount = 200;
    constexpr auto kIslandSeed = 20260908;

    // Not a whole number of cells, so most lattice positions land inside a cell instead of on the corner
    // four cells share.
    constexpr auto kGridSpacingUu = 90.0f;
    constexpr auto kGridAgentRadiusUu = 20.0f;

    // The two overlapping boxes. Their minimum corners differ by 300, which is not a multiple of the
    // spacing, so the unaligned lattices cannot coincide by accident; and no edge of the region the two
    // are compared over is a multiple of the spacing either, so no lattice position sits on that boundary
    // and no inclusive-or-exclusive rule about it can decide the answer.
    constexpr auto kOverlapMinX = 512.0;
    constexpr auto kOverlapMaxX = 912.0;
    constexpr auto kOverlapMinY = 312.0;
    constexpr auto kOverlapMaxY = 912.0;

    constexpr auto kBoxAMinX = 212.0;
    constexpr auto kBoxBMaxX = 1212.0;

    // The ground storey alone: the deck at 260 and the wall top at 300 are both above this.
    constexpr auto kGridGroundMinZ = -50.0;
    constexpr auto kGridGroundMaxZ = 100.0;

    // The whole field, up to just over the wall top, so the lattice is asked about every storey there is.
    constexpr auto kGridWholeMinXY = 112.0;
    constexpr auto kGridWholeMaxXY = 1512.0;
    constexpr auto kGridWholeMaxZ = 320.0;

    // A window on the deck column, well inside the deck's own footprint so every lattice position in it
    // has both the deck and the ground beneath it. Its ceiling clears the deck rather than sitting on it,
    // so nothing here rests on whether the box test that admits a storey is inclusive at its edge.
    constexpr auto kDeckWindowHalfUu = 100.0;
    constexpr auto kDeckWindowMaxZ = kDeckTopZ + 20.0;

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Agent(
        float InRadiusUu) -> FCk_GroundNav_QueryAgent
    {
        auto Agent = FCk_GroundNav_QueryAgent{};

        Agent._RadiusUu = InRadiusUu;

        return Agent;
    }

    auto Make_RandomQuery(
        int32 InCount,
        int32 InSeed) -> FCk_GroundNav_RandomPointsQuery
    {
        auto Query = FCk_GroundNav_RandomPointsQuery{};

        Query._Origin = FVector{kDiscOriginX, kDiscOriginY, kGroundZ};
        Query._RadiusUu = kDiscRadiusUu;
        Query._Agent = Make_Agent(kDiscAgentRadiusUu);
        Query._Count = InCount;
        Query._Seed = InSeed;

        return Query;
    }

    auto Make_PathDistanceQuery(
        const FVector& InOrigin,
        float          InMinDistanceUu,
        float          InMaxDistanceUu,
        int32          InCount,
        int32          InSeed) -> FCk_GroundNav_PathDistancePointsQuery
    {
        auto Query = FCk_GroundNav_PathDistancePointsQuery{};

        Query._Origin = InOrigin;
        Query._MinDistanceUu = InMinDistanceUu;
        Query._MaxDistanceUu = InMaxDistanceUu;
        Query._VerticalToleranceUu = kStepHeight;
        Query._Count = InCount;
        Query._Seed = InSeed;

        return Query;
    }

    /** The flood the path-distance generator runs, re-run by the test so the check shares no state. */
    auto Make_FloodQuery(
        const FVector& InSource,
        float          InMaxDistanceUu) -> FCk_GroundNav_FloodQuery
    {
        auto Query = FCk_GroundNav_FloodQuery{};

        Query._Source = InSource;
        Query._VerticalToleranceUu = kStepHeight;
        Query._MaxDistanceUu = InMaxDistanceUu;

        return Query;
    }

    auto Make_GridQuery(
        const FBox&       InBounds,
        ECk_EnableDisable InAlignToLattice) -> FCk_GroundNav_GridPointsQuery
    {
        auto Query = FCk_GroundNav_GridPointsQuery{};

        Query._Bounds = InBounds;
        Query._SpacingUu = kGridSpacingUu;
        Query._AlignToLattice = InAlignToLattice;
        Query._Agent = Make_Agent(kGridAgentRadiusUu);

        return Query;
    }

    auto Get_IsPointNavigable(
        const FCk_GroundNav_Field& InField,
        const FVector&             InLocation,
        float                      InAgentRadiusUu) -> bool
    {
        auto Query = FCk_GroundNav_IsNavigableQuery{};

        Query._Location = InLocation;
        Query._VerticalToleranceUu = kNavigableToleranceUu;
        Query._Agent = Make_Agent(InAgentRadiusUu);

        return Get_IsNavigable(InField, Query).Get_IsSuccess();
    }

    auto Get_LabelAtSurface(
        const FCk_GroundNav_Field&      InField,
        const FCk_GroundNav_SurfaceRef& InSurface) -> int32
    {
        return InField.Get_ReachabilityLabel(InSurface._TileIndex, InSurface._PlateIndex);
    }

    // ----------------------------------------------------------------------------------------------------------------

    /**
     * The area weight of every plate the disc touches, counted out of the field's own cells.
     *
     * Deliberately written without asking the generator anything: one cell of one layer belongs to exactly
     * one plate, it counts when its centre is inside the disc and its room admits the body, and that is
     * the whole definition the uniformity claim rests on. Indexed by FLAT plate, which is the index space
     * a returned point's surface reference converts into.
     */
    auto Do_CountAdmittedCellsInDisc(
        const FCk_GroundNav_Field&      InField,
        const FVector2D&                InOriginXY,
        float                           InRadiusUu,
        const FCk_GroundNav_QueryAgent& InAgent,
        TArray<int32>&                  OutWeights) -> void
    {
        OutWeights.Init(0, Get_FlatPlateCount(InField));

        const auto RadiusSquared = static_cast<double>(InRadiusUu) * static_cast<double>(InRadiusUu);

        for (auto TileIndex = 0; TileIndex < InField._Tiles.Num(); ++TileIndex)
        {
            const auto& Tile = InField._Tiles[TileIndex];

            if (NOT Tile.Get_IsBuilt())
            { continue; }

            const auto CellSizeUu = static_cast<double>(Tile._CellSizeUu);

            for (auto Layer = 0; Layer < Tile._LayerCount; ++Layer)
            {
                for (auto CellY = 0; CellY < Tile._SizeY; ++CellY)
                {
                    for (auto CellX = 0; CellX < Tile._SizeX; ++CellX)
                    {
                        const auto PlateIndex = Tile._Plates.Get_PlateIndexAt(CellX, CellY, Layer);

                        if (PlateIndex == FCk_GroundNav_Plate::kNoPlate)
                        { continue; }

                        if (NOT Get_IsAdmitted(Tile._Clearance.Get_ClearanceAt(CellX, CellY, Layer), InAgent))
                        { continue; }

                        const auto CentreXY = FVector2D{
                            Tile._Origin.X + ((static_cast<double>(CellX) + 0.5) * CellSizeUu),
                            Tile._Origin.Y + ((static_cast<double>(CellY) + 0.5) * CellSizeUu)};

                        if (FVector2D::DistSquared(CentreXY, InOriginXY) > RadiusSquared)
                        { continue; }

                        const auto FlatPlate = Get_FlatPlateIndex(InField, TileIndex, PlateIndex);

                        if (OutWeights.IsValidIndex(FlatPlate))
                        { ++OutWeights[FlatPlate]; }
                    }
                }
            }
        }
    }

    /**
     * The 0.99 quantile of chi-square with the given degrees of freedom, by Wilson-Hilferty.
     *
     * Computed rather than tabulated because the number of plates a disc touches is a property of the
     * bake, and a table would have to be re-cut whenever the fixture moved. The approximation sits well
     * inside a percent above a couple of degrees of freedom, which is far tighter than the gap between a
     * uniform draw and a biased one.
     */
    auto Get_ChiSquareUpperCritical(
        int32 InDegreesOfFreedom) -> double
    {
        constexpr auto kNormalQuantile99 = 2.3263478740408408;

        const auto Df = static_cast<double>(InDegreesOfFreedom);
        const auto Ninth = 2.0 / (9.0 * Df);
        const auto Term = 1.0 - Ninth + (kNormalQuantile99 * FMath::Sqrt(Ninth));

        return Df * Term * Term * Term;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_TwoIslandScene() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-400.0, -400.0, -10.0}, FVector{kIslandGapMinX, 2000.0, kGroundZ}},
            FBox{FVector{kIslandGapMaxX, -400.0, -10.0}, FVector{2000.0, 2000.0, kGroundZ}}};
    }

    auto Get_PointsAreIdentical(
        const TArray<FCk_GroundNav_GeneratedPoint>& InLeft,
        const TArray<FCk_GroundNav_GeneratedPoint>& InRight) -> bool
    {
        if (InLeft.Num() != InRight.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft.Num(); ++Index)
        {
            if (InLeft[Index]._Location != InRight[Index]._Location)
            { return false; }

            if (NOT (InLeft[Index]._Surface == InRight[Index]._Surface))
            { return false; }
        }

        return true;
    }

    auto Get_ContainsXY(
        const TArray<FVector2D>& InPositions,
        const FVector2D&         InPosition) -> bool
    {
        for (const auto& Position : InPositions)
        {
            if (Position.X == InPosition.X && Position.Y == InPosition.Y)
            { return true; }
        }

        return false;
    }

    /** The distinct lattice positions a grid result placed inside a rectangle, compared exactly. */
    auto Do_CollectXYInRect(
        const TArray<FCk_GroundNav_GeneratedPoint>& InPoints,
        const FBox2D&                               InRect,
        TArray<FVector2D>&                          OutPositions) -> void
    {
        for (const auto& Point : InPoints)
        {
            const auto Position = Get_XY(Point._Location);

            if (Position.X < InRect.Min.X || Position.X > InRect.Max.X)
            { continue; }

            if (Position.Y < InRect.Min.Y || Position.Y > InRect.Max.Y)
            { continue; }

            if (NOT Get_ContainsXY(OutPositions, Position))
            { OutPositions.Emplace(Position); }
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_RandomInRadius_EveryPointIsOnWalkableGround,
    "CkTests.UnitTests.CkGroundNav.Query.RandomInRadius_EveryPointIsOnWalkableGround",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_RandomInRadius_EveryPointIsOnWalkableGround::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_points;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Result = Get_RandomPointsInRadius(Field, Make_RandomQuery(kNavigableCount, kNavigableSeed));

    if (NOT TestEqual(TEXT("the draw succeeded"), Result._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    if (NOT TestEqual(TEXT("the draw is the full count asked for"), Result._Points.Num(), kNavigableCount))
    { return false; }

    const auto OriginXY = FVector2D{kDiscOriginX, kDiscOriginY};
    const auto FarthestAllowedUu = static_cast<double>(kDiscRadiusUu) + kDiscOvershootUu;

    auto NotNavigable = 0;
    auto NoSurfaceRef = 0;
    auto OutOfRadius = 0;

    for (const auto& Point : Result._Points)
    {
        if (NOT Get_IsPointNavigable(Field, Point._Location, kDiscAgentRadiusUu))
        { ++NotNavigable; }

        if (NOT Point._Surface.Get_IsValid())
        { ++NoSurfaceRef; }

        if (FVector2D::Distance(Get_XY(Point._Location), OriginXY) > FarthestAllowedUu)
        { ++OutOfRadius; }
    }

    const auto Report = FString::Printf(
        TEXT("drew %d points in %d attempts, %d not navigable, %d without a surface, %d beyond the disc"),
        Result._Points.Num(), Result._Attempts, NotNavigable, NoSurfaceRef, OutOfRadius);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("every drawn point stands on walkable ground [%s]"), *Report),
        NotNavigable, 0);

    TestEqual(FString::Printf(TEXT("every drawn point carries the surface it stands on [%s]"), *Report),
        NoSurfaceRef, 0);

    TestEqual(FString::Printf(TEXT("no drawn point is further out than the cell it came from allows [%s]"), *Report),
        OutOfRadius, 0);

    TestTrue(FString::Printf(TEXT("the draws spent are at least the points returned [%s]"), *Report),
        Result._Attempts >= Result._Points.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_RandomInRadius_IsUniformByArea,
    "CkTests.UnitTests.CkGroundNav.Query.RandomInRadius_IsUniformByArea",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_RandomInRadius_IsUniformByArea::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_points;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    auto Weights = TArray<int32>{};

    Do_CountAdmittedCellsInDisc(
        Field, FVector2D{kDiscOriginX, kDiscOriginY}, kDiscRadiusUu,
        Make_Agent(kDiscAgentRadiusUu), Weights);

    auto TotalWeight = 0;
    auto PlateCount = 0;

    for (const auto Weight : Weights)
    {
        TotalWeight += Weight;

        if (Weight > 0)
        { ++PlateCount; }
    }

    if (NOT TestTrue(TEXT("the disc covers more than one plate, so the statistic has a shape to test"),
        PlateCount > 1))
    { return false; }

    const auto Result = Get_RandomPointsInRadius(Field, Make_RandomQuery(kUniformCount, kUniformSeed));

    if (NOT TestEqual(TEXT("the draw succeeded"), Result._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    if (NOT TestEqual(TEXT("the draw is the full count asked for"), Result._Points.Num(), kUniformCount))
    { return false; }

    auto Observed = TArray<int32>{};
    Observed.Init(0, Weights.Num());

    auto OffWeightPlate = 0;

    for (const auto& Point : Result._Points)
    {
        const auto FlatPlate = Get_FlatPlateIndex(
            Field, Point._Surface._TileIndex, Point._Surface._PlateIndex);

        if (NOT Observed.IsValidIndex(FlatPlate) || Weights[FlatPlate] <= 0)
        {
            ++OffWeightPlate;
            continue;
        }

        ++Observed[FlatPlate];
    }

    const auto Drawn = static_cast<double>(Result._Points.Num());
    const auto Total = static_cast<double>(TotalWeight);

    auto ChiSquare = 0.0;
    auto WorstDeviation = 0.0;
    auto OverBound = 0;

    for (auto FlatPlate = 0; FlatPlate < Weights.Num(); ++FlatPlate)
    {
        if (Weights[FlatPlate] <= 0)
        { continue; }

        const auto Expected = Drawn * (static_cast<double>(Weights[FlatPlate]) / Total);
        const auto Deviation = static_cast<double>(Observed[FlatPlate]) - Expected;

        ChiSquare += (Deviation * Deviation) / Expected;

        WorstDeviation = FMath::Max(WorstDeviation, FMath::Abs(Deviation));

        if (FMath::Abs(Deviation) > (4.0 * FMath::Sqrt(Expected)) + 5.0)
        { ++OverBound; }
    }

    const auto Critical = Get_ChiSquareUpperCritical(PlateCount - 1);

    const auto Report = FString::Printf(
        TEXT("%d points over %d plates weighing %d cells, chi-square %.4f against %.4f at %d degrees of freedom, worst deviation %.2f, %d plates over the per-plate bound, %d points on a plate with no weight"),
        Result._Points.Num(), PlateCount, TotalWeight, ChiSquare, Critical, PlateCount - 1,
        WorstDeviation, OverBound, OffWeightPlate);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("no point landed on a plate the disc admits nothing of [%s]"), *Report),
        OffWeightPlate, 0);

    TestTrue(FString::Printf(TEXT("the chi-square statistic is under its 0.99 quantile [%s]"), *Report),
        ChiSquare < Critical);

    TestEqual(FString::Printf(TEXT("every plate is within four standard deviations of its area share [%s]"), *Report),
        OverBound, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_RandomInRadius_IsDeterministicPerSeed,
    "CkTests.UnitTests.CkGroundNav.Query.RandomInRadius_IsDeterministicPerSeed",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_RandomInRadius_IsDeterministicPerSeed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_points;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto First = Get_RandomPointsInRadius(Field, Make_RandomQuery(kDeterminismCount, kDeterminismSeed));
    const auto Second = Get_RandomPointsInRadius(Field, Make_RandomQuery(kDeterminismCount, kDeterminismSeed));
    const auto Other = Get_RandomPointsInRadius(Field, Make_RandomQuery(kDeterminismCount, kDeterminismSeed + 1));

    if (NOT TestTrue(TEXT("the draws produced points"), First._Points.Num() > 0))
    { return false; }

    // Exact equality, element by element: the generator is arithmetic over a seeded stream against an
    // immutable field, so anything short of bit-identical is a dependency on something it must not have.
    TestTrue(TEXT("the same seed reproduces the same points exactly"),
        Get_PointsAreIdentical(First._Points, Second._Points));

    TestTrue(TEXT("a different seed produces a different draw"),
        NOT Get_PointsAreIdentical(First._Points, Other._Points));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ByPathDistance_EveryPointIsInRange,
    "CkTests.UnitTests.CkGroundNav.Query.ByPathDistance_EveryPointIsInRange",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ByPathDistance_EveryPointIsInRange::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_points;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Result = Get_RandomPointsByPathDistance(Field, Make_PathDistanceQuery(
        kPathOrigin, kPathMinUu, kPathMaxUu, kPathCount, kPathSeed));

    if (NOT TestEqual(TEXT("the draw succeeded"), Result._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    if (NOT TestTrue(TEXT("the draw produced points"), Result._Points.Num() > 0))
    { return false; }

    const auto Agent = Make_Agent(0.0f);

    const auto Flood = Get_FloodFill(Field, Make_FloodQuery(kPathOrigin, kPathMaxUu));

    if (NOT TestTrue(TEXT("the independent flood resolved its source"), Flood.Get_IsSuccess()))
    { return false; }

    const auto SourceLabel = Get_LabelAtSurface(Field, Flood._SourceSurface);

    if (NOT TestTrue(TEXT("the source plate carries a label"), SourceLabel != INDEX_NONE))
    { return false; }

    const auto Graph = Make_VisibilityGraph(Field, SourceLabel, Get_XY(Flood._SourcePoint));

    const auto MinUu = static_cast<double>(kPathMinUu);
    const auto MaxUu = static_cast<double>(kPathMaxUu);

    auto Unreached = 0;
    auto OutOfRange = 0;

    auto Compared = 0;
    auto Mismatched = 0;
    auto Shortcut = 0;
    auto NoReference = 0;

    auto WorstDeltaUu = 0.0;

    for (const auto& Point : Result._Points)
    {
        const auto Walked = Get_FloodDistanceTo(Field, Flood, Point._Location, kStepHeight, Agent);

        if (NOT Walked.IsSet())
        {
            ++Unreached;
            continue;
        }

        if (Walked.GetValue() < MinUu || Walked.GetValue() > MaxUu)
        { ++OutOfRange; }

        if (Compared >= kPathReferenceTargetCount)
        { continue; }

        if (Point._Location.Z > kGroundStoreyMaxZ)
        { continue; }

        if (Get_LabelAtSurface(Field, Point._Surface) != SourceLabel)
        { continue; }

        const auto Reference = Get_ReferenceDistance(Field, Graph, Get_XY(Point._Location));

        if (NOT Reference.IsSet())
        {
            ++NoReference;
            continue;
        }

        ++Compared;

        const auto Delta = Walked.GetValue() - Reference.GetValue();

        WorstDeltaUu = FMath::Max(WorstDeltaUu, FMath::Abs(Delta));

        if (FMath::Abs(Delta) > static_cast<double>(kCellSize))
        { ++Mismatched; }

        // The reference is the shortest path there is, so a walked distance under it is a route the
        // geometry does not offer — which no tolerance on the absolute difference would ever catch.
        if (Delta < -kEpsilon)
        { ++Shortcut; }
    }

    const auto Report = FString::Printf(
        TEXT("%d points in %d attempts, %d off the flood, %d out of range; compared %d against the reference, %d mismatched, %d shortcuts, %d without a reference, worst delta %.4f"),
        Result._Points.Num(), Result._Attempts, Unreached, OutOfRange,
        Compared, Mismatched, Shortcut, NoReference, WorstDeltaUu);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("every point is somewhere an independent flood also reaches [%s]"), *Report),
        Unreached, 0);

    TestEqual(FString::Printf(TEXT("every walked distance lies inside the range asked for [%s]"), *Report),
        OutOfRange, 0);

    if (NOT TestTrue(FString::Printf(TEXT("the reference was consulted about a real sample [%s]"), *Report),
        Compared > 0))
    { return false; }

    TestEqual(FString::Printf(TEXT("every walked distance is within a cell of the exact shortest path [%s]"), *Report),
        Mismatched, 0);

    TestEqual(FString::Printf(TEXT("no walked distance undercuts the exact shortest path [%s]"), *Report),
        Shortcut, 0);

    TestTrue(FString::Printf(TEXT("the draws spent are at least the points returned [%s]"), *Report),
        Result._Attempts >= Result._Points.Num());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_ByPathDistance_ExcludesTheNearAndTheFar,
    "CkTests.UnitTests.CkGroundNav.Query.ByPathDistance_ExcludesTheNearAndTheFar",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_ByPathDistance_ExcludesTheNearAndTheFar::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_points;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto Near = Get_RandomPointsByPathDistance(Field, Make_PathDistanceQuery(
        kPathOrigin, kFarMinUu, kPathMaxUu, kPathCount, kPathSeed));

    if (NOT TestTrue(TEXT("the draw produced points"), Near._Points.Num() > 0))
    { return false; }

    const auto Agent = Make_Agent(0.0f);
    const auto Flood = Get_FloodFill(Field, Make_FloodQuery(kPathOrigin, kPathMaxUu));

    if (NOT TestTrue(TEXT("the independent flood resolved its source"), Flood.Get_IsSuccess()))
    { return false; }

    const auto FarMinUu = static_cast<double>(kFarMinUu);

    auto InsideTheMinimum = 0;

    for (const auto& Point : Near._Points)
    {
        const auto Walked = Get_FloodDistanceTo(Field, Flood, Point._Location, kStepHeight, Agent);

        if (NOT Walked.IsSet() || Walked.GetValue() < FarMinUu)
        { ++InsideTheMinimum; }
    }

    TestEqual(FString::Printf(
        TEXT("nothing was drawn inside the minimum walked distance (%d of %d were)"),
        InsideTheMinimum, Near._Points.Num()),
        InsideTheMinimum, 0);

    // The other half of the contract, and the half a radius cannot express: the far island is within any
    // distance you like as the crow flies, and no distance at all on foot.
    auto IslandField = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two-island scene bakes"),
        Bake(Make_TwoIslandScene(), Make_QueryParams(), IslandField)))
    { return false; }

    const auto Islands = Get_RandomPointsByPathDistance(IslandField, Make_PathDistanceQuery(
        kIslandOrigin, 0.0f, kIslandMaxUu, kIslandCount, kIslandSeed));

    if (NOT TestTrue(TEXT("the two-island draw produced points"), Islands._Points.Num() > 0))
    { return false; }

    const auto IslandFlood = Get_FloodFill(IslandField, Make_FloodQuery(kIslandOrigin, kIslandMaxUu));

    if (NOT TestTrue(TEXT("the two-island flood resolved its source"), IslandFlood.Get_IsSuccess()))
    { return false; }

    const auto IslandLabel = Get_LabelAtSurface(IslandField, IslandFlood._SourceSurface);

    auto ForeignComponent = 0;
    auto AcrossTheGap = 0;

    for (const auto& Point : Islands._Points)
    {
        if (Get_LabelAtSurface(IslandField, Point._Surface) != IslandLabel)
        { ++ForeignComponent; }

        if (Point._Location.X >= kIslandGapMaxX)
        { ++AcrossTheGap; }
    }

    const auto Report = FString::Printf(
        TEXT("%d points in %d attempts, %d on another component, %d across the gap"),
        Islands._Points.Num(), Islands._Attempts, ForeignComponent, AcrossTheGap);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("every point is on the origin's own component [%s]"), *Report),
        ForeignComponent, 0);

    TestEqual(FString::Printf(TEXT("no point is on the island the origin cannot walk to [%s]"), *Report),
        AcrossTheGap, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Grid_OverlappingAlignedQueriesAgree,
    "CkTests.UnitTests.CkGroundNav.Query.Grid_OverlappingAlignedQueriesAgree",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Grid_OverlappingAlignedQueriesAgree::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_points;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto BoxA = FBox{
        FVector{kBoxAMinX, kOverlapMinY, kGridGroundMinZ},
        FVector{kOverlapMaxX, kOverlapMaxY, kGridGroundMaxZ}};

    const auto BoxB = FBox{
        FVector{kOverlapMinX, kOverlapMinY, kGridGroundMinZ},
        FVector{kBoxBMaxX, kOverlapMaxY, kGridGroundMaxZ}};

    const auto Overlap = FBox2D{
        FVector2D{kOverlapMinX, kOverlapMinY},
        FVector2D{kOverlapMaxX, kOverlapMaxY}};

    const auto AlignedA = Get_GridPoints(Field, Make_GridQuery(BoxA, ECk_EnableDisable::Enable));
    const auto AlignedB = Get_GridPoints(Field, Make_GridQuery(BoxB, ECk_EnableDisable::Enable));

    if (NOT TestEqual(TEXT("the first aligned query succeeded"),
        AlignedA._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    if (NOT TestEqual(TEXT("the second aligned query succeeded"),
        AlignedB._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    auto AlignedPositionsA = TArray<FVector2D>{};
    auto AlignedPositionsB = TArray<FVector2D>{};

    Do_CollectXYInRect(AlignedA._Points, Overlap, AlignedPositionsA);
    Do_CollectXYInRect(AlignedB._Points, Overlap, AlignedPositionsB);

    if (NOT TestTrue(TEXT("the overlap holds lattice positions to compare"), AlignedPositionsA.Num() > 0))
    { return false; }

    auto MissingFromB = 0;
    auto MissingFromA = 0;

    for (const auto& Position : AlignedPositionsA)
    {
        if (NOT Get_ContainsXY(AlignedPositionsB, Position))
        { ++MissingFromB; }
    }

    for (const auto& Position : AlignedPositionsB)
    {
        if (NOT Get_ContainsXY(AlignedPositionsA, Position))
        { ++MissingFromA; }
    }

    const auto UnalignedA = Get_GridPoints(Field, Make_GridQuery(BoxA, ECk_EnableDisable::Disable));
    const auto UnalignedB = Get_GridPoints(Field, Make_GridQuery(BoxB, ECk_EnableDisable::Disable));

    auto UnalignedPositionsA = TArray<FVector2D>{};
    auto UnalignedPositionsB = TArray<FVector2D>{};

    Do_CollectXYInRect(UnalignedA._Points, Overlap, UnalignedPositionsA);
    Do_CollectXYInRect(UnalignedB._Points, Overlap, UnalignedPositionsB);

    auto UnalignedShared = 0;

    for (const auto& Position : UnalignedPositionsA)
    {
        if (Get_ContainsXY(UnalignedPositionsB, Position))
        { ++UnalignedShared; }
    }

    const auto Report = FString::Printf(
        TEXT("aligned %d against %d in the overlap, %d and %d unmatched; unaligned %d against %d sharing %d"),
        AlignedPositionsA.Num(), AlignedPositionsB.Num(), MissingFromB, MissingFromA,
        UnalignedPositionsA.Num(), UnalignedPositionsB.Num(), UnalignedShared);

    ck::groundnav::Display(TEXT("{}"), Report);

    TestEqual(FString::Printf(TEXT("every aligned position of the first box is in the second [%s]"), *Report),
        MissingFromB, 0);

    TestEqual(FString::Printf(TEXT("every aligned position of the second box is in the first [%s]"), *Report),
        MissingFromA, 0);

    if (NOT TestTrue(TEXT("the unaligned queries put something in the overlap"),
        UnalignedPositionsA.Num() > 0 && UnalignedPositionsB.Num() > 0))
    { return false; }

    // Phased to their own corners, and their corners are not a whole number of steps apart: two lattices
    // that agreed here would be ignoring the phase they were asked for.
    TestEqual(FString::Printf(TEXT("unaligned boxes out of phase share no position [%s]"), *Report),
        UnalignedShared, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Grid_EveryPointIsNavigableAndDeckSharesXYWithTheGround,
    "CkTests.UnitTests.CkGroundNav.Query.Grid_EveryPointIsNavigableAndDeckSharesXYWithTheGround",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Grid_EveryPointIsNavigableAndDeckSharesXYWithTheGround::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_query_points;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto WholeField = FBox{
        FVector{kGridWholeMinXY, kGridWholeMinXY, kGridGroundMinZ},
        FVector{kGridWholeMaxXY, kGridWholeMaxXY, kGridWholeMaxZ}};

    const auto Lattice = Get_GridPoints(Field, Make_GridQuery(WholeField, ECk_EnableDisable::Enable));

    if (NOT TestEqual(TEXT("the lattice query succeeded"),
        Lattice._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    if (NOT TestTrue(TEXT("the lattice produced points"), Lattice._Points.Num() > 0))
    { return false; }

    auto NotNavigable = 0;
    auto OutsideTheBox = 0;

    for (const auto& Point : Lattice._Points)
    {
        if (NOT Get_IsPointNavigable(Field, Point._Location, kGridAgentRadiusUu))
        { ++NotNavigable; }

        if (Point._Location.Z < kGridGroundMinZ || Point._Location.Z > kGridWholeMaxZ)
        { ++OutsideTheBox; }
    }

    const auto LatticeReport = FString::Printf(
        TEXT("%d lattice points, %d not navigable, %d outside the box"),
        Lattice._Points.Num(), NotNavigable, OutsideTheBox);

    ck::groundnav::Display(TEXT("{}"), LatticeReport);

    TestEqual(FString::Printf(TEXT("every lattice point stands on walkable ground [%s]"), *LatticeReport),
        NotNavigable, 0);

    TestEqual(FString::Printf(TEXT("every lattice point is inside the box asked for [%s]"), *LatticeReport),
        OutsideTheBox, 0);

    // The deck column: a window of the lattice where every position has two storeys under it, so a
    // generator answering one point per position instead of one per storey has nowhere to hide.
    const auto DeckWindow = FBox{
        FVector{kDeckColumnX - kDeckWindowHalfUu, kDeckColumnY - kDeckWindowHalfUu, kGridGroundMinZ},
        FVector{kDeckColumnX + kDeckWindowHalfUu, kDeckColumnY + kDeckWindowHalfUu, kDeckWindowMaxZ}};

    const auto Deck = Get_GridPoints(Field, Make_GridQuery(DeckWindow, ECk_EnableDisable::Enable));

    if (NOT TestEqual(TEXT("the deck window query succeeded"),
        Deck._Status, ECk_NavSurface_QueryStatus::Success))
    { return false; }

    auto Positions = TArray<FVector2D>{};

    for (const auto& Point : Deck._Points)
    {
        const auto Position = Get_XY(Point._Location);

        if (NOT Get_ContainsXY(Positions, Position))
        { Positions.Emplace(Position); }
    }

    if (NOT TestTrue(TEXT("the deck window holds lattice positions"), Positions.Num() > 0))
    { return false; }

    auto WrongStoreyCount = 0;
    auto WrongHeights = 0;
    auto SharedLayer = 0;

    for (const auto& Position : Positions)
    {
        auto Here = TArray<const FCk_GroundNav_GeneratedPoint*>{};

        auto OnTheGround = 0;
        auto OnTheDeck = 0;

        for (const auto& Point : Deck._Points)
        {
            if (Point._Location.X != Position.X || Point._Location.Y != Position.Y)
            { continue; }

            Here.Emplace(&Point);

            if (FMath::Abs(Point._Location.Z - kGroundZ) <= static_cast<double>(kCellHeight))
            { ++OnTheGround; }

            if (FMath::Abs(Point._Location.Z - kDeckTopZ) <= static_cast<double>(kCellHeight))
            { ++OnTheDeck; }
        }

        if (Here.Num() != 2)
        { ++WrongStoreyCount; }

        if (OnTheGround != 1 || OnTheDeck != 1)
        { ++WrongHeights; }

        if (Here.Num() == 2 && Here[0]->_Surface._LayerIndex == Here[1]->_Surface._LayerIndex)
        { ++SharedLayer; }
    }

    const auto DeckReport = FString::Printf(
        TEXT("%d positions over %d points, %d without two storeys, %d without one of each height, %d on one layer"),
        Positions.Num(), Deck._Points.Num(), WrongStoreyCount, WrongHeights, SharedLayer);

    ck::groundnav::Display(TEXT("{}"), DeckReport);

    TestEqual(FString::Printf(TEXT("every position on the deck column carries two points [%s]"), *DeckReport),
        WrongStoreyCount, 0);

    TestEqual(FString::Printf(TEXT("and they are the deck and the ground beneath it [%s]"), *DeckReport),
        WrongHeights, 0);

    TestEqual(FString::Printf(TEXT("answered from two different storeys of the field [%s]"), *DeckReport),
        SharedLayer, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
