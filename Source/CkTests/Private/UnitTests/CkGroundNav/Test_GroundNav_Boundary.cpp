// The boundary runs a bake produces, and the winding every consumer reads them by.
//
// A boundary run is the one piece of the field a consumer is told it may trust WITHOUT re-deriving:
// the interior is on the left of the walk, so the inward normal is read rather than recomputed. That
// makes the winding a contract rather than an implementation detail, and this file pins it over every
// run of every tile instead of over a hand-picked few. Beside it sit the three properties that decide
// whether a run means anything at all: that two bakes of one scene produce byte-identical runs, that
// no run lies where a crossing already does, and that a tile rim is a wall exactly where no seam
// crosses it — including when the neighbour has been taken away.

#include "CkGroundNav/Bake/CkGroundNav_Boundary.h"
#include "CkGroundNav/Bake/CkGroundNav_Walkability.h"
#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_QueryFixtures.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_boundary
{
    using ck::groundnav::DoDerive_SeamPortals;
    using ck::groundnav::DoLabel_Reachability;
    using ck::groundnav::FCk_GroundNav_BoundaryField;
    using ck::groundnav::FCk_GroundNav_BoundarySegment;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_Tile;
    using ck::groundnav::FCk_GroundNav_TileCoord;
    using ck::groundnav::Get_DirectionOffset;
    using ck::groundnav::Get_TileIndex;

    using ck_test_groundnav_queryfixtures::Bake_QueryScene;
    using ck_test_groundnav_queryfixtures::Get_TileCentre;

    constexpr auto kBakeCount = 20;

    // The winding is derived from integer cell corners, so the normal is exactly axial and the run is
    // exactly perpendicular to it. Only the float-to-double widening of a stored height is slack.
    constexpr auto kNormalTolerance = 1.0e-6;
    constexpr auto kLengthTolerance = 1.0e-3;

    constexpr auto kSideCount = 4;
    constexpr auto kEastSide = 0;
    constexpr auto kNorthSide = 1;

    // ----------------------------------------------------------------------------------------------------------------

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

    auto Get_SegmentListsAreIdentical(
        TConstArrayView<FCk_GroundNav_BoundarySegment> InLeft,
        TConstArrayView<FCk_GroundNav_BoundarySegment> InRight) -> bool
    {
        if (InLeft.Num() != InRight.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft.Num(); ++Index)
        {
            if (NOT Get_SegmentsAreIdentical(InLeft[Index], InRight[Index]))
            { return false; }
        }

        return true;
    }

    auto Get_BucketsAreIdentical(
        const FCk_GroundNav_BoundaryField& InLeft,
        const FCk_GroundNav_BoundaryField& InRight) -> bool
    {
        if (InLeft._BucketsX != InRight._BucketsX ||
            InLeft._BucketsY != InRight._BucketsY ||
            InLeft._Buckets.Num() != InRight._Buckets.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft._Buckets.Num(); ++Index)
        {
            if (InLeft._Buckets[Index] != InRight._Buckets[Index])
            { return false; }
        }

        return true;
    }

    /** What differs between two bakes of one scene, named so a failure can be read rather than guessed at. */
    auto Get_BoundaryDifference(
        const FCk_GroundNav_Field& InLeft,
        const FCk_GroundNav_Field& InRight) -> FString
    {
        if (InLeft._Tiles.Num() != InRight._Tiles.Num())
        {
            return FString::Printf(TEXT("tile count %d vs %d"), InLeft._Tiles.Num(), InRight._Tiles.Num());
        }

        for (auto TileIndex = 0; TileIndex < InLeft._Tiles.Num(); ++TileIndex)
        {
            const auto& LeftBoundary = InLeft._Tiles[TileIndex]._Boundary;
            const auto& RightBoundary = InRight._Tiles[TileIndex]._Boundary;

            if (NOT Get_SegmentListsAreIdentical(LeftBoundary._Segments, RightBoundary._Segments))
            {
                return FString::Printf(TEXT("tile %d segments (%d vs %d)"),
                    TileIndex, LeftBoundary._Segments.Num(), RightBoundary._Segments.Num());
            }

            if (NOT Get_SegmentListsAreIdentical(LeftBoundary._EdgeCandidates, RightBoundary._EdgeCandidates))
            {
                return FString::Printf(TEXT("tile %d edge candidates (%d vs %d)"),
                    TileIndex, LeftBoundary._EdgeCandidates.Num(), RightBoundary._EdgeCandidates.Num());
            }

            if (NOT Get_BucketsAreIdentical(LeftBoundary, RightBoundary))
            {
                return FString::Printf(TEXT("tile %d buckets"), TileIndex);
            }

            if (NOT Get_SegmentListsAreIdentical(
                InLeft.Get_TileEdgeBoundary(TileIndex), InRight.Get_TileEdgeBoundary(TileIndex)))
            {
                return FString::Printf(TEXT("tile %d rim boundary (%d vs %d)"),
                    TileIndex,
                    InLeft.Get_TileEdgeBoundary(TileIndex).Num(),
                    InRight.Get_TileEdgeBoundary(TileIndex).Num());
            }
        }

        return FString{};
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_CellIsInRun(
        const FCk_GroundNav_BoundarySegment& InSegment,
        const FIntPoint&                     InCell) -> bool
    {
        const auto MinX = FMath::Min(InSegment._FromCell.X, InSegment._ToCell.X);
        const auto MaxX = FMath::Max(InSegment._FromCell.X, InSegment._ToCell.X);
        const auto MinY = FMath::Min(InSegment._FromCell.Y, InSegment._ToCell.Y);
        const auto MaxY = FMath::Max(InSegment._FromCell.Y, InSegment._ToCell.Y);

        return InCell.X >= MinX && InCell.X <= MaxX && InCell.Y >= MinY && InCell.Y <= MaxY;
    }

    /** How many of the given runs cover one cell of one plate on one face. */
    auto Get_RunCoverCount(
        TConstArrayView<FCk_GroundNav_BoundarySegment> InRuns,
        int32                                          InPlateIndex,
        int32                                          InLayerIndex,
        int32                                          InSide,
        const FIntPoint&                               InCell) -> int32
    {
        auto Count = 0;

        for (const auto& Run : InRuns)
        {
            if (Run._Side != InSide || Run._PlateIndex != InPlateIndex || Run._LayerIndex != InLayerIndex)
            { continue; }

            if (Get_CellIsInRun(Run, InCell))
            { ++Count; }
        }

        return Count;
    }

    /** How many seam portals cross one plate of one tile at one position along one rim face. */
    auto Get_SeamCoverCount(
        const FCk_GroundNav_Field& InField,
        int32                      InTileIndex,
        int32                      InPlateIndex,
        int32                      InSide,
        int32                      InAlong) -> int32
    {
        const auto Axis = InSide % 2;
        const auto IsPositiveSide = InSide == kEastSide || InSide == kNorthSide;

        auto Count = 0;

        for (const auto& Seam : InField._SeamPortals)
        {
            if (Seam._Direction != Axis || InAlong < Seam._AlongMin || InAlong > Seam._AlongMax)
            { continue; }

            const auto Covers = IsPositiveSide
                ? Seam._TileIndexA == InTileIndex && Seam._PlateA == InPlateIndex
                : Seam._TileIndexB == InTileIndex && Seam._PlateB == InPlateIndex;

            if (Covers)
            { ++Count; }
        }

        return Count;
    }

    /** The rim cell of a tile at a position along one of its outward faces. */
    auto Get_RimCell(
        const FCk_GroundNav_Tile& InTile,
        int32                     InSide,
        int32                     InAlong) -> FIntPoint
    {
        return InSide == kEastSide
            ? FIntPoint{InTile._SizeX - 1, InAlong}
            : FIntPoint{InAlong, InTile._SizeY - 1};
    }

    auto Get_RimLength(
        const FCk_GroundNav_Tile& InTile,
        int32                     InSide) -> int32
    {
        return InSide == kEastSide ? InTile._SizeY : InTile._SizeX;
    }

    struct FRimCoverage
    {
        int32 _WalkableRimCells = 0;
        int32 _CoveredByRuns = 0;
        int32 _CoveredBySeams = 0;
        int32 _CoveredTwiceOrMore = 0;
        int32 _Uncovered = 0;
        int32 _CoveredWhereNothingIsWalkable = 0;
    };

    /**
     * Walk one outward face of one tile cell by cell and account for every walkable rim cell: a rim
     * cell is either crossed by a seam or walled by a run, and never both and never neither.
     */
    auto Get_RimCoverage(
        const FCk_GroundNav_Field& InField,
        int32                      InTileIndex,
        int32                      InSide) -> FRimCoverage
    {
        const auto& Tile = InField._Tiles[InTileIndex];
        const auto Runs = InField.Get_TileEdgeBoundary(InTileIndex);

        auto Coverage = FRimCoverage{};

        for (auto Along = 0; Along < Get_RimLength(Tile, InSide); ++Along)
        {
            const auto Cell = Get_RimCell(Tile, InSide, Along);

            for (auto Layer = 0; Layer < Tile._LayerCount; ++Layer)
            {
                const auto PlateIndex = Tile._Plates.Get_PlateIndexAt(Cell.X, Cell.Y, Layer);

                if (PlateIndex == FCk_GroundNav_Plate::kNoPlate)
                {
                    for (const auto& Run : Runs)
                    {
                        if (Run._Side == InSide && Run._LayerIndex == Layer && Get_CellIsInRun(Run, Cell))
                        { ++Coverage._CoveredWhereNothingIsWalkable; }
                    }

                    continue;
                }

                ++Coverage._WalkableRimCells;

                const auto RunCount = Get_RunCoverCount(Runs, PlateIndex, Layer, InSide, Cell);
                const auto SeamCount = Get_SeamCoverCount(InField, InTileIndex, PlateIndex, InSide, Along);

                Coverage._CoveredByRuns += RunCount;
                Coverage._CoveredBySeams += SeamCount;

                if (RunCount + SeamCount > 1)
                { ++Coverage._CoveredTwiceOrMore; }

                if (RunCount + SeamCount == 0)
                { ++Coverage._Uncovered; }
            }
        }

        return Coverage;
    }

    auto Get_CoverageReport(
        const FRimCoverage& InCoverage) -> FString
    {
        return FString::Printf(
            TEXT("walkable rim cells %d, by runs %d, by seams %d, doubled %d, uncovered %d, spurious %d"),
            InCoverage._WalkableRimCells, InCoverage._CoveredByRuns, InCoverage._CoveredBySeams,
            InCoverage._CoveredTwiceOrMore, InCoverage._Uncovered, InCoverage._CoveredWhereNothingIsWalkable);
    }

    // ----------------------------------------------------------------------------------------------------------------

    struct FWindingFailure
    {
        int32 _RunsChecked = 0;
        int32 _CellNotOnItsPlate = 0;
        int32 _AcrossIsSamePlate = 0;
        int32 _NormalIsNotInward = 0;
        int32 _RunIsNotPerpendicular = 0;
        int32 _LengthDisagreesWithCellCount = 0;
        int32 _NormalIsNotTheLeftPerpendicular = 0;
    };

    auto Do_CheckWinding(
        const FCk_GroundNav_Tile&            InTile,
        const FCk_GroundNav_BoundarySegment& InSegment,
        FWindingFailure&                     InOutFailure) -> void
    {
        ++InOutFailure._RunsChecked;

        const auto Offset = Get_DirectionOffset(InSegment._Side);
        const FIntPoint Cells[]{InSegment._FromCell, InSegment._ToCell};

        for (const auto& Cell : Cells)
        {
            if (InTile._Plates.Get_PlateIndexAt(Cell.X, Cell.Y, InSegment._LayerIndex) != InSegment._PlateIndex)
            { ++InOutFailure._CellNotOnItsPlate; }

            const auto Across = FIntPoint{Cell.X + Offset.X, Cell.Y + Offset.Y};
            const auto AcrossIsInsideTile =
                Across.X >= 0 && Across.Y >= 0 && Across.X < InTile._SizeX && Across.Y < InTile._SizeY;

            if (AcrossIsInsideTile &&
                InTile._Plates.Get_PlateIndexAt(Across.X, Across.Y, InSegment._LayerIndex) == InSegment._PlateIndex)
            { ++InOutFailure._AcrossIsSamePlate; }
        }

        const auto ExpectedNormal = FVector2D{-static_cast<double>(Offset.X), -static_cast<double>(Offset.Y)};

        if (NOT InSegment._InwardNormalXY.Equals(ExpectedNormal, kNormalTolerance))
        { ++InOutFailure._NormalIsNotInward; }

        const auto Along = FVector2D{
            InSegment._End.X - InSegment._Start.X,
            InSegment._End.Y - InSegment._Start.Y};

        if (FMath::Abs(FVector2D::DotProduct(Along, InSegment._InwardNormalXY)) > kNormalTolerance)
        { ++InOutFailure._RunIsNotPerpendicular; }

        const auto ExpectedLength =
            static_cast<double>(InSegment.Get_CellCount()) * static_cast<double>(InTile._CellSizeUu);

        if (FMath::Abs(Along.Size() - ExpectedLength) > kLengthTolerance)
        { ++InOutFailure._LengthDisagreesWithCellCount; }

        const auto CrossZ =
            (Along.X * InSegment._InwardNormalXY.Y) - (Along.Y * InSegment._InwardNormalXY.X);

        if (CrossZ <= 0.0)
        { ++InOutFailure._NormalIsNotTheLeftPerpendicular; }
    }

    auto Get_WindingReport(
        const FWindingFailure& InFailure) -> FString
    {
        return FString::Printf(
            TEXT("runs %d, off-plate cells %d, across-is-same-plate %d, normal-not-inward %d, ")
            TEXT("not-perpendicular %d, wrong-length %d, not-left-perpendicular %d"),
            InFailure._RunsChecked, InFailure._CellNotOnItsPlate, InFailure._AcrossIsSamePlate,
            InFailure._NormalIsNotInward, InFailure._RunIsNotPerpendicular,
            InFailure._LengthDisagreesWithCellCount, InFailure._NormalIsNotTheLeftPerpendicular);
    }

    auto Get_WindingIsClean(
        const FWindingFailure& InFailure) -> bool
    {
        return InFailure._CellNotOnItsPlate == 0 &&
               InFailure._AcrossIsSamePlate == 0 &&
               InFailure._NormalIsNotInward == 0 &&
               InFailure._RunIsNotPerpendicular == 0 &&
               InFailure._LengthDisagreesWithCellCount == 0 &&
               InFailure._NormalIsNotTheLeftPerpendicular == 0;
    }

    // ----------------------------------------------------------------------------------------------------------------

    auto Get_NorthTileIndex(
        const FCk_GroundNav_Field& InField) -> int32
    {
        return Get_TileIndex(InField._Params._Divisions, FCk_GroundNav_TileCoord{0, 1});
    }

    auto Do_RestoreTile(
        FCk_GroundNav_Field& InOutField,
        int32                InTileIndex) -> void
    {
        InOutField._Tiles[InTileIndex]._Status = ECk_GroundNav_BuildStatus::Built;

        DoDerive_SeamPortals(InOutField);
        DoLabel_Reachability(InOutField);
    }

    auto Get_RunsCopy(
        const FCk_GroundNav_Field& InField,
        int32                      InTileIndex,
        int32                      InSide) -> TArray<FCk_GroundNav_BoundarySegment>
    {
        auto Runs = TArray<FCk_GroundNav_BoundarySegment>{};

        for (const auto& Run : InField.Get_TileEdgeBoundary(InTileIndex))
        {
            if (Run._Side == InSide)
            { Runs.Emplace(Run); }
        }

        return Runs;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Boundary_IsDeterministicAcrossBakes,
    "CkTests.UnitTests.CkGroundNav.Bake.Boundary_IsDeterministicAcrossBakes",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Boundary_IsDeterministicAcrossBakes::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_boundary;

    auto First = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(First)))
    { return false; }

    auto FirstSegmentCount = 0;
    auto FirstRimRunCount = 0;

    for (auto TileIndex = 0; TileIndex < First._Tiles.Num(); ++TileIndex)
    {
        FirstSegmentCount += First._Tiles[TileIndex]._Boundary._Segments.Num();
        FirstRimRunCount += First.Get_TileEdgeBoundary(TileIndex).Num();
    }

    if (NOT TestTrue(FString::Printf(
        TEXT("the scene produces boundary runs worth comparing (within-tile %d, rim %d)"),
        FirstSegmentCount, FirstRimRunCount), FirstSegmentCount > 0 && FirstRimRunCount > 0))
    { return false; }

    auto FirstDifference = FString{};
    int32 DifferingBake = INDEX_NONE;

    for (auto BakeIndex = 1; BakeIndex < kBakeCount; ++BakeIndex)
    {
        auto Other = FCk_GroundNav_Field{};

        if (NOT TestTrue(FString::Printf(TEXT("bake %d of the same scene completes"), BakeIndex),
            Bake_QueryScene(Other)))
        { return false; }

        const auto Difference = Get_BoundaryDifference(First, Other);

        if (Difference.IsEmpty())
        { continue; }

        FirstDifference = Difference;
        DifferingBake = BakeIndex;
        break;
    }

    // The decomposition, the crossing extraction and the winding are all deterministic, so this is an
    // equality and never a tolerance: a run that moved by a float is a propagation bug, not noise.
    TestTrue(FString::Printf(
        TEXT("%d bakes of one scene produce byte-identical boundary runs (bake %d differs: %s)"),
        kBakeCount, DifferingBake, *FirstDifference), FirstDifference.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Boundary_InteriorIsOnTheLeftOfEveryRun,
    "CkTests.UnitTests.CkGroundNav.Bake.Boundary_InteriorIsOnTheLeftOfEveryRun",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Boundary_InteriorIsOnTheLeftOfEveryRun::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    auto Failure = FWindingFailure{};

    for (auto TileIndex = 0; TileIndex < Field._Tiles.Num(); ++TileIndex)
    {
        const auto& Tile = Field._Tiles[TileIndex];

        if (NOT Tile.Get_IsBuilt())
        { continue; }

        for (const auto& Segment : Tile._Boundary._Segments)
        { Do_CheckWinding(Tile, Segment, Failure); }

        for (const auto& Segment : Field.Get_TileEdgeBoundary(TileIndex))
        { Do_CheckWinding(Tile, Segment, Failure); }
    }

    const auto Report = Get_WindingReport(Failure);

    ck::groundnav::Display(TEXT("{}"), Report);

    if (NOT TestTrue(FString::Printf(TEXT("the scene has runs to check [%s]"), *Report), Failure._RunsChecked > 0))
    { return false; }

    // One assertion over every run of every tile rather than several over a chosen few: the winding is
    // what lets a consumer read the inward normal instead of deriving it, so a single run that breaks
    // it is a consumer reasoning about the wrong side of a wall.
    TestTrue(FString::Printf(TEXT("every boundary run winds with its plate on the left [%s]"), *Report),
        Get_WindingIsClean(Failure));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Boundary_NoRunLiesOnAPortal,
    "CkTests.UnitTests.CkGroundNav.Bake.Boundary_NoRunLiesOnAPortal",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Boundary_NoRunLiesOnAPortal::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    auto CrossingCellPairs = 0;
    auto RunsOnACrossing = 0;

    for (const auto& Tile : Field._Tiles)
    {
        if (NOT Tile.Get_IsBuilt())
        { continue; }

        for (const auto& Portal : Tile._Portals._Portals)
        {
            const auto Offset = Get_DirectionOffset(Portal._Direction);
            const auto FarSide = (Portal._Direction + 2) % kSideCount;

            for (auto CellY = Portal._FromMin.Y; CellY <= Portal._FromMax.Y; ++CellY)
            {
                for (auto CellX = Portal._FromMin.X; CellX <= Portal._FromMax.X; ++CellX)
                {
                    ++CrossingCellPairs;

                    const auto NearCell = FIntPoint{CellX, CellY};
                    const auto FarCell = FIntPoint{CellX + Offset.X, CellY + Offset.Y};

                    RunsOnACrossing += Get_RunCoverCount(
                        Tile._Boundary._Segments, Portal._PlateA,
                        Tile._Plates._Plates[Portal._PlateA]._LayerIndex, Portal._Direction, NearCell);

                    RunsOnACrossing += Get_RunCoverCount(
                        Tile._Boundary._Segments, Portal._PlateB,
                        Tile._Plates._Plates[Portal._PlateB]._LayerIndex, FarSide, FarCell);
                }
            }
        }
    }

    if (NOT TestTrue(FString::Printf(TEXT("the scene has crossings to check (%d cell pairs)"), CrossingCellPairs),
        CrossingCellPairs > 0))
    { return false; }

    // A run and a crossing on the same cell face are contradictory answers to one question, and the
    // consumer that reads them cannot tell which one is the lie.
    TestEqual(FString::Printf(
        TEXT("no boundary run lies on a crossing (%d cell pairs checked)"), CrossingCellPairs),
        RunsOnACrossing, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Boundary_SeamsAreNotWalls,
    "CkTests.UnitTests.CkGroundNav.Bake.Boundary_SeamsAreNotWalls",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Boundary_SeamsAreNotWalls::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto OriginTile = Get_TileIndex(Field._Params._Divisions, FCk_GroundNav_TileCoord{0, 0});

    const auto EastCoverage = Get_RimCoverage(Field, OriginTile, kEastSide);
    const auto NorthCoverage = Get_RimCoverage(Field, OriginTile, kNorthSide);

    const auto EastReport = Get_CoverageReport(EastCoverage);
    const auto NorthReport = Get_CoverageReport(NorthCoverage);

    ck::groundnav::Display(TEXT("{}"), FString::Printf(
        TEXT("origin tile east rim: %s ; north rim: %s"), *EastReport, *NorthReport));

    if (NOT TestTrue(FString::Printf(TEXT("the origin tile has walkable ground on both rims [%s | %s]"),
        *EastReport, *NorthReport),
        EastCoverage._WalkableRimCells > 0 && NorthCoverage._WalkableRimCells > 0))
    { return false; }

    // The dividing wall reaches the field's own east edge, so the origin tile's east rim is a drop of
    // 300 uu on both sides of the seam and carries no crossing at all. Its north rim is where the
    // floor is continuous, and it is the half of this test that exercises a seam.
    if (NOT TestTrue(FString::Printf(TEXT("the north rim is crossed by seams [%s]"), *NorthReport),
        NorthCoverage._CoveredBySeams > 0))
    { return false; }

    TestEqual(FString::Printf(TEXT("every walkable east rim cell is walled or crossed, never both [%s]"),
        *EastReport), EastCoverage._CoveredTwiceOrMore, 0);
    TestEqual(FString::Printf(TEXT("and never neither [%s]"), *EastReport), EastCoverage._Uncovered, 0);

    TestEqual(FString::Printf(TEXT("every walkable north rim cell is walled or crossed, never both [%s]"),
        *NorthReport), NorthCoverage._CoveredTwiceOrMore, 0);
    TestEqual(FString::Printf(TEXT("and never neither [%s]"), *NorthReport), NorthCoverage._Uncovered, 0);

    TestEqual(FString::Printf(TEXT("no run walls a rim cell nothing can stand on [%s | %s]"),
        *EastReport, *NorthReport),
        EastCoverage._CoveredWhereNothingIsWalkable + NorthCoverage._CoveredWhereNothingIsWalkable, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Boundary_AnUnbuiltNeighbourMakesTheRimAWall,
    "CkTests.UnitTests.CkGroundNav.Bake.Boundary_AnUnbuiltNeighbourMakesTheRimAWall",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Boundary_AnUnbuiltNeighbourMakesTheRimAWall::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_boundary;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the query scene bakes"), Bake_QueryScene(Field)))
    { return false; }

    const auto OriginTile = Get_TileIndex(Field._Params._Divisions, FCk_GroundNav_TileCoord{0, 0});
    const auto NorthTile = Get_NorthTileIndex(Field);

    const auto RecordedRuns = Get_RunsCopy(Field, OriginTile, kNorthSide);
    const auto RecordedCoverage = Get_RimCoverage(Field, OriginTile, kNorthSide);

    if (NOT TestTrue(FString::Printf(TEXT("the north rim starts out crossed by seams [%s]"),
        *Get_CoverageReport(RecordedCoverage)), RecordedCoverage._CoveredBySeams > 0))
    { return false; }

    const auto TakenTile = ck_test_groundnav_queryfixtures::Do_MakeTileUnbuiltAt(
        Field, Get_TileCentre(Field, NorthTile));

    if (NOT TestEqual(TEXT("the tile taken away is the origin tile's northern neighbour"),
        TakenTile, NorthTile))
    { return false; }

    const auto WalledCoverage = Get_RimCoverage(Field, OriginTile, kNorthSide);
    const auto WalledReport = Get_CoverageReport(WalledCoverage);

    // Nothing is known past an unbuilt neighbour, so the whole rim becomes a wall. A body kept off it
    // is kept safe; a body let through it is walking on ground nobody has looked at.
    TestEqual(FString::Printf(TEXT("an unbuilt neighbour leaves no crossings on the rim [%s]"), *WalledReport),
        WalledCoverage._CoveredBySeams, 0);
    TestEqual(FString::Printf(TEXT("and every walkable rim cell is walled [%s]"), *WalledReport),
        WalledCoverage._Uncovered, 0);
    TestEqual(FString::Printf(TEXT("exactly once [%s]"), *WalledReport),
        WalledCoverage._CoveredTwiceOrMore, 0);
    TestEqual(FString::Printf(TEXT("over the same walkable rim the built neighbour had [%s]"), *WalledReport),
        WalledCoverage._WalkableRimCells, RecordedCoverage._WalkableRimCells);

    Do_RestoreTile(Field, NorthTile);

    const auto RestoredRuns = Get_RunsCopy(Field, OriginTile, kNorthSide);

    // Re-deriving from the same tiles must land on exactly the runs the first composition produced,
    // in the same order: the rim boundary is a product of the tiles, never a patch on top of them.
    TestTrue(FString::Printf(TEXT("restoring the neighbour restores the rim runs exactly (%d vs %d)"),
        RestoredRuns.Num(), RecordedRuns.Num()),
        Get_SegmentListsAreIdentical(RecordedRuns, RestoredRuns));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
