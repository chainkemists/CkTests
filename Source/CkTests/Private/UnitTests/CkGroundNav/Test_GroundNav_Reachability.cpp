// Reachability components, and the asymmetry in what they are allowed to claim.
//
// The labels are computed over the crossings that exist, not over the crossings a given body fits
// through. That makes the guarantee one-directional, and the last test here exists to pin the wrong
// half of it: two plates carrying the same label with a doorway between them that no fat agent can
// use. A component label is a way to refuse work early, never a licence to skip the clearance check.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_reachability
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    auto Make_Params(const FIntPoint& InDivisions) -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = InDivisions;
        Params._MinZUu = -50.0f;
        Params._MaxZUu = 300.0f;
        Params._Config = Config;
        Params._Profile = Profile;
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Two islands of ground in one tile, with nothing between them.
    auto Make_TwoIslands() -> TArray<FBox>
    {
        return TArray<FBox>{
            FBox{FVector{50.0, 50.0, -10.0}, FVector{150.0, 150.0, 0.0}},
            FBox{FVector{250.0, 50.0, -10.0}, FVector{350.0, 150.0, 0.0}}};
    }

    // The same two islands with a door between them: a 50 uu neck, two cells wide.
    constexpr auto kDoorWidthUu = 50.0;

    auto Make_TwoIslandsWithADoor() -> TArray<FBox>
    {
        auto Boxes = Make_TwoIslands();
        Boxes.Emplace(FBox{FVector{150.0, 75.0, -10.0}, FVector{250.0, 75.0 + kDoorWidthUu, 0.0}});

        return Boxes;
    }

    // Ground crossing a seam so the two TILES of a 2x1 field belong to one component.
    auto Make_ContinuousGround() -> TArray<FBox>
    {
        return TArray<FBox>{FBox{FVector{-200.0, -200.0, -10.0}, FVector{1000.0, 600.0, 0.0}}};
    }

    auto Bake(
        const TArray<FBox>&              InBoxes,
        const FCk_GroundNav_FieldParams& InParams,
        FCk_GroundNav_Field&             OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{InBoxes};

        return DoBake_Field(Backend, InParams, FCk_GroundNav_Epoch{1}, OutField).Get_IsCompleted();
    }

    /** The plate under a world position, as a (tile, plate) pair; plate is kNoPlate when there is none. */
    auto Get_PlateAt(const FCk_GroundNav_Field& InField, double InX, double InY, int32& OutTileIndex) -> int32
    {
        const auto Position = FVector{InX, InY, 0.0};
        const auto Coord = InField._Params.Get_TileCoordAt(Position);

        OutTileIndex = ck::groundnav::Get_TileIndex(InField._Params._Divisions, Coord);

        const auto* Tile = InField.Get_Tile(Coord);

        if (Tile == nullptr)
        { return ck::groundnav::FCk_GroundNav_Plate::kNoPlate; }

        const auto CellX = FMath::FloorToInt32((InX - Tile->_Origin.X) / Tile->_CellSizeUu);
        const auto CellY = FMath::FloorToInt32((InY - Tile->_Origin.Y) / Tile->_CellSizeUu);

        return Tile->_Plates.Get_PlateIndexAt(CellX, CellY, 0);
    }

    // Ground continuous across all three tiles of a 3x1 field, so every plate is one component right
    // up until a tile stops being built.
    auto Make_GroundAcrossThreeTiles() -> TArray<FBox>
    {
        return TArray<FBox>{FBox{FVector{-200.0, -200.0, -10.0}, FVector{1400.0, 600.0, 0.0}}};
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_SeparateGroundIsSeparateComponents,
    "CkTests.UnitTests.CkGroundNav.Bake.Reachability_SeparateGroundIsSeparateComponents",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_SeparateGroundIsSeparateComponents::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two islands bake"), Bake(Make_TwoIslands(), Make_Params(FIntPoint{1, 1}), Field)))
    { return false; }

    auto LeftTile = int32{INDEX_NONE};
    auto RightTile = int32{INDEX_NONE};

    const auto LeftPlate = Get_PlateAt(Field, 100.0, 100.0, LeftTile);
    const auto RightPlate = Get_PlateAt(Field, 300.0, 100.0, RightTile);

    if (NOT TestTrue(TEXT("both islands have ground on them"),
        LeftPlate != ck::groundnav::FCk_GroundNav_Plate::kNoPlate &&
        RightPlate != ck::groundnav::FCk_GroundNav_Plate::kNoPlate))
    { return false; }

    TestTrue(TEXT("islands with nothing between them are provably out of reach of each other"),
        Field.Get_AreProvablyDisconnected(LeftTile, LeftPlate, RightTile, RightPlate));

    TestTrue(TEXT("so the field has more than one component"),
        Field.Get_ReachabilityComponentCount() > 1);

    // Trivially true of a plate against itself, and worth stating: an answer of "disconnected" here
    // would mean the labelling had lost a plate rather than found a gap.
    TestFalse(TEXT("and a plate is never out of its own reach"),
        Field.Get_AreProvablyDisconnected(LeftTile, LeftPlate, LeftTile, LeftPlate));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_ADoorMergesTwoComponents,
    "CkTests.UnitTests.CkGroundNav.Bake.Reachability_ADoorMergesTwoComponents",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_ADoorMergesTwoComponents::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_reachability;

    const auto Params = Make_Params(FIntPoint{1, 1});

    auto Before = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the closed world bakes"), Bake(Make_TwoIslands(), Params, Before)))
    { return false; }

    auto After = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the opened world bakes"), Bake(Make_TwoIslandsWithADoor(), Params, After)))
    { return false; }

    auto BeforeLeftTile = int32{INDEX_NONE};
    auto BeforeRightTile = int32{INDEX_NONE};
    auto AfterLeftTile = int32{INDEX_NONE};
    auto AfterRightTile = int32{INDEX_NONE};

    const auto BeforeLeft = Get_PlateAt(Before, 100.0, 100.0, BeforeLeftTile);
    const auto BeforeRight = Get_PlateAt(Before, 300.0, 100.0, BeforeRightTile);
    const auto AfterLeft = Get_PlateAt(After, 100.0, 100.0, AfterLeftTile);
    const auto AfterRight = Get_PlateAt(After, 300.0, 100.0, AfterRightTile);

    if (NOT TestTrue(TEXT("both worlds have ground at both ends"),
        BeforeLeft != ck::groundnav::FCk_GroundNav_Plate::kNoPlate &&
        BeforeRight != ck::groundnav::FCk_GroundNav_Plate::kNoPlate &&
        AfterLeft != ck::groundnav::FCk_GroundNav_Plate::kNoPlate &&
        AfterRight != ck::groundnav::FCk_GroundNav_Plate::kNoPlate))
    { return false; }

    TestTrue(TEXT("closed, the two ends are provably out of reach"),
        Before.Get_AreProvablyDisconnected(BeforeLeftTile, BeforeLeft, BeforeRightTile, BeforeRight));

    // The rebuild is what merges them. Labels are never patched across a rebuild: they are re-derived
    // from the crossings the new world has, so a door that opened is simply a different world.
    TestFalse(TEXT("opened, they are not"),
        After.Get_AreProvablyDisconnected(AfterLeftTile, AfterLeft, AfterRightTile, AfterRight));

    TestEqual(TEXT("and the opened world has one component where the closed one had two"),
        After.Get_ReachabilityComponentCount(), 1);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_CrossesTileSeamsAndIsOrderIndependent,
    "CkTests.UnitTests.CkGroundNav.Bake.Reachability_CrossesTileSeamsAndIsOrderIndependent",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_CrossesTileSeamsAndIsOrderIndependent::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_reachability;

    const auto Params = Make_Params(FIntPoint{2, 1});

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the two-tile field bakes"), Bake(Make_ContinuousGround(), Params, Field)))
    { return false; }

    if (NOT TestEqual(TEXT("both tiles built"), Field.Get_BuiltTileCount(), 2))
    { return false; }

    // Ground that runs across a seam is one component. A labelling that stopped at tile boundaries
    // would report every tile as its own island and refuse every route that left one.
    TestEqual(TEXT("ground crossing a seam is a single component"),
        Field.Get_ReachabilityComponentCount(), 1);

    auto LeftTile = int32{INDEX_NONE};
    auto RightTile = int32{INDEX_NONE};

    const auto LeftPlate = Get_PlateAt(Field, 100.0, 200.0, LeftTile);
    const auto RightPlate = Get_PlateAt(Field, 700.0, 200.0, RightTile);

    if (NOT TestTrue(TEXT("the two sample points are in different tiles"), LeftTile != RightTile))
    { return false; }

    TestFalse(TEXT("and they are not provably out of reach of each other"),
        Field.Get_AreProvablyDisconnected(LeftTile, LeftPlate, RightTile, RightPlate));

    // Re-labelling an unchanged field must land on the same numbers, or a label could not be compared
    // against one taken a moment earlier.
    const auto LabelsBefore = Field._ReachabilityLabels;

    ck::groundnav::DoLabel_Reachability(Field);

    TestTrue(TEXT("re-labelling the same field reproduces the same labels"),
        Field._ReachabilityLabels == LabelsBefore);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_SameComponentDoesNotMeanPassable,
    "CkTests.UnitTests.CkGroundNav.Bake.Reachability_SameComponentDoesNotMeanPassable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_SameComponentDoesNotMeanPassable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the world with a door bakes"),
        Bake(Make_TwoIslandsWithADoor(), Make_Params(FIntPoint{1, 1}), Field)))
    { return false; }

    auto LeftTile = int32{INDEX_NONE};
    auto RightTile = int32{INDEX_NONE};

    const auto LeftPlate = Get_PlateAt(Field, 100.0, 100.0, LeftTile);
    const auto RightPlate = Get_PlateAt(Field, 300.0, 100.0, RightTile);

    if (NOT TestTrue(TEXT("both ends have ground"),
        LeftPlate != ck::groundnav::FCk_GroundNav_Plate::kNoPlate &&
        RightPlate != ck::groundnav::FCk_GroundNav_Plate::kNoPlate))
    { return false; }

    TestFalse(TEXT("the two ends share a component"),
        Field.Get_AreProvablyDisconnected(LeftTile, LeftPlate, RightTile, RightPlate));

    // And yet: a body wider than the door cannot get from one to the other. This is the whole reason
    // there is no Get_AreReachable to call — the label answers a question about the world, not about
    // the agent, and only the crossing clearances can answer the second.
    constexpr auto kFatAgentRadiusUu = 60.0f;

    const auto& Tile = Field._Tiles[LeftTile];

    auto WidestCrossing = 0.0f;

    for (const auto& Portal : Tile._Portals._Portals)
    { WidestCrossing = FMath::Max(WidestCrossing, Portal._TraversalClearanceUu); }

    if (NOT TestTrue(TEXT("the world has crossings at all"), Tile._Portals.Get_PortalCount() > 0))
    { return false; }

    TestTrue(FString::Printf(
        TEXT("but no crossing admits a %.0f uu radius (widest offers %.2f)"),
        kFatAgentRadiusUu, WidestCrossing),
        WidestCrossing < kFatAgentRadiusUu);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_AnUnbuiltTileRefusesToProveDisconnection,
    "CkTests.UnitTests.CkGroundNav.Bake.Reachability_AnUnbuiltTileRefusesToProveDisconnection",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_AnUnbuiltTileRefusesToProveDisconnection::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the three-tile field bakes"),
        Bake(Make_GroundAcrossThreeTiles(), Make_Params(FIntPoint{3, 1}), Field)))
    { return false; }

    auto LeftTile = int32{INDEX_NONE};
    auto RightTile = int32{INDEX_NONE};

    const auto LeftPlate = Get_PlateAt(Field, 200.0, 200.0, LeftTile);
    const auto RightPlate = Get_PlateAt(Field, 1000.0, 200.0, RightTile);

    if (NOT TestTrue(TEXT("both ends of the field have ground"),
        LeftPlate != ck::groundnav::FCk_GroundNav_Plate::kNoPlate &&
        RightPlate != ck::groundnav::FCk_GroundNav_Plate::kNoPlate))
    { return false; }

    TestFalse(TEXT("with every tile built, the two ends are not disconnected"),
        Field.Get_AreProvablyDisconnected(LeftTile, LeftPlate, RightTile, RightPlate));

    // Take the middle tile away. The crossings that joined the ends go with it, so the labels really
    // do separate — asserted below, so what follows cannot pass against a field where nothing moved.
    Field._Tiles[1]._Status = ECk_GroundNav_BuildStatus::Unbuilt;

    ck::groundnav::DoDerive_SeamPortals(Field);
    ck::groundnav::DoLabel_Reachability(Field);

    TestNotEqual(TEXT("the two ends now carry different component labels"),
        Field.Get_ReachabilityLabel(LeftTile, LeftPlate),
        Field.Get_ReachabilityLabel(RightTile, RightPlate));

    // And yet the answer must still be "not proven". The labels differ because the ground between
    // them was never baked, not because the world separates them — and answering true here would
    // refuse work on a hole in the data, which is the one thing this contract forbids.
    TestFalse(TEXT("but the separation is NOT proven, because unbuilt ground caused it"),
        Field.Get_AreProvablyDisconnected(LeftTile, LeftPlate, RightTile, RightPlate));

    // The distinction has to survive the tile coming back, or it would only ever be a one-way door.
    Field._Tiles[1]._Status = ECk_GroundNav_BuildStatus::Built;

    ck::groundnav::DoDerive_SeamPortals(Field);
    ck::groundnav::DoLabel_Reachability(Field);

    TestFalse(TEXT("and once the tile is built again the ends are connected as before"),
        Field.Get_AreProvablyDisconnected(LeftTile, LeftPlate, RightTile, RightPlate));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Reachability_AnOutOfRangeTileIsRefusedNotRead,
    "CkTests.UnitTests.CkGroundNav.Bake.Reachability_AnOutOfRangeTileIsRefusedNotRead",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Reachability_AnOutOfRangeTileIsRefusedNotRead::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_reachability;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the field bakes"),
        Bake(Make_ContinuousGround(), Make_Params(FIntPoint{2, 1}), Field)))
    { return false; }

    // _TilePlateOffsets carries TileCount + 1 entries so that every tile's range is one subtraction
    // away. The cost is that a bounds check on the tile index ALONE admits TileCount itself, and the
    // offset lookup then reads one past the end — a real out-of-bounds read behind a valid-looking
    // index. One past the last tile has to be refused, not read.
    TestEqual(TEXT("one past the last tile is refused"),
        Field.Get_ReachabilityLabel(Field.Get_TileCount(), 0), int32{INDEX_NONE});

    TestEqual(TEXT("and so is a negative tile"),
        Field.Get_ReachabilityLabel(-1, 0), int32{INDEX_NONE});

    TestEqual(TEXT("and a negative plate"),
        Field.Get_ReachabilityLabel(0, -1), int32{INDEX_NONE});

    TestEqual(TEXT("and a plate past the end of a real tile"),
        Field.Get_ReachabilityLabel(0, 1000000), int32{INDEX_NONE});

    // A refused lookup must not become a PROOF: two unknowns are not two different components.
    TestFalse(TEXT("and an unknown plate proves nothing about reachability"),
        Field.Get_AreProvablyDisconnected(Field.Get_TileCount(), 0, -1, 0));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
