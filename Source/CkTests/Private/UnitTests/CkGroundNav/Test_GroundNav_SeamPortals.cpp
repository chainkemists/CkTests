// Crossings between tiles.
//
// A tile keeps no span field and no connection field, so composing two of them is the moment the
// codebase is most tempted to grow a second definition of "these two cells are adjacent". It does not:
// each tile records what its own halo already knew about the crossings leaving it, and composition
// pairs those accounts. The tests here pin both halves — that a real crossing is found, and that
// nothing invents one where the world has none.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_seams
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::DoBake_Tile;
    using ck::groundnav::DoDerive_SeamPortals;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::FCk_GroundNav_SeamPortal;
    using ck::groundnav::FCk_GroundNav_TileCoord;
    using ck::groundnav::Get_TileHaloBounds;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;
    constexpr auto kTileCells = 16;

    auto Make_Params() -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Params = FCk_GroundNav_FieldParams{};

        // Two tiles side by side: one seam, running the length of their shared edge.
        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{2, 1};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    auto Make_ContinuousGround() -> TArray<FBox>
    {
        return TArray<FBox>{FBox{FVector{-200.0, -200.0, -10.0}, FVector{1000.0, 600.0, 0.0}}};
    }

    // The same ground with two cell columns missing either side of the seam, so the two tiles have
    // nothing to cross between.
    auto Make_GroundWithAGapAtTheSeam() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{-200.0, -200.0, -10.0}, FVector{375.0, 600.0, 0.0}},
            FBox{FVector{425.0, -200.0, -10.0}, FVector{1000.0, 600.0, 0.0}}};
    }

    // Nothing but a 100 uu bridge over the seam — four cells wide, and the only way across.
    constexpr auto kBridgeWidthUu = 100.0;
    constexpr auto kBridgeMinYUu = 150.0;

    auto Make_BridgeOverTheSeam() -> TArray<FBox>
    {
        return TArray<FBox>{FBox{
            FVector{200.0, kBridgeMinYUu, -10.0},
            FVector{600.0, kBridgeMinYUu + kBridgeWidthUu, 0.0}}};
    }

    auto Bake(const TArray<FBox>& InBoxes, FCk_GroundNav_Field& OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{InBoxes};

        return DoBake_Field(Backend, Make_Params(), FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    auto Get_SeamCellCount(const FCk_GroundNav_Field& InField) -> int32
    {
        auto Count = 0;

        for (const auto& Portal : InField._SeamPortals)
        { Count += Portal.Get_CellCount(); }

        return Count;
    }

    auto Get_SeamPortalsMatch(const FCk_GroundNav_Field& InLeft, const FCk_GroundNav_Field& InRight) -> bool
    {
        if (InLeft._SeamPortals.Num() != InRight._SeamPortals.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft._SeamPortals.Num(); ++Index)
        {
            const auto& A = InLeft._SeamPortals[Index];
            const auto& B = InRight._SeamPortals[Index];

            if (A._TileIndexA == B._TileIndexA && A._TileIndexB == B._TileIndexB &&
                A._PlateA == B._PlateA && A._PlateB == B._PlateB &&
                A._Direction == B._Direction &&
                A._AlongMin == B._AlongMin && A._AlongMax == B._AlongMax &&
                A._MinEndZUu == B._MinEndZUu && A._MaxEndZUu == B._MaxEndZUu &&
                A._TraversalClearanceUu == B._TraversalClearanceUu)
            { continue; }

            return false;
        }

        return true;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Seam_ContinuousGroundCrossesTheBoundary,
    "CkTests.UnitTests.CkGroundNav.Bake.Seam_ContinuousGroundCrossesTheBoundary",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Seam_ContinuousGroundCrossesTheBoundary::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_seams;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes"), Bake(Make_ContinuousGround(), Field)))
    { return false; }

    if (NOT TestEqual(TEXT("both tiles built"), Field.Get_BuiltTileCount(), 2))
    { return false; }

    // Unbroken floor over one plate each side: one crossing, spanning every cell of the shared edge.
    TestEqual(TEXT("unbroken ground makes one crossing"), Field.Get_SeamPortalCount(), 1);

    if (NOT TestEqual(TEXT("running the whole length of the seam"), Get_SeamCellCount(Field), kTileCells))
    { return false; }

    const auto& Portal = Field._SeamPortals[0];

    TestEqual(TEXT("from the first tile"), Portal._TileIndexA, 0);
    TestEqual(TEXT("to the second"), Portal._TileIndexB, 1);
    TestEqual(TEXT("stepping along X"), Portal._Direction, 0);

    TestTrue(TEXT("and it offers room to cross"), Portal._TraversalClearanceUu > 0.0f);
    TestTrue(TEXT("within the ceiling the tiles baked under"),
        Portal._TraversalClearanceUu <= kMaxClearance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Seam_AGapAtTheBoundaryProducesNone,
    "CkTests.UnitTests.CkGroundNav.Bake.Seam_AGapAtTheBoundaryProducesNone",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Seam_AGapAtTheBoundaryProducesNone::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_seams;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes"), Bake(Make_GroundWithAGapAtTheSeam(), Field)))
    { return false; }

    // Both tiles have plenty of ground — just none of it at the seam. A composition that reasoned from
    // tile adjacency rather than from what the tiles observed would happily join them here.
    TestEqual(TEXT("both tiles still built"), Field.Get_BuiltTileCount(), 2);

    TestTrue(TEXT("and both have ground on them"),
        Field._Tiles[0].Get_WalkableCellCount() > 0 && Field._Tiles[1].Get_WalkableCellCount() > 0);

    TestEqual(TEXT("but nothing crosses between them"), Field.Get_SeamPortalCount(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Seam_ABridgeMatchesItsOwnWidth,
    "CkTests.UnitTests.CkGroundNav.Bake.Seam_ABridgeMatchesItsOwnWidth",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Seam_ABridgeMatchesItsOwnWidth::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_seams;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes"), Bake(Make_BridgeOverTheSeam(), Field)))
    { return false; }

    if (NOT TestEqual(TEXT("the bridge makes one crossing"), Field.Get_SeamPortalCount(), 1))
    { return false; }

    // The interval is the bridge, not the seam. A crossing reported wider than the ground carrying it
    // is a route through thin air, and the funnel that later walks it has no way to notice.
    TestEqual(TEXT("as wide as the bridge and no wider"), Get_SeamCellCount(Field),
        static_cast<int32>(kBridgeWidthUu / kCellSize));

    const auto& Portal = Field._SeamPortals[0];

    TestEqual(TEXT("starting where the bridge starts"), Portal._AlongMin,
        static_cast<int32>(kBridgeMinYUu / kCellSize));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Seam_AnUnbuiltNeighbourIsNotABlockedOne,
    "CkTests.UnitTests.CkGroundNav.Bake.Seam_AnUnbuiltNeighbourIsNotABlockedOne",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Seam_AnUnbuiltNeighbourIsNotABlockedOne::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_seams;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes"), Bake(Make_ContinuousGround(), Field)))
    { return false; }

    if (NOT TestTrue(TEXT("the seam is there to begin with"), Field.Get_SeamPortalCount() > 0))
    { return false; }

    Field._Tiles[1]._Status = ECk_GroundNav_BuildStatus::Unbuilt;

    DoDerive_SeamPortals(Field);

    // No portal, which is not the same as a wall: the boundary is now a place nothing is known about,
    // and a path across it must fail as unbuilt rather than be told it is impassable.
    TestEqual(TEXT("an unbuilt neighbour carries no crossing"), Field.Get_SeamPortalCount(), 0);

    // The stubs survive, so the crossing comes back when the tile does — without re-baking the one
    // that never went away.
    TestTrue(TEXT("while the built tile still holds what it observed"),
        Field._Tiles[0]._SeamStubs.Num() > 0);

    Field._Tiles[1]._Status = ECk_GroundNav_BuildStatus::Built;

    DoDerive_SeamPortals(Field);

    TestTrue(TEXT("and the crossing returns when the neighbour does"), Field.Get_SeamPortalCount() > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Seam_RebuildingOneTileReproducesThemExactly,
    "CkTests.UnitTests.CkGroundNav.Bake.Seam_RebuildingOneTileReproducesThemExactly",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Seam_RebuildingOneTileReproducesThemExactly::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_seams;

    auto Reference = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference field bakes"), Bake(Make_BridgeOverTheSeam(), Reference)))
    { return false; }

    if (NOT TestTrue(TEXT("and has a crossing to compare"), Reference.Get_SeamPortalCount() > 0))
    { return false; }

    auto Repeat = FCk_GroundNav_Field{};
    Bake(Make_BridgeOverTheSeam(), Repeat);

    TestTrue(TEXT("a second whole bake reproduces the crossings"),
        Get_SeamPortalsMatch(Reference, Repeat));

    // The case that matters for repair and streaming: one tile is thrown away and rebuilt while its
    // neighbour is untouched. A crossing that came back different would repoint a route across a seam
    // nothing about the world had changed at.
    auto Rebuilt = Reference;

    const auto Params = Make_Params();
    const auto TileParams = Params.Get_TileBakeParams(FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_Epoch{2});

    const auto Backend = FCk_GroundNav_GeometryBackend_Stub{Make_BridgeOverTheSeam()};

    auto Geometry = FCk_GroundNav_GeometryBatch{};
    Backend.Get_TrianglesInBounds(Get_TileHaloBounds(TileParams), Geometry);

    if (NOT TestTrue(TEXT("the single tile rebuilds"),
        DoBake_Tile(Geometry, TileParams, Rebuilt._Tiles[1]).Get_IsCompleted()))
    { return false; }

    DoDerive_SeamPortals(Rebuilt);

    TestTrue(TEXT("and rebuilding one tile alone reproduces them too"),
        Get_SeamPortalsMatch(Reference, Rebuilt));

    // The rebuild did happen — the tile carries the newer epoch, so the field fingerprint moved even
    // though every crossing came back identical.
    TestTrue(TEXT("with the rebuilt tile on a newer epoch"),
        Rebuilt._Tiles[1]._Epoch.Get_IsNewerThan(Reference._Tiles[1]._Epoch));

    TestTrue(TEXT("and the field fingerprint moved with it"),
        Rebuilt.Get_AggregatedTileEpochSum() > Reference.Get_AggregatedTileEpochSum());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
