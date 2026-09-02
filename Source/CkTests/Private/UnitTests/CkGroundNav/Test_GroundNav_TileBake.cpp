// One tile of the ground field.
//
// The assertion that matters is the seam. A tiled bake that computes each tile in isolation gets a
// false pinch at every tile edge, and nothing about the result looks wrong — the field simply claims
// the world is narrower than it is, everywhere two tiles meet. So the test here is agreement: a tile
// must produce the same numbers as a bake of a far wider region covering the same ground.

#include "CkGroundNav/Bake/CkGroundNav_Clearance.h"
#include "CkGroundNav/Bake/CkGroundNav_Layers.h"
#include "CkGroundNav/Bake/CkGroundNav_Rasterize.h"
#include "CkGroundNav/Bake/CkGroundNav_Walkability.h"
#include "CkGroundNav/Field/CkGroundNav_TileBake.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_tilebake
{
    using ck::groundnav::DoBake_Tile;
    using ck::groundnav::DoCompute_Clearance;
    using ck::groundnav::DoExtract_Layers;
    using ck::groundnav::DoFilter_Walkability;
    using ck::groundnav::DoRasterizeSpans;
    using ck::groundnav::FCk_GroundNav_ClearanceField;
    using ck::groundnav::FCk_GroundNav_ConnectionField;
    using ck::groundnav::FCk_GroundNav_LayerField;
    using ck::groundnav::FCk_GroundNav_Plate;
    using ck::groundnav::FCk_GroundNav_SpanField;
    using ck::groundnav::FCk_GroundNav_Tile;
    using ck::groundnav::FCk_GroundNav_TileBakeParams;
    using ck::groundnav::Get_HaloCellCount;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 800.0f;
    constexpr auto kMaxClearance = 200.0f;

    // The tile sits well inside the ground, so every cell it publishes has real world on all sides.
    constexpr auto kFieldOriginUu = 1000.0;
    constexpr auto kGroundExtentUu = 3000.0;

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    auto Make_Config() -> FCk_GroundNav_BakeConfig
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        return Config;
    }

    auto Make_Params() -> FCk_GroundNav_TileBakeParams
    {
        auto Params = FCk_GroundNav_TileBakeParams{};

        Params._Epoch = ck::groundnav::FCk_GroundNav_Epoch{1};
        Params._FieldOriginXY = FVector2D{kFieldOriginUu, kFieldOriginUu};
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 400.0f;
        Params._Config = Make_Config();
        Params._Profile = Make_Profile();
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Ground out to 3000 uu with a 200 uu square hole punched inside the tile, so clearance varies
    // across the published cells instead of being uniformly the cap.
    constexpr auto kHoleMinUu = 1200.0;
    constexpr auto kHoleMaxUu = 1400.0;

    auto Make_GroundWithHole() -> FCk_GroundNav_GeometryBatch
    {
        auto Geometry = FCk_GroundNav_GeometryBatch{};

        Geometry.Add_Box(FBox{FVector{0.0, 0.0, -10.0}, FVector{kGroundExtentUu, kHoleMinUu, 0.0}});
        Geometry.Add_Box(FBox{
            FVector{0.0, kHoleMaxUu, -10.0}, FVector{kGroundExtentUu, kGroundExtentUu, 0.0}});
        Geometry.Add_Box(FBox{
            FVector{0.0, kHoleMinUu, -10.0}, FVector{kHoleMinUu, kHoleMaxUu, 0.0}});
        Geometry.Add_Box(FBox{
            FVector{kHoleMaxUu, kHoleMinUu, -10.0}, FVector{kGroundExtentUu, kHoleMaxUu, 0.0}});

        return Geometry;
    }

    /** Clearance over the whole ground in one bake — the answer a tile has to reproduce. */
    auto Make_WideClearance(FCk_GroundNav_ClearanceField& OutClearance) -> bool
    {
        const auto Region = FBox{
            FVector{0.0, 0.0, -50.0}, FVector{kGroundExtentUu, kGroundExtentUu, 400.0}};

        const auto Profile = Make_Profile();

        auto Spans = FCk_GroundNav_SpanField{};

        if (NOT DoRasterizeSpans(
            Make_GroundWithHole(), Region, Make_Config(), Profile, Spans).Get_IsCompleted())
        { return false; }

        auto Connections = FCk_GroundNav_ConnectionField{};

        if (NOT DoFilter_Walkability(Profile, Spans, Connections).Get_IsCompleted())
        { return false; }

        auto Layers = FCk_GroundNav_LayerField{};

        if (NOT DoExtract_Layers(Spans, Connections, Layers).Get_IsCompleted())
        { return false; }

        return DoCompute_Clearance(Layers, Connections, kCellSize, OutClearance).Get_IsCompleted();
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Tile_SeamAgreesWithAWiderBake,
    "CkTests.UnitTests.CkGroundNav.Bake.Tile_SeamAgreesWithAWiderBake",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Tile_SeamAgreesWithAWiderBake::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_tilebake;

    auto WideClearance = FCk_GroundNav_ClearanceField{};

    if (NOT TestTrue(TEXT("the wide reference bake completes"), Make_WideClearance(WideClearance)))
    { return false; }

    auto Tile = FCk_GroundNav_Tile{};

    if (NOT TestTrue(TEXT("the tile bakes"),
        DoBake_Tile(Make_GroundWithHole(), Make_Params(), Tile).Get_IsCompleted()))
    { return false; }

    TestTrue(TEXT("and publishes as built"), Tile.Get_IsBuilt());
    TestEqual(TEXT("covering exactly its own cells"), Tile._SizeX,
        static_cast<int32>(kTileSize / kCellSize));

    // Where the tile sits in the wide bake's lattice.
    const auto Offset = static_cast<int32>(kFieldOriginUu / kCellSize);

    auto Compared = 0;
    auto BelowCap = 0;

    for (auto Y = 0; Y < Tile._SizeY; ++Y)
    {
        for (auto X = 0; X < Tile._SizeX; ++X)
        {
            const auto Mine = Tile._Clearance.Get_ClearanceAt(X, Y, 0);
            const auto Theirs = FMath::Min(
                WideClearance.Get_ClearanceAt(X + Offset, Y + Offset, 0), kMaxClearance);

            if (Mine != Theirs)
            {
                AddError(FString::Printf(
                    TEXT("cell (%d,%d) reads %.4f in the tile and %.4f in the wide bake"),
                    X, Y, Mine, Theirs));
                return false;
            }

            ++Compared;

            if (Theirs < kMaxClearance)
            { ++BelowCap; }
        }
    }

    TestEqual(TEXT("every published cell was compared"), Compared, Tile._SizeX * Tile._SizeY);

    // Without this the agreement above could be a field of identical caps agreeing with itself. The
    // hole is what makes some of these cells carry a number the halo actually had to see.
    TestTrue(FString::Printf(TEXT("and the comparison is not trivially all-cap (%d below it)"), BelowCap),
        BelowCap > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Tile_PublishesNothingOutsideItself,
    "CkTests.UnitTests.CkGroundNav.Bake.Tile_PublishesNothingOutsideItself",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Tile_PublishesNothingOutsideItself::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_tilebake;

    auto Tile = FCk_GroundNav_Tile{};

    if (NOT TestTrue(TEXT("the tile bakes"),
        DoBake_Tile(Make_GroundWithHole(), Make_Params(), Tile).Get_IsCompleted()))
    { return false; }

    const auto TileCells = static_cast<int32>(kTileSize / kCellSize);

    TestEqual(TEXT("the origin is the tile corner, not the halo corner"),
        Tile._Origin.X, static_cast<double>(kFieldOriginUu));

    // A plate reaching outside would mean one plate id naming ground two tiles both claim, and the
    // two would answer differently after either was rebuilt.
    for (const auto& Plate : Tile._Plates._Plates)
    {
        const auto IsInside =
            Plate._MinX >= 0 && Plate._MinY >= 0 && Plate._MaxX < TileCells && Plate._MaxY < TileCells;

        if (NOT IsInside)
        {
            AddError(FString::Printf(TEXT("plate (%d,%d)-(%d,%d) reaches outside a %d cell tile"),
                Plate._MinX, Plate._MinY, Plate._MaxX, Plate._MaxY, TileCells));
            return false;
        }
    }

    for (const auto& Portal : Tile._Portals._Portals)
    {
        const auto IsInside =
            Portal._FromMin.X >= 0 && Portal._FromMin.Y >= 0 &&
            Portal._FromMax.X < TileCells && Portal._FromMax.Y < TileCells;

        if (NOT IsInside)
        {
            AddError(FString::Printf(TEXT("portal from (%d,%d) reaches outside a %d cell tile"),
                Portal._FromMin.X, Portal._FromMin.Y, TileCells));
            return false;
        }
    }

    // The hole must survive the crop: it is inside the tile, and a tile that quietly filled it would
    // still pass every bounds check above.
    const auto HoleCell = static_cast<int32>((kHoleMinUu + 50.0 - kFieldOriginUu) / kCellSize);

    TestEqual(TEXT("and the hole inside the tile is still a hole"),
        Tile._Plates.Get_PlateIndexAt(HoleCell, HoleCell, 0), FCk_GroundNav_Plate::kNoPlate);

    TestFalse(TEXT("with no surface published there"), Tile.Get_HasSurfaceAt(HoleCell, HoleCell, 0));

    TestTrue(TEXT("while ordinary ground in the tile does carry one"),
        Tile.Get_HasSurfaceAt(1, 1, 0));

    // Every number a tile publishes lives under the same ceiling. A portal derived from the halo's
    // unclamped transform would otherwise advertise more room than any cell either side of it admits,
    // and it is the portal a query trusts when deciding who fits through.
    for (const auto& Portal : Tile._Portals._Portals)
    {
        if (Portal._TraversalClearanceUu <= kMaxClearance)
        { continue; }

        AddError(FString::Printf(TEXT("a crossing offers %.2f uu against a %.2f uu ceiling"),
            Portal._TraversalClearanceUu, kMaxClearance));
        return false;
    }

    TestTrue(TEXT("and no cell claims more room than the ceiling"),
        Tile._Clearance.Get_MaxClearance() <= kMaxClearance);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Tile_HaloIsSizedFromTheClearanceCap,
    "CkTests.UnitTests.CkGroundNav.Bake.Tile_HaloIsSizedFromTheClearanceCap",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Tile_HaloIsSizedFromTheClearanceCap::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_tilebake;

    TestEqual(TEXT("a 200 uu cap over 25 uu cells is eight cells of halo"),
        Get_HaloCellCount(200.0f, 25.0f), 8);

    TestEqual(TEXT("and a cap that does not divide evenly rounds up rather than down"),
        Get_HaloCellCount(210.0f, 25.0f), 9);

    // Not a corner case to tolerate: no cap means no clearance worth bounding, and a halo of zero is
    // the honest consequence rather than an accident.
    TestEqual(TEXT("no cap means no halo"), Get_HaloCellCount(0.0f, 25.0f), 0);

    const auto Params = Make_Params();
    const auto Bounds = ck::groundnav::Get_TileBounds(Params);
    const auto HaloBounds = ck::groundnav::Get_TileHaloBounds(Params);

    TestEqual(TEXT("the tile covers its configured size"), Bounds.GetSize().X,
        static_cast<double>(kTileSize));

    TestEqual(TEXT("and the halo extends it by the cap on every side"),
        HaloBounds.GetSize().X, static_cast<double>(kTileSize + (2.0f * kMaxClearance)));

    TestEqual(TEXT("without changing the vertical slab"), HaloBounds.GetSize().Z, Bounds.GetSize().Z);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Tile_FailedBakeIsAStatusNotAnEmptyTile,
    "CkTests.UnitTests.CkGroundNav.Bake.Tile_FailedBakeIsAStatusNotAnEmptyTile",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Tile_FailedBakeIsAStatusNotAnEmptyTile::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_tilebake;

    auto Params = Make_Params();
    Params._MaxZUu = Params._MinZUu;

    auto Tile = FCk_GroundNav_Tile{};
    const auto Result = DoBake_Tile(Make_GroundWithHole(), Params, Tile);

    TestFalse(TEXT("a degenerate vertical slab does not complete"), Result.Get_IsCompleted());
    TestEqual(TEXT("it is rejected at admission"), Result.Get_Status(),
        ECk_GroundNav_BakeStatus::InvalidInput);

    // The distinction the whole status enum exists for: a caller must be able to tell this from a
    // tile that baked fine and found nothing to walk on.
    TestFalse(TEXT("and the tile does not claim to be built"), Tile.Get_IsBuilt());
    TestEqual(TEXT("it says it failed"), Tile._Status, ECk_GroundNav_BuildStatus::Failed);
    TestEqual(TEXT("carrying no cells at all"), Tile.Get_WalkableCellCount(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Tile_AZeroClearanceCapIsRejectedNotBaked,
    "CkTests.UnitTests.CkGroundNav.Bake.Tile_AZeroClearanceCapIsRejectedNotBaked",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Tile_AZeroClearanceCapIsRejectedNotBaked::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_tilebake;

    // A zero cap sizes the halo at zero cells, and a rimless tile is wrong twice over: every
    // seam stub loses the far column it would have been derived from, and every ledge at the tile
    // border is filtered against a neighbour that is not in the lattice. Neither failure is visible in
    // what the tile publishes, so the cap has to be refused at admission rather than baked.
    auto Params = Make_Params();
    Params._MaxClearanceUu = 0.0f;

    auto Tile = FCk_GroundNav_Tile{};
    const auto Result = DoBake_Tile(Make_GroundWithHole(), Params, Tile);

    TestFalse(TEXT("a zero clearance cap does not complete"), Result.Get_IsCompleted());
    TestEqual(TEXT("it is rejected at admission"), Result.Get_Status(),
        ECk_GroundNav_BakeStatus::InvalidInput);

    TestFalse(TEXT("and the tile does not claim to be built"), Tile.Get_IsBuilt());
    TestEqual(TEXT("carrying no plates"), Tile._Plates._Plates.Num(), 0);
    TestEqual(TEXT("and no crossings"), Tile._Portals._Portals.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
