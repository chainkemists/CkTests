// What a publish says CHANGED, and what it is never allowed to change.
//
// A reader holding a field learns it is behind by comparing epochs, so the epoch arithmetic is the
// whole revision contract: which tiles a republish stamped (Get_ChangedTileBounds), that the field's
// aggregate strictly rises whenever anything moved and does not budge when nothing did
// (Get_AggregatedTileEpochSum), and that the tile lattice itself is not something a rebuild or a
// derive may renumber.
//
// Every assertion here is exact. The tile bounds are hand-computed against a lattice whose origin,
// cell size and divisions the fixture fixes, and the epoch sums are integers — a revision test that
// accepted "close enough" would pass through the off-by-one that republishes the tile beside the one
// that was painted.

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldMarkupCost.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"
#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_Revision_Slow, "Ck.Test.GroundNav.Revision.Slow");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_GroundNav_Revision_Mud, "Ck.Test.GroundNav.Revision.Mud");

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_groundnav_revision
{
    using ck::groundnav::DoBake_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_GeometryBackend_Stub;
    using ck::groundnav::Get_ChangedTileBounds;
    using ck::groundnav::Get_FieldWithMarkupCost;
    using ck::groundnav::Get_TileWorldBounds;

    constexpr auto kCellSize = 25.0f;
    constexpr auto kCellHeight = 10.0f;
    constexpr auto kTileSize = 400.0f;
    constexpr auto kMaxClearance = 100.0f;

    // Distinctly not 1.0, so "the plate took the record's price" cannot pass on the identity.
    constexpr auto kSlowCostMultiplier = 2.0f;
    constexpr auto kMudCostMultiplier = 3.0f;

    // 2x2 tiles of 400uu from the world origin. Tile indices are Y * DivisionsX + X, so tile 0 covers
    // [0,400] on both axes, tile 1 is its neighbour along X, tile 2 its neighbour along Y, and tile 3
    // the far corner. Every bound below is computed against exactly that.
    constexpr auto kTileIndex00 = 0;
    constexpr auto kTileIndex10 = 1;
    constexpr auto kTileIndex01 = 2;
    constexpr auto kTileIndex11 = 3;
    constexpr auto kTileCount = 4;

    constexpr auto kFieldMinZ = -50.0f;
    constexpr auto kFieldMaxZ = 300.0f;

    constexpr auto kBakedEpoch = int64{1};

    auto Make_Profile() -> FCk_GroundNav_AgentProfile
    {
        // The ledge filter is off: the subject is revision, and the conservative default would trim the
        // fixture's tile borders before a single record was applied.
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        Profile.Set_LedgeSensitivity(0.0f);

        return Profile;
    }

    auto Make_FieldParams() -> FCk_GroundNav_FieldParams
    {
        auto Config = FCk_GroundNav_BakeConfig{kCellSize, kCellHeight};
        Config.Set_TileSizeUu(kTileSize);

        auto Params = FCk_GroundNav_FieldParams{};

        Params._OriginXY = FVector2D::ZeroVector;
        Params._Divisions = FIntPoint{2, 2};
        Params._MinZUu = kFieldMinZ;
        Params._MaxZUu = kFieldMaxZ;
        Params._Config = Config;
        Params._Profile = Make_Profile();
        Params._MaxClearanceUu = kMaxClearance;

        return Params;
    }

    // Ground reaching past the field on every side, so every tile's halo has real world in it.
    auto Bake_Field(
        const FCk_GroundNav_Epoch& InEpoch,
        FCk_GroundNav_Field&       OutField) -> bool
    {
        const auto Backend = FCk_GroundNav_GeometryBackend_Stub{
            TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}}};

        return DoBake_Field(Backend, Make_FieldParams(), InEpoch, OutField).Get_IsCompleted();
    }

    auto Make_CostRecord(
        int32               InId,
        const FVector&      InCentre,
        const FVector&      InHalfExtents,
        const FGameplayTag& InAreaTag,
        float               InCostMultiplier) -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            InId,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{InHalfExtents}},
            FTransform{InCentre},
            ECk_GroundNav_MarkupKind::Cost};

        Record.Set_AreaTag(InAreaTag);
        Record.Set_CostMultiplier(InCostMultiplier);

        return Record;
    }

    // Wholly inside tile (0,0): x and y both in [100,300].
    auto Make_RecordOverTile00() -> FCk_GroundNav_MarkupRecord
    {
        return Make_CostRecord(1, FVector{200.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
            TAG_Test_GroundNav_Revision_Slow.GetTag(), kSlowCostMultiplier);
    }

    // Wholly inside tile (1,1): x and y both in [500,700].
    auto Make_RecordOverTile11() -> FCk_GroundNav_MarkupRecord
    {
        return Make_CostRecord(2, FVector{600.0, 600.0, 0.0}, FVector{100.0, 100.0, 50.0},
            TAG_Test_GroundNav_Revision_Mud.GetTag(), kMudCostMultiplier);
    }

    // Straddles the seam between tile (0,0) and tile (1,0): x in [300,500], y in [100,300], so it
    // reaches those two tiles and neither of the two along Y.
    auto Make_RecordStraddlingTheXSeam() -> FCk_GroundNav_MarkupRecord
    {
        return Make_CostRecord(3, FVector{400.0, 200.0, 0.0}, FVector{100.0, 100.0, 50.0},
            TAG_Test_GroundNav_Revision_Slow.GetTag(), kSlowCostMultiplier);
    }

    auto Do_Derive(
        const FCk_GroundNav_Field&                InField,
        const TArray<FCk_GroundNav_MarkupRecord>& InRecords,
        const FCk_GroundNav_Epoch&                InEpoch) -> FCk_GroundNav_FieldPtr
    {
        const auto Derived = Get_FieldWithMarkupCost(InField, InRecords, InEpoch);

        return Derived.Value.Get_IsCompleted() ? Derived.Key : FCk_GroundNav_FieldPtr{};
    }

    // Member by member, IsValid included: FBox::operator== compares only the corners, so an invalid
    // box and a degenerate one at the world origin would compare equal through it.
    auto Get_BoxesEqual(
        const FBox& InLhs,
        const FBox& InRhs) -> bool
    {
        return InLhs.IsValid == InRhs.IsValid && InLhs.Min == InRhs.Min && InLhs.Max == InRhs.Max;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Revision_ChangedTileBoundsIsTheUnionOfRepublishedTilesOnly,
    "CkTests.UnitTests.CkGroundNav.Revision.ChangedTileBoundsIsTheUnionOfRepublishedTilesOnly",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Revision_ChangedTileBoundsIsTheUnionOfRepublishedTilesOnly::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_revision;

    const auto SourceEpoch = FCk_GroundNav_Epoch{kBakedEpoch};

    auto Source = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the source field bakes"), Bake_Field(SourceEpoch, Source)))
    { return false; }

    if (NOT TestEqual(TEXT("with all four of its tiles built"), Source.Get_BuiltTileCount(), kTileCount))
    { return false; }

    // A full build stamps every tile it builds, so its changed bounds are the whole field: 2x2 tiles
    // of 400uu from the origin, over the field's own vertical slab.
    const auto WholeField = FBox{
        FVector{0.0, 0.0, kFieldMinZ}, FVector{800.0, 800.0, kFieldMaxZ}};

    TestTrue(TEXT("a full build reports every built tile as changed"),
        Get_BoxesEqual(Get_ChangedTileBounds(Source, SourceEpoch), WholeField));

    const auto Records = TArray<FCk_GroundNav_MarkupRecord>{Make_RecordStraddlingTheXSeam()};

    const auto DerivedEpoch = SourceEpoch.Get_Next();
    const auto Derived = Do_Derive(Source, Records, DerivedEpoch);

    if (NOT TestTrue(TEXT("the cost derive completes and yields a field"), Derived.IsValid()))
    { return false; }

    // The subset under test, pinned before the bounds are asked for: a bounds assertion over tiles the
    // derive did not actually republish would prove nothing about the union.
    TestTrue(TEXT("the derive republished the tile the record starts in"),
        Derived->_Tiles[kTileIndex00]._Epoch == DerivedEpoch);
    TestTrue(TEXT("and the tile it crosses into"),
        Derived->_Tiles[kTileIndex10]._Epoch == DerivedEpoch);

    TestTrue(TEXT("the tile along Y, which the record never reaches, keeps its epoch"),
        Derived->_Tiles[kTileIndex01]._Epoch == SourceEpoch);
    TestTrue(TEXT("and so does the far corner"),
        Derived->_Tiles[kTileIndex11]._Epoch == SourceEpoch);

    const auto Changed = Get_ChangedTileBounds(*Derived, DerivedEpoch);

    // Exactly tiles (0,0) and (1,0): [0,800] along X, [0,400] along Y, over the field's slab.
    const auto ExpectedUnion = FBox{
        FVector{0.0, 0.0, kFieldMinZ}, FVector{800.0, 400.0, kFieldMaxZ}};

    TestTrue(TEXT("the changed bounds are the union of exactly the two republished tiles"),
        Get_BoxesEqual(Changed, ExpectedUnion));

    TestTrue(TEXT("computed the same way the tiles themselves report it"),
        Get_BoxesEqual(Changed,
            Get_TileWorldBounds(Derived->_Params, Derived->_Tiles[kTileIndex00]) +
            Get_TileWorldBounds(Derived->_Params, Derived->_Tiles[kTileIndex10])));

    const auto UntouchedTileBounds = Get_TileWorldBounds(
        Derived->_Params, Derived->_Tiles[kTileIndex11]);

    // Shrunk off the shared corner line: the untouched tile's box abuts the changed one along y = 400,
    // and a touching test would call that an overlap.
    TestFalse(TEXT("and they do not reach the tile nothing republished"),
        Changed.Intersect(UntouchedTileBounds.ExpandBy(-1.0)));

    // An epoch no tile carries is not an empty region, and must not be reported as a box around one.
    const auto UnusedEpoch = FCk_GroundNav_Epoch{99};

    TestTrue(TEXT("an epoch nobody carries yields an invalid box"),
        Get_ChangedTileBounds(*Derived, UnusedEpoch).IsValid == 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Revision_TileEpochSumRisesOnEveryInterleaving,
    "CkTests.UnitTests.CkGroundNav.Revision.TileEpochSumRisesOnEveryInterleaving",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Revision_TileEpochSumRisesOnEveryInterleaving::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_revision;

    const auto SourceEpoch = FCk_GroundNav_Epoch{kBakedEpoch};

    auto Source = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the source field bakes"), Bake_Field(SourceEpoch, Source)))
    { return false; }

    const auto SourceSum = Source.Get_AggregatedTileEpochSum();

    TestEqual(TEXT("four tiles at epoch one sum to four"), SourceSum, int64{kTileCount});

    const auto OverTile00 = Make_RecordOverTile00();
    const auto OverTile11 = Make_RecordOverTile11();

    // ---- Interleaving one: add, restate, add a second, disable the first, delete the first ----------

    const auto AddedFirst = Do_Derive(Source, {OverTile00}, FCk_GroundNav_Epoch{2});

    if (NOT TestTrue(TEXT("adding a record derives a field"), AddedFirst.IsValid()))
    { return false; }

    const auto AddedFirstSum = AddedFirst->Get_AggregatedTileEpochSum();

    TestTrue(TEXT("adding a record raises the epoch sum"), AddedFirstSum > SourceSum);

    // A derive that changes nothing still allocates a field — the epoch, not the pointer, is what says
    // whether there is news, and it is what the volume processor gates its publish on.
    const auto Restated = Do_Derive(*AddedFirst, {OverTile00}, FCk_GroundNav_Epoch{3});

    if (NOT TestTrue(TEXT("restating the same record derives a field"), Restated.IsValid()))
    { return false; }

    TestFalse(TEXT("a derive that moves no label publishes no newer epoch"),
        Restated->_Epoch.Get_IsNewerThan(AddedFirst->_Epoch));
    TestEqual(TEXT("and leaves the epoch sum exactly where it was"),
        Restated->Get_AggregatedTileEpochSum(), AddedFirstSum);

    const auto AddedSecond = Do_Derive(*AddedFirst, {OverTile00, OverTile11}, FCk_GroundNav_Epoch{4});

    if (NOT TestTrue(TEXT("adding a second record derives a field"), AddedSecond.IsValid()))
    { return false; }

    const auto AddedSecondSum = AddedSecond->Get_AggregatedTileEpochSum();

    TestTrue(TEXT("a record over a second tile raises the sum again"), AddedSecondSum > AddedFirstSum);

    auto DisabledFirst = OverTile00;
    DisabledFirst.Set_Enable(ECk_EnableDisable::Disable);

    const auto Disabled = Do_Derive(*AddedSecond, {DisabledFirst, OverTile11}, FCk_GroundNav_Epoch{5});

    if (NOT TestTrue(TEXT("disabling a record derives a field"), Disabled.IsValid()))
    { return false; }

    const auto DisabledSum = Disabled->Get_AggregatedTileEpochSum();

    TestTrue(TEXT("switching a record off is a change, and raises the sum"), DisabledSum > AddedSecondSum);

    // Deleting a record the previous derive already un-priced converges on the same field, so there is
    // nothing left to republish: disabling and deleting are one destination reached twice.
    const auto Deleted = Do_Derive(*Disabled, {OverTile11}, FCk_GroundNav_Epoch{6});

    if (NOT TestTrue(TEXT("deleting the disabled record derives a field"), Deleted.IsValid()))
    { return false; }

    TestFalse(TEXT("deleting what was already off publishes no newer epoch"),
        Deleted->_Epoch.Get_IsNewerThan(Disabled->_Epoch));
    TestEqual(TEXT("and leaves the epoch sum where the disable put it"),
        Deleted->Get_AggregatedTileEpochSum(), DisabledSum);

    // ---- Interleaving two: the same edits off the same source field, in the other order -------------

    const auto SecondFirst = Do_Derive(Source, {OverTile11}, FCk_GroundNav_Epoch{2});

    if (NOT TestTrue(TEXT("the other order derives a field"), SecondFirst.IsValid()))
    { return false; }

    const auto SecondFirstSum = SecondFirst->Get_AggregatedTileEpochSum();

    TestTrue(TEXT("the far tile's record raises the sum off the same source"),
        SecondFirstSum > SourceSum);

    const auto BothPriced = Do_Derive(*SecondFirst, {OverTile11, OverTile00}, FCk_GroundNav_Epoch{3});

    if (NOT TestTrue(TEXT("pricing both derives a field"), BothPriced.IsValid()))
    { return false; }

    const auto BothPricedSum = BothPriced->Get_AggregatedTileEpochSum();

    TestTrue(TEXT("and adding the near tile's record raises it again"), BothPricedSum > SecondFirstSum);

    const auto AllRemoved = Do_Derive(*BothPriced, {}, FCk_GroundNav_Epoch{4});

    if (NOT TestTrue(TEXT("removing both derives a field"), AllRemoved.IsValid()))
    { return false; }

    TestTrue(TEXT("removing both records raises the sum a third time"),
        AllRemoved->Get_AggregatedTileEpochSum() > BothPricedSum);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Revision_TileCountIsInvariantAcrossRebuilds,
    "CkTests.UnitTests.CkGroundNav.Revision.TileCountIsInvariantAcrossRebuilds",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Revision_TileCountIsInvariantAcrossRebuilds::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_revision;

    auto First = FCk_GroundNav_Field{};
    auto Second = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the first bake completes"),
        Bake_Field(FCk_GroundNav_Epoch{kBakedEpoch}, First)))
    { return false; }

    if (NOT TestTrue(TEXT("and so does a second bake of the identical params"),
        Bake_Field(FCk_GroundNav_Epoch{kBakedEpoch + 1}, Second)))
    { return false; }

    if (NOT TestEqual(TEXT("a bake publishes the tile count the divisions name"),
        First._Tiles.Num(), Make_FieldParams().Get_TileCount()))
    { return false; }

    if (NOT TestEqual(TEXT("and the rebuild publishes the same number of tiles"),
        Second._Tiles.Num(), First._Tiles.Num()))
    { return false; }

    auto RebuiltMismatchCount = 0;

    for (auto TileIndex = 0; TileIndex < First._Tiles.Num(); ++TileIndex)
    {
        const auto& Before = First._Tiles[TileIndex];
        const auto& After = Second._Tiles[TileIndex];

        const auto Matches = Before._Coord == After._Coord && Before._Origin == After._Origin &&
                             Before._SizeX == After._SizeX && Before._SizeY == After._SizeY;

        if (NOT Matches)
        { ++RebuiltMismatchCount; }
    }

    TestEqual(TEXT("every tile of the rebuild sits where the first bake put it"),
        RebuiltMismatchCount, 0);

    const auto Records = TArray<FCk_GroundNav_MarkupRecord>{Make_RecordStraddlingTheXSeam()};

    const auto Derived = Do_Derive(First, Records, FCk_GroundNav_Epoch{kBakedEpoch + 1});

    if (NOT TestTrue(TEXT("the cost derive completes and yields a field"), Derived.IsValid()))
    { return false; }

    if (NOT TestEqual(TEXT("a derive never changes the tile count"),
        Derived->_Tiles.Num(), First._Tiles.Num()))
    { return false; }

    auto DerivedMismatchCount = 0;

    for (auto TileIndex = 0; TileIndex < First._Tiles.Num(); ++TileIndex)
    {
        const auto& Before = First._Tiles[TileIndex];
        const auto& After = Derived->_Tiles[TileIndex];

        const auto Matches = Before._Coord == After._Coord && Before._Origin == After._Origin &&
                             Before._SizeX == After._SizeX && Before._SizeY == After._SizeY;

        if (NOT Matches)
        { ++DerivedMismatchCount; }
    }

    TestEqual(TEXT("and leaves every tile where the bake put it"), DerivedMismatchCount, 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
