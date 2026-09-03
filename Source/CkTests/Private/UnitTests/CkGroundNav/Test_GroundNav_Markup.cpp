// Authored markup volumes, and the two halves of what they decide.
//
// The halves are deliberately not one mechanism. A Walkability volume is a BAKE INPUT: it demotes a
// span exactly as too little headroom does, and the cells it covers then have no layer, no plate, no
// portal and no boundary run — so nothing downstream is ever patched, and the tests below say so by
// asserting that switching a volume off restores the field with no tolerance at all. A Cost volume is
// a PLATE LABEL: it changes nothing about the shape of the world, which is what lets it be applied by
// copying a published field and restamping its plates for zero probes.
//
// Every assertion here is exact. The cell rectangles are hand-computed against a lattice whose origin
// and cell size the fixture fixes, and the field comparisons are member-by-member equality rather
// than a tolerance: a markup test that accepted "close enough" would pass through the off-by-one that
// paints the cell beside the one that was authored.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_Layers.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Bake/CkGroundNav_Plates.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"
#include "CkGroundNav/Bake/CkGroundNav_Walkability.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldMarkupCost.h"
#include "CkGroundNav/Field/CkGroundNav_TileBake.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include "NativeGameplayTags.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Markup_Slow, "CkTests.GroundNav.Markup.Slow");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Markup_Mud, "CkTests.GroundNav.Markup.Mud");

namespace ck_test_groundnav_markup
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::DoBake_Tile;
    using ck::groundnav::DoDecompose_Plates;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_BoundarySegment;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_PlateField;
    using ck::groundnav::FCk_GroundNav_Portal;
    using ck::groundnav::FCk_GroundNav_SeamPortal;
    using ck::groundnav::FCk_GroundNav_SeamStub;
    using ck::groundnav::FCk_GroundNav_SpanField;
    using ck::groundnav::FCk_GroundNav_Tile;
    using ck::groundnav::FCk_GroundNav_TileBakeParams;
    using ck::groundnav::FCk_GroundNav_TileCoord;
    using ck::groundnav::Get_FieldWithMarkupCost;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;

    // ---- The flat lattice the cell-exact assertions are computed against ---------------------------------

    // 40 x 40 cells of 25 uu from the world origin, so the lattice covers [0, 1000] on both axes.
    constexpr auto kFlatExtentUu = 1000.0;
    constexpr auto kFlatCells = 40;

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        // The ledge filter is off throughout: the subject here is markup, and the conservative default
        // would trim the fixtures' borders before a single volume was applied.
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    auto Make_Markup(
        int32                    InId,
        const FVector&           InCentre,
        const FVector&           InHalfExtents,
        ECk_GroundNav_MarkupKind InKind) -> FCk_GroundNav_MarkupRecord
    {
        return FCk_GroundNav_MarkupRecord{
            InId,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{InHalfExtents}},
            FTransform{InCentre},
            InKind};
    }

    struct FBakeResult
    {
        FCk_GroundNav_SpanField _Spans;
        FCk_GroundNav_LayerField _Layers;
        bool _Completed = false;
    };

    auto Bake_Flat(
        TConstArrayView<FCk_GroundNav_MarkupRecord> InMarkups) -> FBakeResult
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{FVector{0.0, 0.0, 0.0}, FVector{kFlatExtentUu, kFlatExtentUu, 10.0}});

        const auto Region = FBox{
            FVector{0.0, 0.0, -50.0}, FVector{kFlatExtentUu, kFlatExtentUu, 400.0}};

        const auto Profile = Make_Profile();
        const auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};

        auto Result = FBakeResult{};

        if (NOT DoRasterizeSpans(Geometry, Region, Config, Profile, Result._Spans).Get_IsCompleted())
        { return Result; }

        auto Connections = FCk_GroundNav_ConnectionField{};

        if (NOT DoFilter_Walkability(Profile, Result._Spans, Connections, InMarkups).Get_IsCompleted())
        { return Result; }

        Result._Completed = DoExtract_Layers(
            Result._Spans, Connections, Result._Layers).Get_IsCompleted();

        return Result;
    }

    // ---- Tiled fixtures ----------------------------------------------------------------------------------

    constexpr auto kTileFieldOriginUu = 1000.0;
    constexpr auto kTileGroundExtentUu = 3000.0;
    constexpr auto kTileMaxClearance = 200.0f;

    // Ground reaching far past every tile under test, so no tile's halo runs out of world.
    auto Make_WideGround() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};
        Geometry.Add_Box(FBox{
            FVector{0.0, 0.0, -10.0},
            FVector{kTileGroundExtentUu, kTileGroundExtentUu, 0.0}});

        return Geometry;
    }

    auto Make_TileParams(
        float                          InTileSizeUu,
        const FCk_GroundNav_TileCoord& InCoord) -> FCk_GroundNav_TileBakeParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(InTileSizeUu);

        auto Params = FCk_GroundNav_TileBakeParams{};

        Params._Coord = InCoord;
        Params._Epoch = FCk_GroundNav_Epoch{1};
        Params._FieldOriginXY = FVector2D{kTileFieldOriginUu, kTileFieldOriginUu};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 400.0f;
        Params._Config = Config;
        Params._Profile = Make_Profile();
        Params._MaxClearanceUu = kTileMaxClearance;

        return Params;
    }

    // ---- Field fixtures ----------------------------------------------------------------------------------

    constexpr auto kFieldTileSize = 400.0f;
    constexpr auto kFieldMaxClearance = 100.0f;

    auto Make_FieldParams(
        const TArray<FCk_GroundNav_MarkupRecord>& InMarkups) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kFieldTileSize);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{2, 2};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Make_Profile();
        Params._MarkupRecords = InMarkups;
        Params._MaxClearanceUu = kFieldMaxClearance;

        return Params;
    }

    auto Bake_Field(
        const TArray<FCk_GroundNav_MarkupRecord>& InMarkups,
        const FCk_GroundNav_Epoch&                InEpoch,
        FCk_GroundNav_Field&                      OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
            TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}}};

        return DoBake_Field(Backend, Make_FieldParams(InMarkups), InEpoch, OutField).Get_IsCompleted();
    }

    // ---- Exact comparison ---------------------------------------------------------------------------------
    //
    // Written out member by member rather than memcmp'd: these structures carry doubles beside int32s,
    // so they have padding a byte compare would read, and padding is not a value anything set.

    enum class EPolicyComparison
    {
        // Everything, the cost labelling included.
        Include,

        // Everything a cost-only derive is forbidden to touch. What is left out is exactly what such a
        // derive is allowed to change, so a derive that moved anything else fails this.
        Ignore
    };

    template <typename T, typename T_Predicate>
    auto Get_ArraysEqual(
        const TArray<T>& InLhs,
        const TArray<T>& InRhs,
        T_Predicate      InPredicate) -> bool
    {
        if (InLhs.Num() != InRhs.Num())
        { return false; }

        for (auto Index = 0; Index < InLhs.Num(); ++Index)
        {
            if (NOT InPredicate(InLhs[Index], InRhs[Index]))
            { return false; }
        }

        return true;
    }

    template <typename T>
    auto Get_ValueArraysEqual(
        const TArray<T>& InLhs,
        const TArray<T>& InRhs) -> bool
    {
        return Get_ArraysEqual(InLhs, InRhs, [](const T& InA, const T& InB) -> bool { return InA == InB; });
    }

    auto Get_NestedIndexArraysEqual(
        const TArray<TArray<int32>>& InLhs,
        const TArray<TArray<int32>>& InRhs) -> bool
    {
        return Get_ArraysEqual(InLhs, InRhs,
            [](const TArray<int32>& InA, const TArray<int32>& InB) -> bool
            {
                return Get_ValueArraysEqual(InA, InB);
            });
    }

    auto Get_PlatesEqual(
        const FCk_GroundNav_Plate& InLhs,
        const FCk_GroundNav_Plate& InRhs,
        EPolicyComparison          InPolicy) -> bool
    {
        const auto ShapeMatches =
            InLhs._LayerIndex == InRhs._LayerIndex &&
            InLhs._MinX == InRhs._MinX && InLhs._MinY == InRhs._MinY &&
            InLhs._MaxX == InRhs._MaxX && InLhs._MaxY == InRhs._MaxY &&
            InLhs._MaxPlaneResidualUu == InRhs._MaxPlaneResidualUu &&
            InLhs._HeightRangeUu == InRhs._HeightRangeUu &&
            InLhs._MinClearanceUu == InRhs._MinClearanceUu;

        if (InPolicy == EPolicyComparison::Ignore)
        { return ShapeMatches; }

        return ShapeMatches &&
            InLhs._AreaPolicyIndex == InRhs._AreaPolicyIndex &&
            InLhs._CostMultiplier == InRhs._CostMultiplier;
    }

    auto Get_PortalsEqual(
        const FCk_GroundNav_Portal& InLhs,
        const FCk_GroundNav_Portal& InRhs) -> bool
    {
        return InLhs._PlateA == InRhs._PlateA && InLhs._PlateB == InRhs._PlateB &&
               InLhs._Direction == InRhs._Direction &&
               InLhs._FromMin == InRhs._FromMin && InLhs._FromMax == InRhs._FromMax &&
               InLhs._MinEndZUu == InRhs._MinEndZUu && InLhs._MaxEndZUu == InRhs._MaxEndZUu &&
               InLhs._TraversalClearanceUu == InRhs._TraversalClearanceUu;
    }

    auto Get_SegmentsEqual(
        const FCk_GroundNav_BoundarySegment& InLhs,
        const FCk_GroundNav_BoundarySegment& InRhs) -> bool
    {
        return InLhs._PlateIndex == InRhs._PlateIndex && InLhs._LayerIndex == InRhs._LayerIndex &&
               InLhs._Side == InRhs._Side &&
               InLhs._FromCell == InRhs._FromCell && InLhs._ToCell == InRhs._ToCell &&
               InLhs._Start == InRhs._Start && InLhs._End == InRhs._End &&
               InLhs._InwardNormalXY == InRhs._InwardNormalXY;
    }

    auto Get_StubsEqual(
        const FCk_GroundNav_SeamStub& InLhs,
        const FCk_GroundNav_SeamStub& InRhs) -> bool
    {
        return InLhs._Direction == InRhs._Direction && InLhs._AlongIndex == InRhs._AlongIndex &&
               InLhs._PlateIndex == InRhs._PlateIndex &&
               InLhs._NearSurfaceZUu == InRhs._NearSurfaceZUu &&
               InLhs._FarSurfaceZUu == InRhs._FarSurfaceZUu &&
               InLhs._ClearanceUu == InRhs._ClearanceUu;
    }

    auto Get_SeamPortalsEqual(
        const FCk_GroundNav_SeamPortal& InLhs,
        const FCk_GroundNav_SeamPortal& InRhs) -> bool
    {
        return InLhs._TileIndexA == InRhs._TileIndexA && InLhs._TileIndexB == InRhs._TileIndexB &&
               InLhs._PlateA == InRhs._PlateA && InLhs._PlateB == InRhs._PlateB &&
               InLhs._Direction == InRhs._Direction &&
               InLhs._AlongMin == InRhs._AlongMin && InLhs._AlongMax == InRhs._AlongMax &&
               InLhs._MinEndZUu == InRhs._MinEndZUu && InLhs._MaxEndZUu == InRhs._MaxEndZUu &&
               InLhs._TraversalClearanceUu == InRhs._TraversalClearanceUu;
    }

    // Epochs are deliberately excluded: they are the one thing a rebuild and a derive are SUPPOSED to
    // move, and every caller here bakes its comparands under the same epoch or asserts on them directly.
    auto Get_TilesEqual(
        const FCk_GroundNav_Tile& InLhs,
        const FCk_GroundNav_Tile& InRhs,
        EPolicyComparison         InPolicy) -> bool
    {
        const auto HeaderMatches =
            InLhs._Coord == InRhs._Coord &&
            InLhs._Status == InRhs._Status &&
            InLhs._Origin == InRhs._Origin &&
            InLhs._CellSizeUu == InRhs._CellSizeUu &&
            InLhs._MaxClearanceUu == InRhs._MaxClearanceUu &&
            InLhs._SizeX == InRhs._SizeX && InLhs._SizeY == InRhs._SizeY &&
            InLhs._LayerCount == InRhs._LayerCount &&
            InLhs._BakeStats._SourceTriangleCount == InRhs._BakeStats._SourceTriangleCount &&
            InLhs._BakeStats._RasterizedSpanCount == InRhs._BakeStats._RasterizedSpanCount &&
            InLhs._BakeStats._RejectedCellCount == InRhs._BakeStats._RejectedCellCount;

        if (NOT HeaderMatches)
        { return false; }

        const auto CellsMatch =
            Get_ValueArraysEqual(InLhs._SurfaceZ, InRhs._SurfaceZ) &&
            Get_ValueArraysEqual(InLhs._Clearance._Cells, InRhs._Clearance._Cells) &&
            Get_ValueArraysEqual(InLhs._Plates._CellToPlate, InRhs._Plates._CellToPlate);

        if (NOT CellsMatch)
        { return false; }

        const auto PlatesMatch = Get_ArraysEqual(InLhs._Plates._Plates, InRhs._Plates._Plates,
            [&](const FCk_GroundNav_Plate& InA, const FCk_GroundNav_Plate& InB) -> bool
            {
                return Get_PlatesEqual(InA, InB, InPolicy);
            });

        if (NOT PlatesMatch)
        { return false; }

        if (InPolicy == EPolicyComparison::Include &&
            NOT Get_ValueArraysEqual(InLhs._Plates._AreaPolicies, InRhs._Plates._AreaPolicies))
        { return false; }

        return Get_ArraysEqual(InLhs._Portals._Portals, InRhs._Portals._Portals, &Get_PortalsEqual) &&
               Get_NestedIndexArraysEqual(InLhs._Portals._PlateToPortals, InRhs._Portals._PlateToPortals) &&
               Get_ArraysEqual(InLhs._Boundary._Segments, InRhs._Boundary._Segments, &Get_SegmentsEqual) &&
               Get_ArraysEqual(InLhs._Boundary._EdgeCandidates, InRhs._Boundary._EdgeCandidates, &Get_SegmentsEqual) &&
               Get_NestedIndexArraysEqual(InLhs._Boundary._Buckets, InRhs._Boundary._Buckets) &&
               Get_ArraysEqual(InLhs._SeamStubs, InRhs._SeamStubs, &Get_StubsEqual);
    }

    auto Get_FieldsEqual(
        const FCk_GroundNav_Field& InLhs,
        const FCk_GroundNav_Field& InRhs,
        EPolicyComparison          InPolicy) -> bool
    {
        const auto TilesMatch = Get_ArraysEqual(InLhs._Tiles, InRhs._Tiles,
            [&](const FCk_GroundNav_Tile& InA, const FCk_GroundNav_Tile& InB) -> bool
            {
                return Get_TilesEqual(InA, InB, InPolicy);
            });

        return TilesMatch &&
               InLhs._UnmatchedSeamStubCount == InRhs._UnmatchedSeamStubCount &&
               Get_ArraysEqual(InLhs._SeamPortals, InRhs._SeamPortals, &Get_SeamPortalsEqual) &&
               Get_ValueArraysEqual(InLhs._TilePlateOffsets, InRhs._TilePlateOffsets) &&
               Get_ValueArraysEqual(InLhs._ReachabilityLabels, InRhs._ReachabilityLabels) &&
               Get_ValueArraysEqual(InLhs._ComponentIsOpen, InRhs._ComponentIsOpen);
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_ImpassableBoxMakesExactlyTheCoveredCellsImpassable,
    "CkTests.UnitTests.CkGroundNav.Bake.Markup_ImpassableBoxMakesExactlyTheCoveredCellsImpassable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_ImpassableBoxMakesExactlyTheCoveredCellsImpassable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    // Half extents chosen so the volume's footprint falls strictly INSIDE cell 10 and cell 13 on both
    // axes: [262.5, 337.5] touches neither the line at 250 nor the line at 350, so the closed-square
    // rule has nothing to arbitrate and the expected rectangle is the only one it can produce.
    constexpr auto kCoveredMin = 10;
    constexpr auto kCoveredMax = 13;

    const auto Markups = TArray<FCk_GroundNav_MarkupRecord>{
        Make_Markup(1, FVector{300.0, 300.0, 10.0}, FVector{37.5, 37.5, 50.0},
            ECk_GroundNav_MarkupKind::Walkability)};

    const auto Tunables = FCk_GroundNav_MergeTunables{};

    const auto Plain = Bake_Flat({});
    const auto Marked = Bake_Flat(Markups);

    if (NOT TestTrue(TEXT("both bakes complete"), Plain._Completed && Marked._Completed))
    { return false; }

    auto PlainPlates = FCk_GroundNav_PlateField{};
    auto MarkedPlates = FCk_GroundNav_PlateField{};

    DoDecompose_Plates(Plain._Spans, Plain._Layers, Tunables, PlainPlates);
    DoDecompose_Plates(Marked._Spans, Marked._Layers, Tunables, MarkedPlates);

    TestEqual(TEXT("the unmarked flat plane is exactly one plate"), PlainPlates._Plates.Num(), 1);

    auto InsideKept = 0;
    auto OutsideLost = 0;

    for (auto Y = 0; Y < kFlatCells; ++Y)
    {
        for (auto X = 0; X < kFlatCells; ++X)
        {
            const auto IsInside =
                X >= kCoveredMin && X <= kCoveredMax && Y >= kCoveredMin && Y <= kCoveredMax;

            const auto MarkedIndex = MarkedPlates.Get_PlateIndexAt(X, Y, 0);
            const auto PlainIndex = PlainPlates.Get_PlateIndexAt(X, Y, 0);

            if (IsInside && MarkedIndex != FCk_GroundNav_Plate::kNoPlate)
            { ++InsideKept; }

            if (NOT IsInside && (MarkedIndex == FCk_GroundNav_Plate::kNoPlate) !=
                                (PlainIndex == FCk_GroundNav_Plate::kNoPlate))
            { ++OutsideLost; }
        }
    }

    TestEqual(TEXT("every cell the volume covers has no plate"), InsideKept, 0);
    TestEqual(TEXT("and no cell outside it changed verdict"), OutsideLost, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_DisablingAMarkupRestoresTheFieldByteIdentically,
    "CkTests.UnitTests.CkGroundNav.Bake.Markup_DisablingAMarkupRestoresTheFieldByteIdentically",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_DisablingAMarkupRestoresTheFieldByteIdentically::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    // Straddling the middle of a 2x2 field, so the volume reaches every tile and its seams.
    auto Enabled = TArray<FCk_GroundNav_MarkupRecord>{
        Make_Markup(1, FVector{400.0, 400.0, 0.0}, FVector{100.0, 100.0, 50.0},
            ECk_GroundNav_MarkupKind::Walkability)};

    auto Disabled = Enabled;
    Disabled[0].Set_Enable(ECk_EnableDisable::Disable);

    // One epoch for all three, so nothing in the comparison depends on the counter.
    const auto Epoch = FCk_GroundNav_Epoch{1};

    auto Without = FCk_GroundNav_Field{};
    auto With = FCk_GroundNav_Field{};
    auto WithDisabled = FCk_GroundNav_Field{};

    const auto AllBaked =
        Bake_Field({}, Epoch, Without) &&
        Bake_Field(Enabled, Epoch, With) &&
        Bake_Field(Disabled, Epoch, WithDisabled);

    if (NOT TestTrue(TEXT("all three fields bake"), AllBaked))
    { return false; }

    TestFalse(TEXT("the enabled volume does change the field"),
        Get_FieldsEqual(Without, With, EPolicyComparison::Include));

    TestTrue(TEXT("and disabling it restores the field exactly, with no tolerance"),
        Get_FieldsEqual(Without, WithDisabled, EPolicyComparison::Include));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_MarkupAtATileSeamAgreesOnBothSides,
    "CkTests.UnitTests.CkGroundNav.Bake.Markup_MarkupAtATileSeamAgreesOnBothSides",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_MarkupAtATileSeamAgreesOnBothSides::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    // The seam sits at x = 1400: the left tile owns [1000, 1400] and the right owns [1400, 1800]. The
    // volume covers [1300, 1500], so each tile decides half of it from its own halo. A wide tile over
    // the same ground is the reference the pair must agree with, cell for cell.
    const auto Markups = TArray<FCk_GroundNav_MarkupRecord>{
        Make_Markup(1, FVector{1400.0, 1200.0, 0.0}, FVector{100.0, 100.0, 50.0},
            ECk_GroundNav_MarkupKind::Walkability)};

    const auto Geometry = Make_WideGround();

    auto WideParams = Make_TileParams(800.0f, FCk_GroundNav_TileCoord{0, 0});
    WideParams._MarkupRecords = Markups;

    auto LeftParams = Make_TileParams(400.0f, FCk_GroundNav_TileCoord{0, 0});
    LeftParams._MarkupRecords = Markups;

    auto RightParams = Make_TileParams(400.0f, FCk_GroundNav_TileCoord{1, 0});
    RightParams._MarkupRecords = Markups;

    auto Wide = FCk_GroundNav_Tile{};
    auto Left = FCk_GroundNav_Tile{};
    auto Right = FCk_GroundNav_Tile{};

    const auto AllBaked =
        DoBake_Tile(Geometry, WideParams, Wide).Get_IsCompleted() &&
        DoBake_Tile(Geometry, LeftParams, Left).Get_IsCompleted() &&
        DoBake_Tile(Geometry, RightParams, Right).Get_IsCompleted();

    if (NOT TestTrue(TEXT("the wide tile and the pair both bake"), AllBaked))
    { return false; }

    if (NOT TestEqual(TEXT("the pair spans exactly the wide tile"), Left._SizeX * 2, Wide._SizeX))
    { return false; }

    auto RejectedCellCount = 0;
    auto DisagreementCount = 0;

    const auto Get_HasPlate = [](const FCk_GroundNav_Tile& InTile, int32 InX, int32 InY) -> bool
    {
        return InTile._Plates.Get_PlateIndexAt(InX, InY, 0) != FCk_GroundNav_Plate::kNoPlate;
    };

    for (auto Y = 0; Y < Left._SizeY; ++Y)
    {
        for (auto X = 0; X < Left._SizeX; ++X)
        {
            if (NOT Get_HasPlate(Left, X, Y))
            { ++RejectedCellCount; }

            if (Get_HasPlate(Left, X, Y) != Get_HasPlate(Wide, X, Y))
            { ++DisagreementCount; }

            if (NOT Get_HasPlate(Right, X, Y))
            { ++RejectedCellCount; }

            if (Get_HasPlate(Right, X, Y) != Get_HasPlate(Wide, X + Left._SizeX, Y))
            { ++DisagreementCount; }
        }
    }

    TestTrue(TEXT("the volume rejects cells on both sides of the seam"), RejectedCellCount > 0);

    TestEqual(TEXT("and no cell is rejected in one tile and kept in the other"),
        DisagreementCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_OverlappingCostRecordsTakeTheMaxAndUnionTheTags,
    "CkTests.UnitTests.CkGroundNav.Bake.Markup_OverlappingCostRecordsTakeTheMaxAndUnionTheTags",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_OverlappingCostRecordsTakeTheMaxAndUnionTheTags::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    auto Wider = Make_Markup(1, FVector{1200.0, 1200.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);
    Wider.Set_AreaTag(TAG_CkTests_GroundNav_Markup_Slow);
    Wider.Set_CostMultiplier(2.0f);

    auto Tighter = Make_Markup(2, FVector{1200.0, 1200.0, 0.0}, FVector{50.0, 50.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);
    Tighter.Set_AreaTag(TAG_CkTests_GroundNav_Markup_Mud);
    Tighter.Set_CostMultiplier(3.0f);

    const auto Markups = TArray<FCk_GroundNav_MarkupRecord>{Wider, Tighter};

    auto Params = Make_TileParams(400.0f, FCk_GroundNav_TileCoord{0, 0});
    Params._MarkupRecords = Markups;

    auto Tile = FCk_GroundNav_Tile{};

    if (NOT TestTrue(TEXT("the tile bakes"),
        DoBake_Tile(Make_WideGround(), Params, Tile).Get_IsCompleted()))
    { return false; }

    // Both volumes are centred on the same point, which is cell 8 of a tile whose origin is 1000.
    const auto PlateIndex = Tile._Plates.Get_PlateIndexAt(8, 8, 0);

    if (NOT TestTrue(TEXT("the covered ground has a plate"), PlateIndex != FCk_GroundNav_Plate::kNoPlate))
    { return false; }

    const auto& Plate = Tile._Plates._Plates[PlateIndex];

    TestTrue(FString::Printf(TEXT("the plate takes the LARGEST multiplier over it (was %f)"),
        Plate._CostMultiplier), Plate._CostMultiplier == 3.0f);

    const auto& Policy = Tile._Plates.Get_AreaPolicy(Plate._AreaPolicyIndex);

    TestEqual(TEXT("and the UNION of the tags over it"), Policy.Num(), 2);
    TestTrue(TEXT("including the wider volume's tag"),
        Policy.HasTagExact(TAG_CkTests_GroundNav_Markup_Slow));
    TestTrue(TEXT("and the tighter volume's tag"),
        Policy.HasTagExact(TAG_CkTests_GroundNav_Markup_Mud));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_CostOnlyDeriveSpendsZeroProbesAndChangesOnlyPolicy,
    "CkTests.UnitTests.CkGroundNav.Bake.Markup_CostOnlyDeriveSpendsZeroProbesAndChangesOnlyPolicy",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_CostOnlyDeriveSpendsZeroProbesAndChangesOnlyPolicy::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    const auto SourceEpoch = FCk_GroundNav_Epoch{1};

    auto Source = MakeShared<FCk_GroundNav_Field>();

    if (NOT TestTrue(TEXT("the source field bakes"), Bake_Field({}, SourceEpoch, *Source)))
    { return false; }

    // What a reader holds across the derive, and a value copy of the same thing to compare it against.
    const auto Published = FCk_GroundNav_FieldPtr{Source};
    const auto Before = FCk_GroundNav_Field{*Source};

    // Wholly inside tile (0,0), which covers [0, 400] on both axes.
    auto Record = Make_Markup(1, FVector{200.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
        ECk_GroundNav_MarkupKind::Cost);
    Record.Set_AreaTag(TAG_CkTests_GroundNav_Markup_Slow);
    Record.Set_CostMultiplier(2.0f);

    const auto Markups = TArray<FCk_GroundNav_MarkupRecord>{Record};

    const auto DerivedEpoch = SourceEpoch.Get_Next();
    const auto Derived = Get_FieldWithMarkupCost(*Published, Markups, DerivedEpoch);

    if (NOT TestTrue(TEXT("the derive completes and yields a field"),
        Derived.Value.Get_IsCompleted() && Derived.Key.IsValid()))
    { return false; }

    TestEqual(TEXT("a cost-only derive spends no probes at all"), Derived.Value.Get_ProbesSpent(), 0);

    TestTrue(TEXT("the published field a reader is holding is untouched"),
        Get_FieldsEqual(Before, *Published, EPolicyComparison::Include));

    TestTrue(TEXT("and the derived field differs from it in NOTHING but policy"),
        Get_FieldsEqual(Before, *Derived.Key, EPolicyComparison::Ignore));

    TestFalse(TEXT("policy itself did change"),
        Get_FieldsEqual(Before, *Derived.Key, EPolicyComparison::Include));

    const auto& DerivedTiles = Derived.Key->_Tiles;

    if (NOT TestTrue(TEXT("the field has its four tiles"), DerivedTiles.Num() == 4))
    { return false; }

    // Every built tile is restamped; only the one whose plate labels actually MOVED takes the epoch.
    TestTrue(TEXT("the tile whose policy changed takes the new epoch"),
        DerivedTiles[0]._Epoch == DerivedEpoch);
    TestTrue(TEXT("and the field with it"), Derived.Key->_Epoch == DerivedEpoch);

    for (auto TileIndex = 1; TileIndex < DerivedTiles.Num(); ++TileIndex)
    {
        TestTrue(FString::Printf(
            TEXT("tile %d, restamped onto the same labels, keeps its epoch"), TileIndex),
            DerivedTiles[TileIndex]._Epoch == SourceEpoch);
    }

    auto PricedPlateCount = 0;

    for (const auto& Plate : DerivedTiles[0]._Plates._Plates)
    {
        if (Plate._AreaPolicyIndex == INDEX_NONE)
        { continue; }

        ++PricedPlateCount;

        TestTrue(FString::Printf(TEXT("a priced plate carries the record's multiplier (was %f)"),
            Plate._CostMultiplier), Plate._CostMultiplier == 2.0f);
        TestTrue(TEXT("and the record's tag"),
            DerivedTiles[0]._Plates.Get_AreaPolicy(Plate._AreaPolicyIndex)
                .HasTagExact(TAG_CkTests_GroundNav_Markup_Slow));
    }

    TestTrue(TEXT("the record priced at least one plate"), PricedPlateCount > 0);

    // A record DELETED from the list, not merely disabled. It names no tile any more, so a derive that
    // restamped only the tiles its listed records touch could never find the ground it priced and that
    // price would stand forever. Restamping every tile from the whole list is what makes deleting a
    // record and switching it off converge on the same field.
    const auto RemovedEpoch = DerivedEpoch.Get_Next();
    const auto Removed = Get_FieldWithMarkupCost(*Derived.Key, {}, RemovedEpoch);

    if (NOT TestTrue(TEXT("the derive after the removal completes and yields a field"),
        Removed.Value.Get_IsCompleted() && Removed.Key.IsValid()))
    { return false; }

    TestEqual(TEXT("still spending no probes"), Removed.Value.Get_ProbesSpent(), 0);

    TestTrue(TEXT("removing the record restores the policy the field had before it"),
        Get_FieldsEqual(Before, *Removed.Key, EPolicyComparison::Include));

    const auto& RemovedTiles = Removed.Key->_Tiles;

    TestTrue(TEXT("and bumps exactly the tile that carried the price"),
        RemovedTiles[0]._Epoch == RemovedEpoch);
    TestTrue(TEXT("with the field following it"), Removed.Key->_Epoch == RemovedEpoch);

    for (auto TileIndex = 1; TileIndex < RemovedTiles.Num(); ++TileIndex)
    {
        TestTrue(FString::Printf(
            TEXT("tile %d, which never carried a price, keeps its epoch"), TileIndex),
            RemovedTiles[TileIndex]._Epoch == SourceEpoch);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_PlateMergeIsUnchangedWhenNoPolicyIsFed,
    "CkTests.UnitTests.CkGroundNav.Bake.Markup_PlateMergeIsUnchangedWhenNoPolicyIsFed",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_PlateMergeIsUnchangedWhenNoPolicyIsFed::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    const auto Baked = Bake_Flat({});

    if (NOT TestTrue(TEXT("the flat plane bakes"), Baked._Completed))
    { return false; }

    const auto Tunables = FCk_GroundNav_MergeTunables{};

    auto NoView = FCk_GroundNav_PlateField{};
    const auto NoViewResult = DoDecompose_Plates(Baked._Spans, Baked._Layers, Tunables, NoView);

    // With no policy key, coplanar continuous ground is one rectangle over every cell.
    TestEqual(TEXT("a 40x40 cell plane is still exactly one plate"), NoView._Plates.Num(), 1);
    TestEqual(TEXT("still covering every cell"), NoView._Plates[0].Get_CellCount(), kFlatCells * kFlatCells);

    // Feeding the criterion a key every cell shares must be indistinguishable from feeding it nothing,
    // down to the probe count — otherwise the seam would cost something merely by being connected.
    auto AllNone = TArray<int32>{};
    AllNone.Init(static_cast<int32>(INDEX_NONE), kFlatCells * kFlatCells * Baked._Layers._LayerCount);

    auto WithView = FCk_GroundNav_PlateField{};
    const auto WithViewResult = DoDecompose_Plates(Baked._Spans, Baked._Layers, Tunables, WithView, AllNone);

    TestTrue(TEXT("an all-none policy key decomposes identically"),
        Get_ArraysEqual(NoView._Plates, WithView._Plates,
            [](const FCk_GroundNav_Plate& InA, const FCk_GroundNav_Plate& InB) -> bool
            {
                return Get_PlatesEqual(InA, InB, EPolicyComparison::Include);
            }));

    TestTrue(TEXT("with the same cell-to-plate map"),
        Get_ValueArraysEqual(NoView._CellToPlate, WithView._CellToPlate));

    TestEqual(TEXT("and the same probe count"),
        WithViewResult.Get_ProbesSpent(), NoViewResult.Get_ProbesSpent());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Markup_PlateMergeSplitsOnPolicyInequality,
    "CkTests.UnitTests.CkGroundNav.Bake.Markup_PlateMergeSplitsOnPolicyInequality",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Markup_PlateMergeSplitsOnPolicyInequality::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_markup;

    const auto Baked = Bake_Flat({});

    if (NOT TestTrue(TEXT("the flat plane bakes"), Baked._Completed))
    { return false; }

    // Ground that is coplanar and continuous throughout: the first two criteria admit every merge, so
    // any split the decomposition makes here is the third criterion's and nothing else's.
    constexpr auto kDivideX = kFlatCells / 2;

    auto CellPolicy = TArray<int32>{};
    CellPolicy.Reserve(kFlatCells * kFlatCells * Baked._Layers._LayerCount);

    for (auto Layer = 0; Layer < Baked._Layers._LayerCount; ++Layer)
    {
        for (auto Y = 0; Y < kFlatCells; ++Y)
        {
            for (auto X = 0; X < kFlatCells; ++X)
            { CellPolicy.Emplace(X < kDivideX ? 0 : 1); }
        }
    }

    auto Plates = FCk_GroundNav_PlateField{};

    if (NOT TestTrue(TEXT("the decomposition completes"),
        DoDecompose_Plates(Baked._Spans, Baked._Layers, FCk_GroundNav_MergeTunables{}, Plates, CellPolicy)
            .Get_IsCompleted()))
    { return false; }

    TestEqual(TEXT("two policies over one flat plane are two plates"), Plates._Plates.Num(), 2);

    TestTrue(TEXT("and neither of them crosses the divide"),
        Plates.Get_PlateIndexAt(kDivideX - 1, 0, 0) != Plates.Get_PlateIndexAt(kDivideX, 0, 0));

    auto MismatchCount = 0;

    for (auto Y = 0; Y < kFlatCells; ++Y)
    {
        for (auto X = 0; X < kFlatCells; ++X)
        {
            const auto Expected = X < kDivideX
                ? Plates.Get_PlateIndexAt(0, 0, 0)
                : Plates.Get_PlateIndexAt(kDivideX, 0, 0);

            if (Plates.Get_PlateIndexAt(X, Y, 0) != Expected)
            { ++MismatchCount; }
        }
    }

    TestEqual(TEXT("every cell belongs to the plate its policy names"), MismatchCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
