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
#include "CkGroundNav/Cook/CkGroundNav_CookedFieldLoad.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedTile.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Field/CkGroundNav_TileBake.h"
#include "CkGroundNav/Field/CkGroundNav_FieldTypes.h"

#include "CkCore/Validation/CkIsValid.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_FieldEquality.h"
#include "Test_GroundNav_QueryFixtures.h"

#include <UObject/Class.h>
#include <UObject/Package.h>
#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_cookedassets
{
    UE_DEFINE_GAMEPLAY_TAG_STATIC(kCookedProfileTag, "CkTests.GroundNav.CookedProfile");
    UE_DEFINE_GAMEPLAY_TAG_STATIC(kCookedPathProfileA, "A");
    UE_DEFINE_GAMEPLAY_TAG_STATIC(kCookedPathProfileProfilesA, "Profiles.A");
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

    // ----------------------------------------------------------------------------------------------------
    //
    // The load side. Every fixture below builds its cooked assets in the TRANSIENT package out of a
    // field the stub backend baked, so the whole cooked/runtime decision is exercised without a world,
    // without a cook and without a single asset on disk — which is the property the pure load path was
    // split out to have.

    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_Epoch;
    using ck::groundnav::FCk_GroundNav_DataLayerSelector;
    using ck::groundnav::Get_CookedLatticeKey;
    using ck::groundnav::Get_CookedTileContentHash;
    using ck::groundnav::Get_TileBounds;
    using ck::groundnav::Read_Field;
    using ck::groundnav::Try_LoadCookedField;
    using ck::groundnav::TryMake_DataLayerSelector;
    using ck::groundnav::Write_Field;
    using ck::groundnav::Write_Tile;
    using ck::groundnav::kFieldBlobFormatVersion;

    using ck_test_groundnav_field_equality::EEpochComparison;
    using ck_test_groundnav_field_equality::EPolicyComparison;
    using ck_test_groundnav_field_equality::Get_FirstFieldDifference;
    using ck_test_groundnav_field_equality::Get_FirstParamsDifference;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;

    // The bake this fixture's index claims to have come out of. An arbitrary value on purpose: what is
    // under test is that the number is COMPARED, and pinning it to whatever the params currently hash
    // to would make the fixture agree with itself for a reason the code under test does not supply.
    constexpr auto kFixtureInputFingerprint = uint64{0x0F1E2D3C4B5A6978ull};

    auto Get_CookStatusName(ECk_GroundNav_CookStatus InStatus) -> FString
    {
        return StaticEnum<ECk_GroundNav_CookStatus>()->GetNameStringByValue(static_cast<int64>(InStatus));
    }

    /** Every tile of InField written to its own transient cooked asset, in tile-index order. */
    auto Make_CookedTilesFor(
        const FCk_GroundNav_Field& InField,
        FGameplayTag InProfileTag = {},
        int32 InStreamingVolumeId = INDEX_NONE,
        const FCk_GroundNav_DataLayerSelector& InDataLayerSelector = {})
        -> TArray<TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>>
    {
        const auto Lattice = Get_CookedLatticeKey(InField._Params);

        auto Tiles = TArray<TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>>{};
        Tiles.Reserve(InField._Tiles.Num());

        for (const auto& Tile : InField._Tiles)
        {
            auto Blob = TArray<uint8>{};
            Write_Tile(InField, Tile._Coord, Blob);

            auto* CookedTile = NewObject<UCk_GroundNav_CookedTile_UE>(GetTransientPackage());

            if (ck::Is_NOT_Valid(CookedTile))
            { return {}; }

            CookedTile->Set_FormatVersion(kFieldBlobFormatVersion);
            CookedTile->Set_TileCoord(FIntPoint{Tile._Coord._X, Tile._Coord._Y});
            CookedTile->Set_StreamingVolumeId(InStreamingVolumeId);
            CookedTile->Set_WorldBounds(Get_TileBounds(
                InField._Params.Get_TileBakeParams(Tile._Coord, FCk_GroundNav_Epoch{})));
            CookedTile->Set_DataLayerNames(InDataLayerSelector.Get_LayerNames());
            CookedTile->Set_Fingerprint(kFixtureInputFingerprint);
            CookedTile->Set_ProfileTag(InProfileTag);
            CookedTile->Set_LatticeKey(Lattice);
            CookedTile->Set_Blob(Blob);
            CookedTile->Set_ContentHash(Get_CookedTileContentHash(CookedTile->Get_Blob()));

            Tiles.Emplace(TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>{CookedTile});
        }

        return Tiles;
    }

    /** An index over those tiles that a reader speaking the current format would accept. */
    auto Make_CookedIndexFor(
        const FCk_GroundNav_Field&                                 InField,
        const TArray<TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>>& InTiles,
        FGameplayTag InProfileTag = {},
        int32 InStreamingVolumeId = INDEX_NONE,
        const FCk_GroundNav_DataLayerSelector& InDataLayerSelector = {})
        -> UCk_GroundNav_CookedFieldIndex_UE*
    {
        auto* Index = NewObject<UCk_GroundNav_CookedFieldIndex_UE>(GetTransientPackage());

        if (ck::Is_NOT_Valid(Index))
        { return nullptr; }

        Index->Set_LevelPackage(kFixtureLevelPackage);
        Index->Set_CookKey(kFixtureCookKey);
        Index->Set_StreamingVolumeId(InStreamingVolumeId);
        Index->Set_DataLayerNames(InDataLayerSelector.Get_LayerNames());
        Index->Set_ProfileTag(InProfileTag);
        Index->Set_Fingerprint(kFixtureInputFingerprint);
        Index->Set_FormatVersion(kFieldBlobFormatVersion);
        Index->Set_LatticeKey(Get_CookedLatticeKey(InField._Params));
        Index->Set_Tiles(InTiles);

        return Index;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AStreamedChunkIdentityMismatchIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AStreamedChunkIdentityMismatchIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AStreamedChunkIdentityMismatchIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    constexpr auto kStreamingVolumeId = int32{701};
    auto Selector = FCk_GroundNav_DataLayerSelector{};
    const auto SelectorNames = TArray<FName>{FName{TEXT("Gameplay" )}, FName{TEXT("Navigation")}};

    if (NOT TestTrue(TEXT("the streamed selector canonicalizes"),
        TryMake_DataLayerSelector(SelectorNames, Selector)))
    { return false; }

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked, {}, kStreamingVolumeId, Selector);
    auto* Index = Make_CookedIndexFor(Baked, Tiles, {}, kStreamingVolumeId, Selector);

    if (NOT TestTrue(TEXT("the streamed cooked assets were created"),
        ck::IsValid(Index) && NOT Tiles.IsEmpty() && Tiles[0].IsValid()))
    { return false; }

    auto* FirstTile = Tiles[0].Get();
    TestEqual(TEXT("the manifest retains the positive streamed volume identity"),
        Index->Get_StreamingVolumeId(), kStreamingVolumeId);
    TestTrue(TEXT("the manifest retains the canonical selector set"),
        Index->Get_DataLayerNames() == Selector.Get_LayerNames());
    TestEqual(TEXT("every chunk retains the same positive volume identity"),
        FirstTile->Get_StreamingVolumeId(), kStreamingVolumeId);
    TestTrue(TEXT("every chunk retains exact published-cell bounds"),
        FirstTile->Get_WorldBounds() == Get_TileBounds(
            Baked._Params.Get_TileBakeParams(Baked._Tiles[0]._Coord, FCk_GroundNav_Epoch{})));
    TestTrue(TEXT("every chunk retains the canonical selector set"),
        FirstTile->Get_DataLayerNames() == Selector.Get_LayerNames());
    TestEqual(TEXT("every chunk retains a hash of its value blob"), FirstTile->Get_ContentHash(),
        Get_CookedTileContentHash(FirstTile->Get_Blob()));

    auto Loaded = FCk_GroundNav_Field{};
    auto Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, {}, kStreamingVolumeId, Selector);

    if (NOT TestTrue(TEXT("matching streamed chunk identity loads"),
        Status == ECk_GroundNav_CookStatus::Cooked))
    { return false; }

    // The same bytes with a different selector would describe a different geometry collection. The
    // caller's fallback is deliberately non-empty before the refusal to prove validation is atomic.
    FirstTile->Set_DataLayerNames(TArray<FName>{FName{TEXT("OtherLayer")}});
    Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;
    Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, {}, kStreamingVolumeId, Selector);

    TestTrue(TEXT("a chunk from another selector is stale"), Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("selector refusal leaves the caller fallback untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());

    FirstTile->Set_DataLayerNames(Selector.Get_LayerNames());
    auto WrongBounds = FirstTile->Get_WorldBounds();
    WrongBounds.Max.X += 1.0;
    FirstTile->Set_WorldBounds(WrongBounds);
    Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;
    Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, {}, kStreamingVolumeId, Selector);

    TestTrue(TEXT("a chunk with mismatched world bounds is stale"), Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("world-bounds refusal leaves the caller fallback untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());

    // A hashless chunk is not a 7E chunk. Refuse before deserializing so a malformed asset cannot
    // publish an answer whose bytes the manifest never authenticated.
    FirstTile->Set_WorldBounds(Get_TileBounds(
        Baked._Params.Get_TileBakeParams(Baked._Tiles[0]._Coord, FCk_GroundNav_Epoch{})));
    FirstTile->Set_ContentHash(0);
    Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;
    Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, {}, kStreamingVolumeId, Selector);

    TestTrue(TEXT("a hashless chunk is stale"), Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("hash refusal leaves the caller fallback untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());

    FirstTile->Set_ContentHash(Get_CookedTileContentHash(FirstTile->Get_Blob()));
    FirstTile->Set_StreamingVolumeId(kStreamingVolumeId + 1);
    Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;
    Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, {}, kStreamingVolumeId, Selector);

    TestTrue(TEXT("a chunk from another streamed volume is stale"),
        Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("volume-identity refusal leaves the caller fallback untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());

    FirstTile->Set_StreamingVolumeId(kStreamingVolumeId);
    FirstTile->Set_TileCoord(FIntPoint{99, 99});
    Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;
    Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, {}, kStreamingVolumeId, Selector);

    TestTrue(TEXT("a chunk filed under another coordinate is stale"),
        Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("coordinate refusal leaves the caller fallback untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());

    FirstTile->Set_TileCoord(FIntPoint{Baked._Tiles[0]._Coord._X, Baked._Tiles[0]._Coord._Y});
    const auto NonCanonicalNames = TArray<FName>{FName{TEXT("Navigation")}, FName{TEXT("Gameplay")}};
    Index->Set_DataLayerNames(NonCanonicalNames);
    FirstTile->Set_DataLayerNames(NonCanonicalNames);
    Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;
    Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, {}, kStreamingVolumeId, Selector);

    TestTrue(TEXT("a manifest with noncanonical selector names is stale"),
        Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("selector-shape refusal leaves the caller fallback untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AProfileSwappedTileIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AProfileSwappedTileIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AProfileSwappedTileIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked, kCookedProfileTag);
    auto* Index = Make_CookedIndexFor(Baked, Tiles, kCookedProfileTag);

    if (NOT TestTrue(TEXT("the variant cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    // The index says variant while the first tile was copied from default. Its bytes can deserialize,
    // but they name a different field and must not partially mutate the caller's fallback field.
    Tiles[0].Get()->Set_ProfileTag({});
    auto Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;

    const auto Status = Try_LoadCookedField(*Index, kFixtureLevelPackage, kFixtureCookKey,
        Baked._Params, kFixtureInputFingerprint, Loaded, kCookedProfileTag);

    TestTrue(TEXT("a tile from another profile is stale"), Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("and the fallback field is untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AWrongTileCardinalityIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AWrongTileCardinalityIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AWrongTileCardinalityIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked);

    if (NOT TestTrue(TEXT("the fixture cooked at least one tile"), NOT Tiles.IsEmpty()))
    { return false; }

    Tiles.Pop();
    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the incomplete cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;

    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(TEXT("a missing tile slot is stale"), Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("and the fallback field is untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AMalformedParamsAreStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AMalformedParamsAreStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AMalformedParamsAreStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked);
    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index and tile assets were created"),
        ck::IsValid(Index) && NOT Tiles.IsEmpty() && Tiles[0].IsValid()))
    { return false; }

    auto MalformedParams = Baked._Params;
    MalformedParams._Divisions = FIntPoint{0, 1};
    auto Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;

    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, MalformedParams, kFixtureInputFingerprint, Loaded);

    TestTrue(TEXT("malformed field params are stale before an allocation"),
        Status == ECk_GroundNav_CookStatus::StaleCook);
    TestTrue(TEXT("and the fallback field is untouched"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());
    return true;
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

    TestEqual(TEXT("the default profile keeps its published legacy path"), IndexPath,
        FString{TEXT("/Game/CkGroundNavData/Maps/TestMap/GroundNavIndex_FirstVolume.GroundNavIndex_FirstVolume")});

    TestTrue(TEXT("and carries the cook key, which is what separates two volumes in one level"),
        IndexPath.Contains(kFixtureCookKey.ToString()));

    const auto OtherKeyPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, Level, FName{TEXT("SecondVolume")});

    TestTrue(TEXT("so a second volume in the same level names a different asset"),
        IndexPath != OtherKeyPath);

    const auto NestedDefaultLevel = FString{TEXT("/Game/Maps/Foo/Profiles/A")};
    const auto VariantSourceLevel = FString{TEXT("/Game/Maps/Foo")};
    const auto NestedDefaultPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, NestedDefaultLevel, kFixtureCookKey);
    const auto VariantPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, VariantSourceLevel, kFixtureCookKey, kCookedPathProfileA);

    TestTrue(TEXT("a profile asset cannot overlap a default asset in a level path named Profiles/A"),
        NestedDefaultPath != VariantPath);

    TestEqual(TEXT("a profile asset uses the dedicated, count-delimited schema"), VariantPath,
        FString{TEXT("/Game/CkGroundNavData/__CkGroundNavProfiles/Level_3/Game/Maps/Foo/Profiles/S_A/GroundNavProfileIndex_FirstVolume.GroundNavProfileIndex_FirstVolume")});

    const auto NestedVariantPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, TEXT("/Game/Maps/Foo/Profiles"), kFixtureCookKey, kCookedPathProfileA);
    const auto HierarchicalVariantPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, VariantSourceLevel, kFixtureCookKey, kCookedPathProfileProfilesA);

    TestTrue(TEXT("the source-level component count separates nested-level and nested-profile variants"),
        NestedVariantPath != HierarchicalVariantPath);

    auto FirstSelector = FCk_GroundNav_DataLayerSelector{};
    auto SecondSelector = FCk_GroundNav_DataLayerSelector{};
    auto FirstSelectorInOtherAuthoringOrder = FCk_GroundNav_DataLayerSelector{};
    const auto FirstSelectorNames = TArray<FName>{FName{TEXT("Gameplay")}, FName{TEXT("Navigation")}};
    const auto SecondSelectorNames = TArray<FName>{FName{TEXT("Gameplay")}, FName{TEXT("Props")}};
    const auto FirstSelectorNamesReversed = TArray<FName>{FName{TEXT("Navigation")}, FName{TEXT("Gameplay")}};

    if (NOT TestTrue(TEXT("the first selector canonicalizes"),
        TryMake_DataLayerSelector(FirstSelectorNames, FirstSelector)) ||
        NOT TestTrue(TEXT("the second selector canonicalizes"),
        TryMake_DataLayerSelector(SecondSelectorNames, SecondSelector)) ||
        NOT TestTrue(TEXT("the reordered first selector canonicalizes"),
        TryMake_DataLayerSelector(FirstSelectorNamesReversed, FirstSelectorInOtherAuthoringOrder)))
    { return false; }

    const auto FirstSelectorPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, Level, kFixtureCookKey, {}, FirstSelector);
    const auto SecondSelectorPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, Level, kFixtureCookKey, {}, SecondSelector);
    const auto ReorderedFirstSelectorPath = ck::groundnav::Get_CookedIndexAssetPath(
        Root, Level, kFixtureCookKey, {}, FirstSelectorInOtherAuthoringOrder);

    TestTrue(TEXT("different canonical selector sets have distinct index paths"),
        FirstSelectorPath != SecondSelectorPath);
    TestEqual(TEXT("selector path identity is independent of authoring order"),
        FirstSelectorPath, ReorderedFirstSelectorPath);
    TestTrue(TEXT("a selector path carries every canonical layer name"),
        FirstSelectorPath.Contains(TEXT("L_Gameplay")) && FirstSelectorPath.Contains(TEXT("L_Navigation")));

    const auto FirstTilePath = ck::groundnav::Get_CookedTileAssetPath(
        Root, Level, kFixtureCookKey, FIntPoint{2, 1});

    TestTrue(TEXT("the same inputs name the same tile path"),
        FirstTilePath == ck::groundnav::Get_CookedTileAssetPath(
            Root, Level, kFixtureCookKey, FIntPoint{2, 1}));

    TestTrue(TEXT("and a different coord names a different tile"),
        FirstTilePath != ck::groundnav::Get_CookedTileAssetPath(
            Root, Level, kFixtureCookKey, FIntPoint{1, 2}));

    TestTrue(TEXT("profile tiles also use a basename distinct from default tiles"),
        ck::groundnav::Get_CookedTileAssetPath(
            Root, VariantSourceLevel, kFixtureCookKey, FIntPoint{2, 1}, kCookedPathProfileA)
        .EndsWith(TEXT("/GroundNavProfileTile_FirstVolume_2_1.GroundNavProfileTile_FirstVolume_2_1")));

    TestTrue(TEXT("different selector sets also separate tile paths"),
        ck::groundnav::Get_CookedTileAssetPath(
            Root, Level, kFixtureCookKey, FIntPoint{2, 1}, {}, FirstSelector)
        != ck::groundnav::Get_CookedTileAssetPath(
            Root, Level, kFixtureCookKey, FIntPoint{2, 1}, {}, SecondSelector));

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
// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_LoadingACookedFieldComposesItFromItsTiles,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.LoadingACookedFieldComposesItFromItsTiles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_LoadingACookedFieldComposesItFromItsTiles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    const auto Tiles = Make_CookedTilesFor(Baked);

    if (NOT TestEqual(TEXT("every tile of the baked field was cooked"), Tiles.Num(), Baked._Tiles.Num()))
    { return false; }

    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};

    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("an index whose identity matches loads [%s]"),
        *Get_CookStatusName(Status)), Status == ECk_GroundNav_CookStatus::Cooked))
    { return false; }

    // _Params is not part of what the field comparator walks, and it is the half a tile blob carries
    // none of: the loader writes the params it was HANDED onto the field it composes, so a loader
    // that dropped or reshaped one of them would produce a field every index in it still agreed with.
    const auto ParamsDifference = Get_FirstParamsDifference(Baked._Params, Loaded._Params);

    TestTrue(FString::Printf(TEXT("the loaded field carries the params it was loaded for [%s]"),
        *ParamsDifference), ParamsDifference.IsEmpty());

    // A cooked field carries no open body: the per-tile form has none, and the closure diagnostics
    // belong to the run that read the meshes. Asserted on the loaded field DIRECTLY as well as
    // through the comparison below, so the claim survives the fixture gaining an open panel.
    TestTrue(TEXT("a loaded cooked field reports no open body"), Loaded._OpenBodies.IsEmpty());

    auto BakedWithoutOpenBodies = Baked;
    BakedWithoutOpenBodies._OpenBodies.Reset();

    // Epochs excluded - the cook carries the bake's own tile epochs and the field it is loaded into is
    // stamped by whoever publishes it, so they are the one thing a load is not obliged to reproduce.
    // Every cell, every plate and every array the load RE-DERIVED rather than read is compared member
    // for member. _Params is asserted separately above: the comparator does not reach it.
    const auto Difference = Get_FirstFieldDifference(
        BakedWithoutOpenBodies, Loaded, EPolicyComparison::Include, EEpochComparison::Exclude);

    TestTrue(FString::Printf(TEXT("the loaded field equals the baked one [%s]"), *Difference),
        Difference.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AStaleFingerprintIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AStaleFingerprintIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AStaleFingerprintIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked);
    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    Loaded._Params._MinZUu = -12345.0f;

    // The volume's inputs have moved since the cook: the tiles describe ground baked under something
    // else, and reading them would answer about a world that is no longer there.
    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint + 1, Loaded);

    TestTrue(FString::Printf(TEXT("an index whose fingerprint names other inputs is stale [%s]"),
        *Get_CookStatusName(Status)), Status == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and the caller's field is left exactly as it was, so a fallback has something to fall back to"),
        Loaded._Params._MinZUu == -12345.0f && Loaded._Tiles.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AnIncompatibleFormatIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AnIncompatibleFormatIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AnIncompatibleFormatIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked);
    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    // A v1 field may have plate topology produced before connection-gated decomposition, so it is
    // stale even though its byte layout remains readable.
    Index->Set_FormatVersion(1);

    auto Loaded = FCk_GroundNav_Field{};

    const auto OldVersionStatus = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("a v1 index is stale [%s]"),
        *Get_CookStatusName(OldVersionStatus)), OldVersionStatus == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and nothing was composed"), Loaded._Tiles.IsEmpty());

    // The comparison is exact in both directions; a future writer is equally unsafe to admit.
    Index->Set_FormatVersion(kFieldBlobFormatVersion + 1);
    const auto FutureVersionStatus = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("a future-version index is stale [%s]"),
        *Get_CookStatusName(FutureVersionStatus)), FutureVersionStatus == ECk_GroundNav_CookStatus::StaleCook);

    Index->Set_FormatVersion(kFieldBlobFormatVersion);
    auto* FirstTile = Tiles.IsEmpty() ? nullptr : Tiles[0].Get();
    if (NOT TestTrue(TEXT("the first cooked tile resolves"), ck::IsValid(FirstTile)))
    { return false; }
    FirstTile->Set_FormatVersion(1);
    const auto OldTileVersionStatus = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("a v1 tile is stale [%s]"),
        *Get_CookStatusName(OldTileVersionStatus)), OldTileVersionStatus == ECk_GroundNav_CookStatus::StaleCook);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AMissingTileIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AMissingTileIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AMissingTileIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked);

    if (NOT TestTrue(TEXT("the fixture cooked at least one tile"), NOT Tiles.IsEmpty()))
    { return false; }

    // A tile the cook wrote and something has since deleted or renamed. The index is describing a
    // field that is not there, and a partial field is not a smaller field — it is ground reported as
    // unbuilt that the cook says is walkable.
    Tiles[0] = TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>{};

    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};

    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("an index naming a tile that resolves to nothing is stale [%s]"),
        *Get_CookStatusName(Status)), Status == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and no partially composed field reaches the caller"), Loaded._Tiles.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_ATruncatedTileBlobIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.ATruncatedTileBlobIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_ATruncatedTileBlobIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    const auto Tiles = Make_CookedTilesFor(Baked);

    if (NOT TestTrue(TEXT("the fixture cooked at least one tile"), NOT Tiles.IsEmpty()))
    { return false; }

    auto* FirstTile = Tiles[0].Get();

    if (NOT TestTrue(TEXT("the first cooked tile resolves"), ck::IsValid(FirstTile)))
    { return false; }

    auto TruncatedBlob = FirstTile->Get_Blob();

    if (NOT TestTrue(TEXT("the cooked blob is long enough to truncate"), TruncatedBlob.Num() > 2))
    { return false; }

    TruncatedBlob.SetNum(TruncatedBlob.Num() / 2);
    FirstTile->Set_Blob(TruncatedBlob);

    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};

    // The serializer's own refusal, reported as the one thing it means to a caller about to fall back.
    // A blob that ends before its tile does cannot be half-read: the members after the cut would come
    // out of whatever bytes followed.
    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("a tile whose blob ends early is stale [%s]"),
        *Get_CookStatusName(Status)), Status == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and no partially composed field reaches the caller"), Loaded._Tiles.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_ATileAssetFromAnotherBakeIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.ATileAssetFromAnotherBakeIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_ATileAssetFromAnotherBakeIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    const auto Tiles = Make_CookedTilesFor(Baked);

    if (NOT TestTrue(TEXT("the fixture cooked at least one tile"), NOT Tiles.IsEmpty()))
    { return false; }

    auto* FirstTile = Tiles[0].Get();

    if (NOT TestTrue(TEXT("the first cooked tile resolves"), ck::IsValid(FirstTile)))
    { return false; }

    // The INDEX still names the bake the caller asked for, so nothing the index carries is wrong; one
    // tile beside it came out of another one. Its blob reads perfectly - the format, the lattice and
    // the coord all agree - and its cells describe ground baked under inputs that have since moved.
    // Nothing but this comparison can tell.
    FirstTile->Set_Fingerprint(kFixtureInputFingerprint + 1);

    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};

    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("a tile cooked from another bake than the index it is listed in is stale [%s]"),
        *Get_CookStatusName(Status)), Status == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and no partially composed field reaches the caller"), Loaded._Tiles.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_ATileAssetOfAnotherLatticeIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.ATileAssetOfAnotherLatticeIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_ATileAssetOfAnotherLatticeIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    const auto Tiles = Make_CookedTilesFor(Baked);

    if (NOT TestTrue(TEXT("the fixture cooked at least one tile"), NOT Tiles.IsEmpty()))
    { return false; }

    auto* FirstTile = Tiles[0].Get();

    if (NOT TestTrue(TEXT("the first cooked tile resolves"), ck::IsValid(FirstTile)))
    { return false; }

    // A lattice the index does not share. The asset's own claim, judged against the collection that
    // lists it: a tile produced on another division carries tile-local indices that name other cells,
    // and the blob would place them over ground it was never baked from.
    FirstTile->Set_LatticeKey(Make_LatticeKey());

    if (NOT TestTrue(TEXT("the fixture lattice differs from the baked field's, or this pins nothing"),
        NOT (Make_LatticeKey() == Get_CookedLatticeKey(Baked._Params))))
    { return false; }

    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};

    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("a tile claiming another lattice than the index it is listed in is stale [%s]"),
        *Get_CookStatusName(Status)), Status == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and no partially composed field reaches the caller"), Loaded._Tiles.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_AnIndexForAnotherKeyIsStaleCook,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.AnIndexForAnotherKeyIsStaleCook",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_AnIndexForAnotherKeyIsStaleCook::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked);
    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    // A cooked asset is reached by PATH and by nothing else, so the asset that answers a lookup is not
    // necessarily the one that path names: an index moved, renamed or copied from another level would
    // load, and every check below it would pass, because it is internally consistent about a volume
    // nobody asked about. It says which level and which volume it was written for.
    auto LoadedForAnotherVolume = FCk_GroundNav_Field{};

    const auto OtherKeyStatus = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, FName{TEXT("SecondVolume")}, Baked._Params,
        kFixtureInputFingerprint, LoadedForAnotherVolume);

    TestTrue(FString::Printf(TEXT("an index written for another volume's cook key is stale [%s]"),
        *Get_CookStatusName(OtherKeyStatus)), OtherKeyStatus == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and nothing was composed for the volume that asked"), LoadedForAnotherVolume._Tiles.IsEmpty());

    auto LoadedForAnotherLevel = FCk_GroundNav_Field{};

    const auto OtherLevelStatus = Try_LoadCookedField(
        *Index, FName{TEXT("/Game/Maps/OtherMap")}, kFixtureCookKey, Baked._Params,
        kFixtureInputFingerprint, LoadedForAnotherLevel);

    TestTrue(FString::Printf(TEXT("an index cooked from another level package is stale [%s]"),
        *Get_CookStatusName(OtherLevelStatus)), OtherLevelStatus == ECk_GroundNav_CookStatus::StaleCook);

    TestTrue(TEXT("and nothing was composed for the level that asked"), LoadedForAnotherLevel._Tiles.IsEmpty());

    auto Loaded = FCk_GroundNav_Field{};

    const auto MatchingStatus = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    TestTrue(FString::Printf(TEXT("and the identity it WAS written for still loads [%s]"),
        *Get_CookStatusName(MatchingStatus)), MatchingStatus == ECk_GroundNav_CookStatus::Cooked);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedAssets_ALoadComposesOnce,
    "CkTests.UnitTests.CkGroundNav.CookedAssets.ALoadComposesOnce",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedAssets_ALoadComposesOnce::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedassets;

    auto Baked = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Baked)))
    { return false; }

    auto Tiles = Make_CookedTilesFor(Baked);
    auto* Index = Make_CookedIndexFor(Baked, Tiles);

    if (NOT TestTrue(TEXT("the cooked index asset was created"), ck::IsValid(Index)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};

    const auto Status = Try_LoadCookedField(
        *Index, kFixtureLevelPackage, kFixtureCookKey, Baked._Params, kFixtureInputFingerprint, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("the cooked field loads [%s]"),
        *Get_CookStatusName(Status)), Status == ECk_GroundNav_CookStatus::Cooked))
    { return false; }

    // HOW MANY compositions ran is not observable — the serializer exposes no counter and inventing
    // one to be asserted would be the test writing the code it is testing. What IS observable is that
    // the ONE composition the tile-by-tile load defers to produces exactly the field a whole-field
    // blob's single composition does: the seam portals above all, which are the derived array a
    // per-tile composition would have rebuilt N times and kept only the last answer of.
    auto WholeFieldBlob = TArray<uint8>{};
    Write_Field(Baked, WholeFieldBlob);

    auto ReadWhole = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the whole-field blob reads back"),
        Read_Field(WholeFieldBlob, ReadWhole) == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    TestEqual(TEXT("the deferred-composition load derives the same number of seam portals"),
        Loaded._SeamPortals.Num(), ReadWhole._SeamPortals.Num());

    // The open bodies are the one array the two forms legitimately differ in: a whole-field blob
    // carries the bake's report and a per-tile one carries none.
    ReadWhole._OpenBodies.Reset();

    const auto Difference = Get_FirstFieldDifference(
        ReadWhole, Loaded, EPolicyComparison::Include, EEpochComparison::Exclude);

    TestTrue(FString::Printf(TEXT("and every other derived array with it [%s]"), *Difference),
        Difference.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------
