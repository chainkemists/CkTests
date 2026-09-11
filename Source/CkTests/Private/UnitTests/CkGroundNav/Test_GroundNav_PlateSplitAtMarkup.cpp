// Where a Cost markup ENDS, a plate ends: the decomposition's third merge criterion, fed from the
// bake's own records.
//
// Stamp_PlateCostPolicies prices a WHOLE plate that any record touches, and cannot do otherwise - a
// plate is the unit everything above the cell grid addresses, and splitting one after it is stamped
// would renumber ids a tile has already published. On a coarse cut that makes a small volume label
// the whole rectangle it landed in, and a filter that DENIES the label then refuses ground the volume
// never covered. The resolution is bought at decomposition time instead: the bake hands
// DoDecompose_Plates a per-cell key derived from the same records the stamp reads, two cells join
// only where the same records cover both, and the label that lands on each piece is exact.
//
// The claim is stated three ways over one bake, because the mechanism has three consequences and only
// the first of them is about plates: the cut follows the record's cell rectangle exactly, the compiled
// filter therefore denies only that rectangle, and a route across the tile at the record's own
// latitude comes back Ready. Falsified whole by dropping the cell-policy view at the DoDecompose_Plates
// call in DoBake_Tile - the middle tile collapses back to one plate, that plate carries the tag, the
// filter denies it, and the crossing between the tiles either side of it stops existing.
//
// A BOX rather than a round volume, for the reason every cell-exact markup assertion is stated over
// one: a box's covered set IS a cell rectangle, so the expected cut is the only one the closed-square
// rule can produce, where a disc leaves the corners of its own bounding rectangle uncovered and the
// expected plate count stops being a statement about the criterion.
//
// The filter and the area tag are the crowd's REAL ones, not local stand-ins: this is the shape the
// crowd's strict planning phase meets on a GroundNav field, and a test that registered its own copy
// would be pinning its own arithmetic.

#include "CkCrowd/CkCrowd_NavGameplayTags.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupMask.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Bake/CkGroundNav_Plates.h"
#include "CkGroundNav/CkGroundNav_Log.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Search/CkGroundNav_FilterCompile.h"
#include "CkGroundNav/Search/CkGroundNav_PathSearch.h"

#include "CkNavigation/Nav/CkNav_Fragment_Data.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"
#include "CkShapes/Sphere/CkShapeSphere_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_platesplitatmarkup
{
    using ck::groundnav::DoBake_Field;
    using ::FCk_GroundNav_AgentProfile;
    using ::FCk_GroundNav_BakeConfig;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ::FCk_GroundNav_MarkupRecord;
    using ck::groundnav::FCk_GroundNav_PathQuery;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::TryGet_CompiledFilterTables;
    using ck::groundnav::Get_FlatPlateIndex;
    using ck::groundnav::Get_IsMarkupCoveringCell;
    using ck::groundnav::Get_Path;

    // ---- The lattice every cell-exact number below is computed against ------------------------------------

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;

    // Three tiles in a row, each 20 cells square, from the world origin: the field covers [0, 1500] in
    // X and [0, 500] in Y, and the MIDDLE tile is the one the record lands in.
    //
    // Three rather than one, because the route half of the claim needs the record's tile to be
    // INTERIOR. With a single tile the whole scene is one plate before the split, so both ends of any
    // route stand on it and the search answers from its same-plate early-out - which is Ready whether
    // the plate was denied or not, and pins nothing.
    constexpr auto kTileSizeUu = 500.0f;
    constexpr auto kTileCells = 20;
    constexpr auto kMiddleTileIndex = 1;
    constexpr auto kMiddleTileOriginX = 500.0;

    constexpr auto kMaxClearanceUu = 100.0f;

    // The record: centred in the middle tile, its footprint [712.5, 787.5] x [212.5, 287.5]. Both ends
    // fall strictly INSIDE a cell rather than on a cell line, so the closed-square rule has nothing to
    // arbitrate: cell 8 spans [700, 725] tile-locally and cell 11 spans [775, 800].
    const auto kRecordCentre = FVector{750.0, 250.0, 0.0};
    const auto kRecordHalfExtents = FVector{37.5, 37.5, 50.0};

    constexpr auto kCoveredMin = 8;
    constexpr auto kCoveredMax = 11;

    constexpr auto kRecordCostMultiplier = 2.0f;

    // ---- The route --------------------------------------------------------------------------------------

    // Both ends stand on the OUTER tiles, at the record's own latitude - Y 250 is tile-local cell 10,
    // which is inside the covered band. A route between them has to cross the middle tile beside the
    // record rather than through it.
    constexpr auto kGroundZ = 0.0;
    constexpr auto kRouteLaneY = 250.0;

    const auto kRouteStart = FVector{250.0, kRouteLaneY, kGroundZ};
    const auto kRouteGoal = FVector{1250.0, kRouteLaneY, kGroundZ};

    constexpr auto kRouteVerticalToleranceUu = 100.0f;

    // Stated for a body of no size: the subject is which ground the filter refuses, and a radius would
    // put an admission question between the assertion and the thing asserted.
    constexpr auto kNoRadius = 0.0f;

    // ----------------------------------------------------------------------------------------------------------------

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        // The ledge filter is off: the subject is the cut, and the conservative default would trim the
        // tiles' borders before a single cell was decided.
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    auto Make_FieldParams(
        const TArray<FCk_GroundNav_MarkupRecord>& InMarkups,
        FIntPoint                                  InDivisions = FIntPoint{3, 1}) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSizeUu);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = InDivisions;
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Make_Profile();
        Params._MarkupRecords = InMarkups;
        Params._MaxClearanceUu = kMaxClearanceUu;

        return Params;
    }

    // Ground reaching past the field on every side, so no tile's halo runs out of world.
    auto Bake_Field(
        const TArray<FCk_GroundNav_MarkupRecord>& InMarkups,
        FCk_GroundNav_Field&                      OutField,
        FIntPoint                                  InDivisions = FIntPoint{3, 1}) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
            TArray<FBox>{FBox{FVector{-200.0, -200.0, -10.0}, FVector{1700.0, 700.0, 0.0}}}};

        return DoBake_Field(Backend, Make_FieldParams(InMarkups, InDivisions), FCk_GroundNav_Epoch{1}, OutField)
            .Get_IsCompleted();
    }

    auto Make_CostRecord() -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            1,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{kRecordHalfExtents}},
            FTransform{kRecordCentre},
            ECk_GroundNav_MarkupKind::Cost};

        Record.Set_AreaTag(TAG_Nav_Area_Crowd_Agent.GetTag());
        Record.Set_CostMultiplier(kRecordCostMultiplier);

        return Record;
    }

    auto Make_DiscCostRecord() -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            2,
            FCk_AnyShape{FCk_ShapeSphere_Dimensions{84.0f}},
            FTransform{FVector{250.0, 250.0, 0.0}},
            ECk_GroundNav_MarkupKind::Cost};

        Record.Set_AreaTag(TAG_Nav_Area_Crowd_Agent.GetTag());
        Record.Set_CostMultiplier(kRecordCostMultiplier);

        return Record;
    }

    auto Get_IsCellCovered(
        int32 InX,
        int32 InY) -> bool
    {
        return InX >= kCoveredMin && InX <= kCoveredMax &&
               InY >= kCoveredMin && InY <= kCoveredMax;
    }

    auto Get_PlateCarriesTheRecordsTag(
        const FCk_GroundNav_PlateField& InPlates,
        int32                           InPlateIndex) -> bool
    {
        if (NOT InPlates._Plates.IsValidIndex(InPlateIndex))
        { return false; }

        return InPlates.Get_AreaPolicy(InPlates._Plates[InPlateIndex]._AreaPolicyIndex)
            .HasTagExact(TAG_Nav_Area_Crowd_Agent);
    }

    auto Make_RouteQuery() -> FCk_GroundNav_PathQuery
    {
        auto Query = FCk_GroundNav_PathQuery{};

        Query._Start = kRouteStart;
        Query._Goal = kRouteGoal;
        Query._VerticalToleranceUu = kRouteVerticalToleranceUu;
        Query._Agent._RadiusUu = kNoRadius;

        return Query;
    }
}

// --------------------------------------------------------------------------------------------------------------------

// The cut itself: the record's cell rectangle is its own plate, and nothing outside it is labelled.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PlateSplitAtMarkup_CostRecordSplitsThePlateAtItsOwnCells,
    "CkTests.UnitTests.CkGroundNav.Bake.PlateSplitAtMarkup_CostRecordSplitsThePlateAtItsOwnCells",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PlateSplitAtMarkup_CostRecordSplitsThePlateAtItsOwnCells::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_platesplitatmarkup;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the three-tile field bakes with the record on it"),
        Bake_Field(TArray<FCk_GroundNav_MarkupRecord>{Make_CostRecord()}, Field)))
    { return false; }

    const auto& Plates = Field._Tiles[kMiddleTileIndex]._Plates;

    ck::groundnav::Display(
        TEXT("[PLATE-SPLIT] middle tile answers [{}] plates over [{}] interned policies"),
        Plates._Plates.Num(), Plates._AreaPolicies.Num());

    // (a) The tile no longer collapses to one rectangle - which it does, exactly, with no record on it
    //     (the control case below).
    if (NOT TestTrue(TEXT("a record over part of the tile cuts it into more than one plate"),
        Plates._Plates.Num() > 1))
    { return false; }

    // (b) Cell by cell, because the two halves of the claim are one statement: a cell the record covers
    //     stands on a labelled plate and a cell it does not stand on an unlabelled one. Counted rather
    //     than asserted per cell so a failure reports how much ground moved.
    auto CoveredButUnlabelled = 0;
    auto UncoveredButLabelled = 0;
    auto CellsWithNoPlate = 0;

    for (auto Y = 0; Y < kTileCells; ++Y)
    {
        for (auto X = 0; X < kTileCells; ++X)
        {
            const auto PlateIndex = Plates.Get_PlateIndexAt(X, Y, 0);

            if (PlateIndex == FCk_GroundNav_Plate::kNoPlate)
            {
                ++CellsWithNoPlate;
                continue;
            }

            const auto IsLabelled = Get_PlateCarriesTheRecordsTag(Plates, PlateIndex);

            if (Get_IsCellCovered(X, Y) && NOT IsLabelled)
            { ++CoveredButUnlabelled; }

            if (NOT Get_IsCellCovered(X, Y) && IsLabelled)
            { ++UncoveredButLabelled; }
        }
    }

    TestEqual(TEXT("the tile is walkable end to end, so every cell answers a plate"), CellsWithNoPlate, 0);
    TestEqual(TEXT("every cell the record covers stands on a labelled plate"), CoveredButUnlabelled, 0);
    TestEqual(TEXT("and no cell outside it does"), UncoveredButLabelled, 0);

    // The same claim from the plate's side: a labelled rectangle lies WHOLLY inside the covered cells,
    // which is what "the label is exact" means for the thing that carries it.
    auto LabelledPlatesOutsideTheRecord = 0;
    auto LabelledPlateCount = 0;

    for (auto PlateIndex = 0; PlateIndex < Plates._Plates.Num(); ++PlateIndex)
    {
        if (NOT Get_PlateCarriesTheRecordsTag(Plates, PlateIndex))
        { continue; }

        ++LabelledPlateCount;

        const auto& Plate = Plates._Plates[PlateIndex];

        const auto IsWhollyCovered =
            Plate._MinX >= kCoveredMin && Plate._MaxX <= kCoveredMax &&
            Plate._MinY >= kCoveredMin && Plate._MaxY <= kCoveredMax;

        if (NOT IsWhollyCovered)
        { ++LabelledPlatesOutsideTheRecord; }

        TestTrue(FString::Printf(TEXT("a labelled plate carries the record's multiplier (was %f)"),
            Plate._CostMultiplier), Plate._CostMultiplier == kRecordCostMultiplier);
    }

    TestTrue(TEXT("the record labelled at least one plate"), LabelledPlateCount > 0);

    TestEqual(TEXT("and no labelled plate reaches ground the record does not cover"),
        LabelledPlatesOutsideTheRecord, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The control: the criterion is INERT without a record. The same bake with nothing painted still
// answers the single rectangle a flat tile has always answered - so the split above is the record's
// and not a change in how flat ground merges.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PlateSplitAtMarkup_NoRecordStillAnswersOnePlate,
    "CkTests.UnitTests.CkGroundNav.Bake.PlateSplitAtMarkup_NoRecordStillAnswersOnePlate",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PlateSplitAtMarkup_NoRecordStillAnswersOnePlate::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_platesplitatmarkup;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the three-tile field bakes with nothing painted on it"),
        Bake_Field({}, Field)))
    { return false; }

    const auto& Plates = Field._Tiles[kMiddleTileIndex]._Plates;

    TestEqual(TEXT("a flat tile carrying no record is exactly one plate"), Plates._Plates.Num(), 1);

    if (NOT TestTrue(TEXT("which it has to be for the count to mean anything"),
        Plates._Plates.Num() == 1))
    { return false; }

    TestEqual(TEXT("covering every cell of the tile"),
        Plates._Plates[0].Get_CellCount(), kTileCells * kTileCells);

    TestEqual(TEXT("and no area policy is interned at all"), Plates._AreaPolicies.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// What the cut buys: the crowd's own excluding filter refuses the record's rectangle and NOTHING else,
// and a route across the middle tile at the record's own latitude comes back Ready.
//
// This is the case the coarse cut got wrong. With the whole tile labelled, the filter denies the whole
// tile, the two outer tiles have no ground between them the search may enter, and a strict planning
// phase answers Unreachable over ground that is plainly open.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PlateSplitAtMarkup_ExcludingFilterDeniesOnlyTheRecordsPlate,
    "CkTests.UnitTests.CkGroundNav.Bake.PlateSplitAtMarkup_ExcludingFilterDeniesOnlyTheRecordsPlate",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PlateSplitAtMarkup_ExcludingFilterDeniesOnlyTheRecordsPlate::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_platesplitatmarkup;

    auto Field = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the three-tile field bakes with the record on it"),
        Bake_Field(TArray<FCk_GroundNav_MarkupRecord>{Make_CostRecord()}, *Field)))
    { return false; }

    const auto Published = FCk_GroundNav_FieldPtr{Field};

    const auto* Tables = TryGet_CompiledFilterTables(
        Published, TAG_Nav_Filter_Crowd_AvoidStandingCrowds, FCk_Nav_QueryFilterOverlay{});

    if (NOT TestNotNull(TEXT("the registered standing-crowd filter compiles"), Tables))
    { return false; }

    ck::groundnav::Display(TEXT("[PLATE-SPLIT] the excluding filter refuses [{}] plates of [{}] tiles"),
        Tables->_Denied.Num(), Field->_Tiles.Num());

    if (NOT TestTrue(TEXT("the filter refuses something"), Tables->_Denied.Num() > 0))
    { return false; }

    // Denied is exactly the labelled set, over the WHOLE field: a plate in an outer tile carries no
    // label at all, so a denial there would be the compile inventing one.
    auto LabelledButAdmitted = 0;
    auto DeniedButUnlabelled = 0;

    for (auto TileIndex = 0; TileIndex < Field->_Tiles.Num(); ++TileIndex)
    {
        const auto& Plates = Field->_Tiles[TileIndex]._Plates;

        for (auto PlateIndex = 0; PlateIndex < Plates._Plates.Num(); ++PlateIndex)
        {
            const auto FlatPlate = Get_FlatPlateIndex(*Field, TileIndex, PlateIndex);
            const auto IsLabelled = Get_PlateCarriesTheRecordsTag(Plates, PlateIndex);

            if (IsLabelled && NOT Tables->_Denied.Contains(FlatPlate))
            { ++LabelledButAdmitted; }

            if (NOT IsLabelled && Tables->_Denied.Contains(FlatPlate))
            { ++DeniedButUnlabelled; }
        }
    }

    TestEqual(TEXT("every plate the record labelled is refused"), LabelledButAdmitted, 0);
    TestEqual(TEXT("and no plate it did not label is"), DeniedButUnlabelled, 0);

    // The route, at the record's own latitude and with the filter's refusals on the query, exactly as
    // the facade puts them there.
    const auto Unfiltered = Get_Path(Published, Make_RouteQuery());

    if (NOT TestEqual(TEXT("the two outer tiles are joined when nothing is refused"),
        Unfiltered._Status, ECk_GroundNav_PathStatus::Ready))
    { return false; }

    auto FilteredQuery = Make_RouteQuery();
    FilteredQuery._Cost._DeniedPlates = Tables->_Denied;

    const auto Filtered = Get_Path(Published, FilteredQuery);

    ck::groundnav::Display(
        TEXT("[PLATE-SPLIT] route under the excluding filter: status [{}] over [{}] plates"),
        Filtered._Status, Filtered._PlateCorridor.Num());

    TestEqual(TEXT("and they are STILL joined once the record's own ground is refused"),
        Filtered._Status, ECk_GroundNav_PathStatus::Ready);

    auto CorridorHoldsADeniedPlate = false;

    for (const auto FlatPlate : Filtered._PlateCorridor)
    {
        if (Tables->_Denied.Contains(FlatPlate))
        { CorridorHoldsADeniedPlate = true; }
    }

    TestFalse(TEXT("by a corridor that goes around the record rather than through it"),
        CorridorHoldsADeniedPlate);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// The production crowd paint is round. This one-tile row derives coverage through the same reducer as
// the bake, then proves the excluding filter still leaves a route around the disc.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_PlateSplitAtMarkup_OneTileDiscKeepsAFilteredDetour,
    "CkTests.UnitTests.CkGroundNav.Bake.PlateSplitAtMarkup_OneTileDiscKeepsAFilteredDetour",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_PlateSplitAtMarkup_OneTileDiscKeepsAFilteredDetour::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_platesplitatmarkup;

    const auto Disc = Make_DiscCostRecord();
    auto Field = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the one-tile disc fixture bakes"),
        Bake_Field(TArray<FCk_GroundNav_MarkupRecord>{Disc}, *Field, FIntPoint{1, 1})))
    { return false; }

    const auto& Plates = Field->_Tiles[0]._Plates;
    TestTrue(TEXT("the disc splits the flat one-tile field"), Plates._Plates.Num() > 1);

    auto CoveredButUnlabelled = 0;
    auto UncoveredButLabelled = 0;
    for (auto Y = 0; Y < kTileCells; ++Y)
    {
        for (auto X = 0; X < kTileCells; ++X)
        {
            const auto PlateIndex = Plates.Get_PlateIndexAt(X, Y, 0);
            if (PlateIndex == FCk_GroundNav_Plate::kNoPlate)
            { continue; }

            const auto Covered = Get_IsMarkupCoveringCell(
                Disc, FVector2D{
                    Field->_Tiles[0]._Origin.X + (float(X) * kCellSize),
                    Field->_Tiles[0]._Origin.Y + (float(Y) * kCellSize)},
                kCellSize, kGroundZ);
            const auto Labelled = Get_PlateCarriesTheRecordsTag(Plates, PlateIndex);

            if (Covered && NOT Labelled)
            { ++CoveredButUnlabelled; }
            if (NOT Covered && Labelled)
            { ++UncoveredButLabelled; }
        }
    }

    TestEqual(TEXT("every disc-covered cell is labelled"), CoveredButUnlabelled, 0);
    TestEqual(TEXT("no cell outside the disc is labelled"), UncoveredButLabelled, 0);

    const auto Published = FCk_GroundNav_FieldPtr{Field};
    const auto* Tables = TryGet_CompiledFilterTables(
        Published, TAG_Nav_Filter_Crowd_AvoidStandingCrowds, FCk_Nav_QueryFilterOverlay{});

    if (NOT TestNotNull(TEXT("the registered standing-crowd filter compiles"), Tables))
    { return false; }

    auto Query = FCk_GroundNav_PathQuery{};
    Query._Start = FVector{100.0, 250.0, kGroundZ};
    Query._Goal = FVector{400.0, 250.0, kGroundZ};
    Query._VerticalToleranceUu = kRouteVerticalToleranceUu;
    Query._Agent._RadiusUu = kNoRadius;
    Query._Cost._DeniedPlates = Tables->_Denied;

    const auto Filtered = Get_Path(Published, Query);
    TestEqual(TEXT("the excluding filter routes around the one-tile disc"),
        Filtered._Status, ECk_GroundNav_PathStatus::Ready);

    auto CorridorUsesDeniedPlate = false;
    for (const auto FlatPlate : Filtered._PlateCorridor)
    {
        if (Tables->_Denied.Contains(FlatPlate))
        { CorridorUsesDeniedPlate = true; }
    }
    TestFalse(TEXT("the detour never enters a disc-labelled plate"), CorridorUsesDeniedPlate);

    auto NoRecordField = FCk_GroundNav_Field{};
    if (NOT TestTrue(TEXT("the one-tile control bakes"), Bake_Field({}, NoRecordField, FIntPoint{1, 1})))
    { return false; }
    TestEqual(TEXT("the no-record one-tile control remains one plate"),
        NoRecordField._Tiles[0]._Plates._Plates.Num(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
