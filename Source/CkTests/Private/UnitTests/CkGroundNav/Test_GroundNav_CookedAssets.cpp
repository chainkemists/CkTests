// Cooked ground-nav assets.
//
// The asset types are the boundary between a bake that ran once, offline, and a game that only ever
// reads. Two properties are worth pinning before anything writes one:
//
//   1. Every field the cook writes survives the asset unchanged. A cooked tile whose coord, lattice
//      or fingerprint did not round-trip would describe a tile other than the one its blob holds,
//      and the blob itself cannot say which.
//   2. A format version the reader does not speak is REFUSED. Reinterpreting a differently-shaped
//      record as the current one is the failure the version exists to prevent, and it is silent.

#include "CkGroundNav/Cook/CkGroundNav_CookedFieldIndex.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedTile.h"

#include "CkCore/Validation/CkIsValid.h"

#include "../CkUnitTest_Common.h"

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_cookedassets
{
    // Deliberately not the module's current format version: what is under test is the comparison,
    // not the number, and a fixture pinned to the live constant would stop testing the mismatch the
    // day the constant moves.
    constexpr auto kFixtureFormatVersion = 7;

    // A level and a volume name the path convention can be read against. Neither has to exist: the
    // convention is arithmetic over strings, which is exactly what makes it assertable without a cook.
    const auto kFixtureLevelPackage = FName{TEXT("/Game/Maps/TestMap")};
    const auto kFixtureCookKey = FName{TEXT("FirstVolume")};

    auto Make_LatticeKey() -> FCk_GroundNav_CookedLatticeKey
    {
        auto Key = FCk_GroundNav_CookedLatticeKey{};

        Key.Set_OriginXY(FVector2D{-800.0, 400.0});
        Key.Set_Divisions(FIntPoint{3, 2});
        Key.Set_MinZUu(-100.0f);
        Key.Set_MaxZUu(500.0f);
        Key.Set_TileSizeUu(800.0f);
        Key.Set_CellSizeUu(25.0f);
        Key.Set_CellHeightUu(10.0f);

        return Key;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_TileAssetRoundTripsItsFields,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.TileAssetRoundTripsItsFields",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_TileAssetRoundTripsItsFields::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto* Tile = NewObject<UCk_GroundNav_CookedTile_UE>(GetTransientPackage());

    TestTrue(TEXT("the cooked tile asset was created"), ck::IsValid(Tile));

    if (ck::Is_NOT_Valid(Tile))
    { return false; }

    const auto Lattice = Make_LatticeKey();
    const auto Blob = TArray<uint8>{7, 0, 255, 1, 42};

    Tile->Set_FormatVersion(kFixtureFormatVersion);
    Tile->Set_TileCoord(FIntPoint{2, 1});
    Tile->Set_Fingerprint(0xFEDCBA9876543210ull);
    Tile->Set_LatticeKey(Lattice);
    Tile->Set_Blob(Blob);

    TestEqual(TEXT("the format version round-trips"),
        Tile->Get_FormatVersion(), kFixtureFormatVersion);

    TestTrue(TEXT("the tile coord round-trips"),
        Tile->Get_TileCoord() == FIntPoint{2, 1});

    TestTrue(TEXT("the fingerprint round-trips whole, all 64 bits of it"),
        Tile->Get_Fingerprint() == 0xFEDCBA9876543210ull);

    TestTrue(TEXT("the lattice key round-trips every one of its values"),
        Tile->Get_LatticeKey() == Lattice);

    TestTrue(TEXT("the blob round-trips byte for byte"),
        Tile->Get_Blob() == Blob);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_IncompatibleFormatVersionIsRefused,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.IncompatibleFormatVersionIsRefused",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_IncompatibleFormatVersionIsRefused::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto* Tile = NewObject<UCk_GroundNav_CookedTile_UE>(GetTransientPackage());

    TestTrue(TEXT("the cooked tile asset was created"), ck::IsValid(Tile));

    if (ck::Is_NOT_Valid(Tile))
    { return false; }

    Tile->Set_FormatVersion(kFixtureFormatVersion);

    TestTrue(TEXT("a reader speaking the tile's own format is admitted"),
        Tile->Get_IsCompatibleWith(kFixtureFormatVersion));

    TestFalse(TEXT("a reader one version AHEAD is refused"),
        Tile->Get_IsCompatibleWith(kFixtureFormatVersion + 1));

    TestFalse(TEXT("a reader one version BEHIND is refused"),
        Tile->Get_IsCompatibleWith(kFixtureFormatVersion - 1));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_IndexAssetRoundTripsItsFields,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.IndexAssetRoundTripsItsFields",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_IndexAssetRoundTripsItsFields::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto* Index = NewObject<UCk_GroundNav_CookedFieldIndex_UE>(GetTransientPackage());

    TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index));

    if (ck::Is_NOT_Valid(Index))
    { return false; }

    auto* FirstTile = NewObject<UCk_GroundNav_CookedTile_UE>(GetTransientPackage());
    auto* SecondTile = NewObject<UCk_GroundNav_CookedTile_UE>(GetTransientPackage());

    if (NOT TestTrue(TEXT("the two tiles the index names were created"),
        ck::IsValid(FirstTile) && ck::IsValid(SecondTile)))
    { return false; }

    const auto Lattice = Make_LatticeKey();

    const auto Tiles = TArray<TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>>{
        TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>{FirstTile},
        TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>{SecondTile}};

    Index->Set_LevelPackage(kFixtureLevelPackage);
    Index->Set_CookKey(kFixtureCookKey);
    Index->Set_Fingerprint(0x0123456789ABCDEFull);
    Index->Set_FormatVersion(kFixtureFormatVersion);
    Index->Set_LatticeKey(Lattice);
    Index->Set_Tiles(Tiles);

    TestTrue(TEXT("the level package round-trips"), Index->Get_LevelPackage() == kFixtureLevelPackage);

    TestTrue(TEXT("the cook key round-trips"), Index->Get_CookKey() == kFixtureCookKey);

    TestTrue(TEXT("the fingerprint round-trips whole, all 64 bits of it"),
        Index->Get_Fingerprint() == 0x0123456789ABCDEFull);

    TestEqual(TEXT("the format version round-trips"),
        Index->Get_FormatVersion(), kFixtureFormatVersion);

    TestTrue(TEXT("the lattice key round-trips member for member"),
        Index->Get_LatticeKey() == Lattice);

    if (NOT TestEqual(TEXT("the tile list round-trips its count"), Index->Get_Tiles().Num(), 2))
    { return false; }

    // Compared by the asset each entry POINTS AT rather than by the soft pointer's own string: the
    // order is the lattice's tile-index order, and an index that reordered them would hand every
    // reader the wrong tile for the coord it asked about.
    TestTrue(TEXT("and its entries, in the order they were written"),
        Index->Get_Tiles()[0].Get() == FirstTile && Index->Get_Tiles()[1].Get() == SecondTile);

    TestTrue(TEXT("an index refuses a format version it does not speak"),
        NOT Index->Get_IsCompatibleWith(kFixtureFormatVersion + 1));

    TestTrue(TEXT("and admits the one it was written under"),
        Index->Get_IsCompatibleWith(kFixtureFormatVersion));

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_IndexPathConventionIsStable,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.IndexPathConventionIsStable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_IndexPathConventionIsStable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    const auto Root = FString{TEXT("/Game/CkGroundNavData")};
    const auto Level = FString{TEXT("/Game/Maps/TestMap")};

    // Nothing hard-references a cooked asset, so the path IS the reference: two callers computing it
    // from the same three inputs have to arrive at the same string or the lookup finds nothing.
    const auto IndexPath = ck::groundnav::Get_CookedIndexAssetPath(Root, Level, kFixtureCookKey);

    TestTrue(TEXT("the same inputs name the same index path"),
        IndexPath == ck::groundnav::Get_CookedIndexAssetPath(Root, Level, kFixtureCookKey));

    TestTrue(TEXT("the index path is under the cooked root"), IndexPath.StartsWith(Root));

    TestTrue(TEXT("and carries the cook key, which is what separates two volumes in one level"),
        IndexPath.Contains(kFixtureCookKey.ToString()));

    const auto OtherKeyPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, Level, FName{TEXT("SecondVolume")});

    TestTrue(TEXT("so a second volume in the same level names a different asset"),
        IndexPath != OtherKeyPath);

    const auto FirstTilePath = ck::groundnav::Get_CookedTileAssetPath(
        Root, Level, kFixtureCookKey, FIntPoint{2, 1});

    TestTrue(TEXT("the same inputs name the same tile path"),
        FirstTilePath == ck::groundnav::Get_CookedTileAssetPath(
            Root, Level, kFixtureCookKey, FIntPoint{2, 1}));

    TestTrue(TEXT("and a different coord names a different tile"),
        FirstTilePath != ck::groundnav::Get_CookedTileAssetPath(
            Root, Level, kFixtureCookKey, FIntPoint{1, 2}));

    // PIE renames every level package, and the cook only ever ran on the unprefixed one: a lookup key
    // that kept the prefix would match nothing and degrade silently to a runtime bake.
    const auto PieKey = ck::groundnav::Get_PackageLookupKey(TEXT("/Game/Maps/UEDPIE_0_TestMap"));
    const auto CookKey = ck::groundnav::Get_PackageLookupKey(Level);

    TestTrue(TEXT("a PIE-prefixed package resolves to the key the cook recorded"), PieKey == CookKey);

    TestTrue(TEXT("and an unprefixed one is left exactly as it was"),
        CookKey == FName{*Level});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
