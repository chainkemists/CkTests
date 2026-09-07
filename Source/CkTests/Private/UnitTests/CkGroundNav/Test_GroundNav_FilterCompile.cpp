// What a NEUTRAL query filter tag means on grounded ground, compiled once and read by both ways into
// a search — the one-shot facade query and the sliced path processor.
//
// Recast answers an area tag with a UNavArea and lets the engine filter carry the exclusion; a field
// has no such class, so a filter has to be resolved against the plates THEMSELVES. The claim pinned
// here is the one the crowd's strict planning phase rests on: the crowd registers
// Nav.Filter.Crowd.AvoidStandingCrowds as EXCLUDING Nav.Area.Crowd.Agent, its stationary painter
// stamps that very area tag onto the ground under a standing body, and a plate carrying it must
// therefore come back DENIED rather than merely dear. A denial is what makes "no crowd-free route
// exists" answerable at all — a price would let the search cross the plugged gap and report success.
//
// The definition is the crowd's REAL one, not a local stand-in: CkCrowd's filter registrar is a
// static in CkCrowd_NavGameplayTags.cpp, this file names a tag defined in that same translation
// unit, and TryGet_FilterDefinition flushes every parked registration on its first read. A test that
// registered its own copy would be pinning its own arithmetic.
//
// The field is hand-built rather than baked. Nothing here is about the bake: what a plate's area
// container holds is decided by Stamp_PlateCostPolicies, and what a filter does with it is decided
// by the compile — two plates and one interned container are the whole scene the second question
// needs, and a bake would put a lattice between the assertion and the thing asserted.

#include "CkCore/Macros/CkMacros.h"

#include "CkCrowd/CkCrowd_NavGameplayTags.h"

#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Query/CkGroundNav_Query_Reachability.h"
#include "CkGroundNav/Search/CkGroundNav_FilterCompile.h"

#include "CkNavigation/Nav/CkNav_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_filtercompile
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_Tile;
    using ck::groundnav::Get_CompiledFilterTables;
    using ck::groundnav::Get_FlatPlateIndex;

    // The two plates of the one tile: the first stands under a standing body, the second is clear
    // floor. Indices rather than names because a flat plate id is what the tables are keyed by.
    constexpr auto kMarkedPlateIndex = 0;
    constexpr auto kClearPlateIndex = 1;

    constexpr auto kOnlyTileIndex = 0;

    /**
     * One tile, two plates, one interned area container holding the crowd's own agent area — the
     * shape Stamp_PlateCostPolicies produces for ground a stationary disc covers.
     *
     * Shared by reference the way a search takes a field, because the compile is keyed on that
     * handle: a raw address could name a freed field, and taking the handle is what lets the cache
     * tell a live snapshot from one whose allocation was reused.
     */
    auto Make_TwoPlateField() -> FCk_GroundNav_FieldPtr
    {
        auto Field = MakeShared<FCk_GroundNav_Field>();

        auto Tile = FCk_GroundNav_Tile{};
        Tile._Status = ECk_GroundNav_BuildStatus::Built;
        Tile._SizeX = 2;
        Tile._SizeY = 1;
        Tile._LayerCount = 1;

        Tile._Plates._SizeX = 2;
        Tile._Plates._SizeY = 1;
        Tile._Plates._LayerCount = 1;
        Tile._Plates._AreaPolicies.Emplace(FGameplayTagContainer{TAG_Nav_Area_Crowd_Agent.GetTag()});

        auto MarkedPlate = FCk_GroundNav_Plate{};
        MarkedPlate._MaxX = 0;
        MarkedPlate._AreaPolicyIndex = 0;

        auto ClearPlate = FCk_GroundNav_Plate{};
        ClearPlate._MinX = 1;
        ClearPlate._MaxX = 1;

        Tile._Plates._Plates.Emplace(MarkedPlate);
        Tile._Plates._Plates.Emplace(ClearPlate);
        Tile._Plates._CellToPlate = {kMarkedPlateIndex, kClearPlateIndex};

        Field->_Tiles.Emplace(MoveTemp(Tile));
        Field->_TilePlateOffsets = {0, 2};

        return Field;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_AvoidStandingCrowdsDeniesTheMarkedPlate,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.AvoidStandingCrowdsDeniesTheMarkedPlate",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_AvoidStandingCrowdsDeniesTheMarkedPlate::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_filtercompile;

    const auto Field = Make_TwoPlateField();

    const auto MarkedFlatPlate = Get_FlatPlateIndex(*Field, kOnlyTileIndex, kMarkedPlateIndex);
    const auto ClearFlatPlate = Get_FlatPlateIndex(*Field, kOnlyTileIndex, kClearPlateIndex);

    if (NOT TestTrue(TEXT("the fixture's two plates both have a flat id"),
        MarkedFlatPlate != INDEX_NONE && ClearFlatPlate != INDEX_NONE))
    { return false; }

    const auto& Tables = Get_CompiledFilterTables(
        Field, TAG_Nav_Filter_Crowd_AvoidStandingCrowds, FCk_Nav_QueryFilterOverlay{});

    TestTrue(TEXT("the plate under a standing body is REFUSED, not merely priced"),
        Tables._Denied.Contains(MarkedFlatPlate));

    TestFalse(TEXT("and clear floor beside it is left alone"),
        Tables._Denied.Contains(ClearFlatPlate));

    // The crowd's definition excludes and prices nothing, so a multiplier here would mean the compile
    // had invented a price the registered definition never named.
    TestEqual(TEXT("a filter that only excludes produces no cost table"),
        Tables._Multipliers.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNavFilterCompile_NoFilterRefusesNothing,
    "CkTests.UnitTests.CkGroundNav.FilterCompile.NoFilterRefusesNothing",
    kCkUnitTestFlags)

bool FCkTest_GroundNavFilterCompile_NoFilterRefusesNothing::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_filtercompile;

    const auto Field = Make_TwoPlateField();

    // The permissive phase names no filter and no overlay. The very same marked plate must come back
    // walkable, because a phase that refused it either way would make the strict phase mean nothing.
    const auto& Tables = Get_CompiledFilterTables(
        Field, FGameplayTag{}, FCk_Nav_QueryFilterOverlay{});

    TestEqual(TEXT("a query naming no filter refuses no plate"), Tables._Denied.Num(), 0);
    TestEqual(TEXT("and prices none"), Tables._Multipliers.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
