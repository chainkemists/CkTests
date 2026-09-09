// What a field survives being written down and read back, and what a reader answers when it cannot.
//
// The round trip is pinned against the SHARED field comparator rather than against a byte compare of
// the two fields: these structures carry doubles beside int32s, so they have padding a byte compare
// would read, and padding is not a value anything set. The BLOB is the thing compared byte for byte,
// and only where two writes of one field must agree.

#include "CkGroundNav/Bake/CkGroundNav_MarkupTypes.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Field/CkGroundNav_FieldStreaming.h"
#include "CkGroundNav/Field/CkGroundNav_FieldTypes.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkShapes/Box/CkShapeBox_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include "Test_GroundNav_FieldEquality.h"
#include "Test_GroundNav_QueryFixtures.h"

#include <CoreMinimal.h>
#include <GameplayTagContainer.h>
#include <Misc/ScopeExit.h>
#include <NativeGameplayTags.h>
#include <UObject/Class.h>

#include <Engine/World.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

namespace ck_test_groundnav_serialization
{
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_StreamFieldBundle;
    using ck::groundnav::FCk_GroundNav_StreamTileTransition;
    using ck::groundnav::FCk_GroundNav_TileCoord;
    using ck::groundnav::FCk_GroundNav_VolumeId;
    namespace world_fields = ck::groundnav::world_fields;

    constexpr auto kStreamingVolumeValue = 7;

    struct FStreamingRegistryFixture
    {
        UWorld* _World = nullptr;
        FCk_Handle _WorldEntity;
        FCk_Handle _Owner;
    };

    auto Bake_DistinctStreamingSource(FCk_GroundNav_StreamFieldBundle& OutBundle) -> bool;
    auto Make_StreamingRegistryFixture(const TCHAR* InWorldName) -> FStreamingRegistryFixture;
    auto Get_IsReady(const FStreamingRegistryFixture& InFixture) -> bool;
    auto Destroy_StreamingRegistryFixture(FStreamingRegistryFixture& InFixture) -> void;
    auto Make_EmptyStreamingBundleLike(const FCk_GroundNav_StreamFieldBundle& InReference) -> FCk_GroundNav_StreamFieldBundle;
    auto Make_ReplaceTransitions(const FCk_GroundNav_StreamFieldBundle& InSource,
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> TArray<FCk_GroundNav_StreamTileTransition>;
    auto Make_RemoveTransitions(const TArray<FCk_GroundNav_TileCoord>& InCoords)
        -> TArray<FCk_GroundNav_StreamTileTransition>;
    auto Get_SnapshotHasBuiltTiles(const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InSnapshot,
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> bool;
    auto SnapshotHasTileBuiltState(const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InSnapshot,
        const FCk_GroundNav_TileCoord& InCoord, bool InExpectedBuilt) -> bool;
    auto Get_SnapshotPointersAndEpochMatch(const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InLhs,
        const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InRhs) -> bool;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingInvokerRegistry_UpsertIsAtomic,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Invoker.Registry.UpsertIsAtomic",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingInvokerRegistry_UpsertIsAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }
    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingInvokerUpsert"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    if (NOT TestEqual(TEXT("the invoker owner registers"), Registered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    const auto Coords = TArray<FCk_GroundNav_TileCoord>{
        FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{1, 1}};
    const auto Before = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    const auto Upserted = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source, Make_ReplaceTransitions(Source, Coords), Coords);
    if (NOT TestEqual(TEXT("one source upsert publishes all profiles together"), Upserted._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto After = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("upsert produces a public all-profile snapshot"), After.IsSet() &&
        Get_SnapshotHasBuiltTiles(*After, Coords)))
    { return false; }
    TestTrue(TEXT("an actual upsert replaces the immutable publication"),
        Before.IsSet() && After->_DefaultField != Before->_DefaultField && After->_Epoch.Get_IsNewerThan(Before->_Epoch));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingInvokerRegistry_ExactMaskRetainsDisabledTiles,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Invoker.Registry.ExactMaskRetainsDisabledTiles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingInvokerRegistry_ExactMaskRetainsDisabledTiles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }
    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingInvokerMask"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    const auto CoordA = FCk_GroundNav_TileCoord{0, 0};
    const auto CoordB = FCk_GroundNav_TileCoord{0, 1};
    const auto Coords = TArray<FCk_GroundNav_TileCoord>{CoordA, CoordB};
    const auto Masked = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source, Make_ReplaceTransitions(Source, Coords),
        TArray<FCk_GroundNav_TileCoord>{CoordA});
    if (NOT TestEqual(TEXT("the exact mask publishes its enabled coordinate"), Masked._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto MaskedSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("the omitted coordinate is unbuilt in every profile"), MaskedSnapshot.IsSet() &&
        SnapshotHasTileBuiltState(*MaskedSnapshot, CoordA, true) && SnapshotHasTileBuiltState(*MaskedSnapshot, CoordB, false)))
    { return false; }

    const auto Reenabled = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source,
        TArray<FCk_GroundNav_StreamTileTransition>{}, Coords);
    if (NOT TestEqual(TEXT("re-enabling a retained coordinate publishes without a replacement blob"), Reenabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto ReenabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("the retained coordinate re-enables in every profile"), ReenabledSnapshot.IsSet() &&
        Get_SnapshotHasBuiltTiles(*ReenabledSnapshot, Coords)))
    { return false; }

    const auto Purged = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source,
        Make_RemoveTransitions(TArray<FCk_GroundNav_TileCoord>{CoordB}),
        TArray<FCk_GroundNav_TileCoord>{CoordA});
    if (NOT TestEqual(TEXT("a remove transition purges its coordinate from publication"), Purged._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto PurgedSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestTrue(TEXT("a purged coordinate remains unbuilt in every profile"), PurgedSnapshot.IsSet() &&
        SnapshotHasTileBuiltState(*PurgedSnapshot, CoordB, false));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingInvokerRegistry_ForeignOwnershipRefuses,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Invoker.Registry.ForeignOwnershipRefuses",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingInvokerRegistry_ForeignOwnershipRefuses::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }
    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingInvokerForeign"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    const auto Coord = FCk_GroundNav_TileCoord{0, 0};
    const auto Foreign = world_fields::Load_StreamSource(
        Fixture._World, VolumeId, Make_ReplaceTransitions(Source, TArray<FCk_GroundNav_TileCoord>{Coord}));
    if (NOT TestEqual(TEXT("the distinct source claims its coordinate"), Foreign._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto Before = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    const auto Refused = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source,
        Make_ReplaceTransitions(Source, TArray<FCk_GroundNav_TileCoord>{Coord}),
        TArray<FCk_GroundNav_TileCoord>{});
    TestEqual(TEXT("an owner-reserved source cannot claim a foreign coordinate"), Refused._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::CoordinateAlreadyOwned);
    const auto After = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestTrue(TEXT("foreign ownership refusal retains every pointer and epoch"),
        Before.IsSet() && After.IsSet() && Get_SnapshotPointersAndEpochMatch(*After, *Before));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingInvokerRegistry_InvalidInputDoesNotMutate,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Invoker.Registry.InvalidInputDoesNotMutate",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingInvokerRegistry_InvalidInputDoesNotMutate::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }
    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingInvokerInvalid"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    const auto Coord = FCk_GroundNav_TileCoord{0, 0};
    const auto Loaded = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source,
        Make_ReplaceTransitions(Source, TArray<FCk_GroundNav_TileCoord>{Coord}),
        TArray<FCk_GroundNav_TileCoord>{Coord});
    if (NOT TestEqual(TEXT("the baseline source tile publishes"), Loaded._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto Before = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    auto Corrupt = Make_ReplaceTransitions(Source, TArray<FCk_GroundNav_TileCoord>{Coord});
    Corrupt[0]._DefaultBlob.SetNum(1);
    AddExpectedError(TEXT("GroundNav stream upsert requires valid all-profile replacement blobs"),
        EAutomationExpectedErrorFlags::Contains, 2);
    const auto Refused = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source, Corrupt,
        TArray<FCk_GroundNav_TileCoord>{Coord});
    TestEqual(TEXT("a corrupt all-profile replacement refuses atomically"), Refused._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::CompositionRefused);
    const auto After = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestTrue(TEXT("invalid input leaves every pointer and epoch unchanged"),
        Before.IsSet() && After.IsSet() && Get_SnapshotPointersAndEpochMatch(*After, *Before));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingInvokerRegistry_NoOpIsStable,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Invoker.Registry.NoOpIsStable",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingInvokerRegistry_NoOpIsStable::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }
    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingInvokerNoOp"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    const auto Coords = TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{0, 0}};
    const auto Replacements = Make_ReplaceTransitions(Source, Coords);
    const auto Published = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source, Replacements, Coords);
    if (NOT TestEqual(TEXT("the first upsert publishes"), Published._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto Before = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    const auto NoOp = world_fields::Upsert_StreamSourceTiles(
        Fixture._World, VolumeId, Registered._Source, Replacements, Coords);
    TestEqual(TEXT("an identical transaction is a no-op"), NoOp._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::NoChange);
    const auto After = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestTrue(TEXT("a no-op retains every pointer and epoch"),
        Before.IsSet() && After.IsSet() && Get_SnapshotPointersAndEpochMatch(*After, *Before));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

// Two tags whose names sort Alpha before Zulu whichever order they are authored in, which is what the
// table-order pin reads. A third name of the SAME BYTE LENGTH as the first is what the unknown-tag pin
// overwrites it with, so the blob stays structurally intact and only the name stops resolving.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Serialization_AreaAlpha, "CkTests.GroundNav.Serialization.AreaAlpha");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Serialization_AreaZulu, "CkTests.GroundNav.Serialization.AreaZulu");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_Serialization_AreaBeta, "CkTests.GroundNav.Serialization.AreaBeta");

namespace ck_test_groundnav_serialization
{
    using ck::groundnav::FCk_GroundNav_Field;
    using ck::groundnav::FCk_GroundNav_FieldParams;
    using ck::groundnav::FCk_GroundNav_FieldPtr;
    using ck::groundnav::FCk_GroundNav_StreamFieldBundle;
    using ck::groundnav::FCk_GroundNav_StreamTileId;
    using ck::groundnav::FCk_GroundNav_StreamTileTransition;
    using ck::groundnav::FCk_GroundNav_TileCoord;
    using ck::groundnav::FCk_GroundNav_VolumeId;
    using ck::groundnav::Compose_LoadedField;
    using ck::groundnav::Compose_StreamTileTransitions;
    using ck::groundnav::ECk_GroundNav_ComposeOnLoad;
    using ck::groundnav::ECk_GroundNav_StreamCompositionStatus;
    using ck::groundnav::ECk_GroundNav_StreamTileTransitionKind;
    using ck::groundnav::Get_TileCoord;
    using ck::groundnav::Get_TileIndex;
    using ck::groundnav::Read_Field;
    using ck::groundnav::Read_TagTable;
    using ck::groundnav::Read_TileInto;
    using ck::groundnav::Write_Field;
    using ck::groundnav::Write_FieldSubset;
    using ck::groundnav::Write_Tile;
    using ck::groundnav::kFieldBlobCookSecondsOffset;

    namespace world_fields = ck::groundnav::world_fields;

    using ck_test_groundnav_field_equality::EPolicyComparison;
    using ck_test_groundnav_field_equality::Get_FirstFieldDifference;
    using ck_test_groundnav_field_equality::Get_FirstParamsDifference;
    using ck_test_groundnav_field_equality::Get_TilesEqual;

    using ck_test_groundnav_queryfixtures::Bake;
    using ck_test_groundnav_queryfixtures::Make_FlatParams;
    using ck_test_groundnav_queryfixtures::Make_FlatScene;
    using ck_test_groundnav_queryfixtures::Make_QueryParams;
    using ck_test_groundnav_queryfixtures::Make_QueryScene;
    using ck_test_groundnav_queryfixtures::kGroundZ;

    constexpr auto kAlphaTagName = TEXT("CkTests.GroundNav.Serialization.AreaAlpha");

    // Same byte length as the name above, and deliberately not a tag anything registers.
    constexpr auto kUnregisteredTagName = TEXT("CkTests.GroundNav.Serialization.AreaOmega");

    // --------------------------------------------------------------------------------------------------

    auto Get_StatusName(ECk_GroundNav_LoadStatus InStatus) -> FString
    {
        return StaticEnum<ECk_GroundNav_LoadStatus>()->GetNameStringByValue(static_cast<int64>(InStatus));
    }

    /** A field of the given lattice with every tile present, carrying its coord, and Unbuilt. */
    auto Make_EmptyFieldLike(
        const FCk_GroundNav_FieldParams& InParams) -> FCk_GroundNav_Field
    {
        auto Field = FCk_GroundNav_Field{};

        Field._Params = InParams;
        Field._Tiles.SetNum(InParams.Get_TileCount());

        for (auto TileIndex = 0; TileIndex < Field._Tiles.Num(); ++TileIndex)
        { Field._Tiles[TileIndex]._Coord = Get_TileCoord(InParams._Divisions, TileIndex); }

        return Field;
    }

    auto Make_Link(
        int32               InId,
        const FVector&      InStart,
        const FVector&      InEnd,
        const FGameplayTag& InUserTypeTag) -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{InId, InStart, InEnd};
        Record.Set_UserTypeTag(InUserTypeTag);

        return Record;
    }

    auto Bake_FlatSceneWithLinks(
        const TArray<FCk_GroundNav_LinkRecord>& InLinks,
        FCk_GroundNav_Field&                    OutField) -> bool
    {
        auto Params = Make_FlatParams();
        Params._Links = InLinks;

        return Bake(Make_FlatScene(), Params, OutField);
    }

    // Every member of the params below is moved OFF its default, which is what makes the round trip
    // evidence: a default that survives says nothing about whether the writer wrote it.
    constexpr auto kAuthoredMaxColumnsPerTile = 131072;
    constexpr auto kAuthoredPlaneFitToleranceUu = 3.5f;
    constexpr auto kAuthoredNormalConeDegrees = 12.5f;
    constexpr auto kAuthoredMaxClearanceUu = 175.0f;

    // Far outside the fixture's floor, and a value whose eight bytes appear nowhere else in the blob:
    // the corrupt-transform pin finds the markup's translation by searching for exactly this number.
    constexpr auto kAuthoredMarkupCentreX = 12345.5;

    auto Make_AuthoredMarkup() -> FCk_GroundNav_MarkupRecord
    {
        auto Record = FCk_GroundNav_MarkupRecord{
            7,
            FCk_AnyShape{FCk_ShapeBox_Dimensions{FVector{120.0, 80.0, 40.0}}},
            FTransform{FRotator{0.0, 30.0, 0.0}, FVector{kAuthoredMarkupCentreX, 250.0, 15.0}, FVector{2.0}},
            ECk_GroundNav_MarkupKind::Cost};

        Record.Set_AreaTag(TAG_CkTests_GroundNav_Serialization_AreaAlpha);
        Record.Set_Enable(ECk_EnableDisable::Enable);
        Record.Set_CostMultiplier(2.5f);
        Record.Set_RequestedAtEpoch(11);

        return Record;
    }

    auto Make_AuthoredLink() -> FCk_GroundNav_LinkRecord
    {
        auto Record = FCk_GroundNav_LinkRecord{
            3, FVector{200.0, 200.0, kGroundZ}, FVector{600.0, 200.0, kGroundZ}};

        Record.Set_Direction(ECk_GroundNav_LinkDirection::Forward);
        Record.Set_CostMultiplierForward(1.75f);
        Record.Set_CostMultiplierBackward(2.25f);
        Record.Set_ClearanceUu(65.0f);
        Record.Set_AreaTag(TAG_CkTests_GroundNav_Serialization_AreaAlpha);
        Record.Set_UserTypeTag(TAG_CkTests_GroundNav_Serialization_AreaZulu);
        Record.Set_Enable(ECk_EnableDisable::Enable);
        Record.Set_ProjectionMode(ECk_NavSurface_ProjectionMode::Down);
        Record.Set_ProjectionHorizontalExtentUu(75.0f);
        Record.Set_ProjectionVerticalExtentUu(125.0f);
        Record.Set_RequestedAtEpoch(13);

        return Record;
    }

    auto Make_AuthoredParams() -> FCk_GroundNav_FieldParams
    {
        auto Params = Make_FlatParams();

        Params._Config.Set_MaxColumnsPerTile(kAuthoredMaxColumnsPerTile);
        Params._MergeTunables = FCk_GroundNav_MergeTunables{
            kAuthoredPlaneFitToleranceUu, kAuthoredNormalConeDegrees};
        Params._MaxClearanceUu = kAuthoredMaxClearanceUu;
        Params._MarkupRecords = TArray<FCk_GroundNav_MarkupRecord>{Make_AuthoredMarkup()};
        Params._Links = TArray<FCk_GroundNav_LinkRecord>{Make_AuthoredLink()};

        return Params;
    }

    /**
     * A quiet NaN, spelled by its bits rather than computed.
     *
     * What a corrupt blob holds is a bit pattern, and arithmetic that produces one is at the mercy of
     * whatever the compiler decides to fold.
     */
    auto Get_NotANumber() -> double
    {
        constexpr auto QuietNaNBits = uint64{0x7FF8000000000000};

        auto Value = 0.0;
        FMemory::Memcpy(&Value, &QuietNaNBits, sizeof(Value));

        return Value;
    }

    /** Overwrite the first occurrence of one eight-byte double in a blob with another. */
    auto Do_ReplaceDouble(
        TArray<uint8>& InOutBlob,
        double         InFrom,
        double         InTo) -> bool
    {
        constexpr auto Width = static_cast<int32>(sizeof(double));

        auto FromBytes = TArray<uint8>{};
        auto ToBytes = TArray<uint8>{};

        FromBytes.SetNumZeroed(Width);
        ToBytes.SetNumZeroed(Width);

        FMemory::Memcpy(FromBytes.GetData(), &InFrom, Width);
        FMemory::Memcpy(ToBytes.GetData(), &InTo, Width);

        for (auto Index = 0; (Index + Width) <= InOutBlob.Num(); ++Index)
        {
            if (FMemory::Memcmp(&InOutBlob[Index], FromBytes.GetData(), Width) != 0)
            { continue; }

            FMemory::Memcpy(&InOutBlob[Index], ToBytes.GetData(), Width);
            return true;
        }

        return false;
    }

    /** Overwrite the first occurrence of one UTF-8 string in a blob with another of the same length. */
    auto Do_ReplaceBytes(
        TArray<uint8>& InOutBlob,
        const FString& InFrom,
        const FString& InTo) -> bool
    {
        const auto From = FTCHARToUTF8{*InFrom};
        const auto To = FTCHARToUTF8{*InTo};

        const auto Length = static_cast<int32>(From.Length());

        if (Length == 0 || Length != static_cast<int32>(To.Length()))
        { return false; }

        const auto* FromBytes = reinterpret_cast<const uint8*>(From.Get());
        const auto* ToBytes = reinterpret_cast<const uint8*>(To.Get());

        for (auto Index = 0; (Index + Length) <= InOutBlob.Num(); ++Index)
        {
            if (FMemory::Memcmp(&InOutBlob[Index], FromBytes, Length) != 0)
            { continue; }

            FMemory::Memcpy(&InOutBlob[Index], ToBytes, Length);
            return true;
        }

        return false;
    }

    /** Every byte of two blobs but the header's cook date, which is the one run they may differ in. */
    auto Get_BlobsMatchOutsideTheCookDate(
        const TArray<uint8>& InLeft,
        const TArray<uint8>& InRight) -> bool
    {
        if (InLeft.Num() != InRight.Num())
        { return false; }

        for (auto Index = 0; Index < InLeft.Num(); ++Index)
        {
            const auto IsCookDate = Index >= kFieldBlobCookSecondsOffset &&
                                    Index < (kFieldBlobCookSecondsOffset + static_cast<int32>(sizeof(int64)));

            if (IsCookDate)
            { continue; }

            if (InLeft[Index] != InRight[Index])
            { return false; }
        }

        return true;
    }

    // The registry is keyed by a real UWorld and its owner validity gate resolves a real ECS handle.
    // Keeping both in this fixture means every row reaches the production map, rather than a local
    // composition helper that could never observe registration, teardown, or world cleanup.
    auto Make_StreamingRegistryFixture(const TCHAR* InWorldName) -> FStreamingRegistryFixture
    {
        constexpr auto InformEngineOfWorld = false;

        auto Fixture = FStreamingRegistryFixture{};
        Fixture._World = UWorld::CreateWorld(EWorldType::Game, InformEngineOfWorld, FName{InWorldName});

        if (Fixture._World == nullptr)
        { return Fixture; }

        Fixture._WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Fixture._World);

        if (ck::Is_NOT_Valid(Fixture._WorldEntity))
        { return Fixture; }

        Fixture._Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture._WorldEntity);
        return Fixture;
    }

    auto Get_IsReady(const FStreamingRegistryFixture& InFixture) -> bool
    {
        return InFixture._World != nullptr &&
               ck::IsValid(InFixture._WorldEntity) &&
               ck::IsValid(InFixture._Owner);
    }

    auto Destroy_StreamingRegistryFixture(FStreamingRegistryFixture& InFixture) -> void
    {
        constexpr auto InformEngineOfWorld = false;

        if (InFixture._World != nullptr)
        { InFixture._World->DestroyWorld(InformEngineOfWorld); }

        InFixture._World = nullptr;
    }

    auto Get_SnapshotHasBuiltTiles(
        const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InSnapshot,
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> bool
    {
        const auto HasTiles = [&InCoords](const FCk_GroundNav_FieldPtr& InField, bool InExpectedBuilt) -> bool
        {
            if (NOT InField.IsValid()) { return false; }

            for (const auto& Coord : InCoords)
            {
                const auto* Tile = InField->Get_Tile(Coord);
                if (Tile == nullptr || Tile->Get_IsBuilt() != InExpectedBuilt) { return false; }
            }

            return true;
        };

        const auto* Alpha = InSnapshot._VariantFields.Find(TAG_CkTests_GroundNav_Serialization_AreaAlpha);
        const auto* Zulu = InSnapshot._VariantFields.Find(TAG_CkTests_GroundNav_Serialization_AreaZulu);
        return Alpha != nullptr && Zulu != nullptr &&
               HasTiles(InSnapshot._DefaultField, true) && HasTiles(*Alpha, true) && HasTiles(*Zulu, true);
    }

    auto Get_SnapshotHasUnbuiltTiles(
        const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InSnapshot,
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> bool
    {
        const auto HasTiles = [&InCoords](const FCk_GroundNav_FieldPtr& InField) -> bool
        {
            if (NOT InField.IsValid()) { return false; }

            for (const auto& Coord : InCoords)
            {
                const auto* Tile = InField->Get_Tile(Coord);
                if (Tile == nullptr || Tile->Get_IsBuilt()) { return false; }
            }

            return true;
        };

        const auto* Alpha = InSnapshot._VariantFields.Find(TAG_CkTests_GroundNav_Serialization_AreaAlpha);
        const auto* Zulu = InSnapshot._VariantFields.Find(TAG_CkTests_GroundNav_Serialization_AreaZulu);
        return Alpha != nullptr && Zulu != nullptr &&
               HasTiles(InSnapshot._DefaultField) && HasTiles(*Alpha) && HasTiles(*Zulu);
    }

    auto SnapshotHasTileBuiltState(
        const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InSnapshot,
        const FCk_GroundNav_TileCoord& InCoord,
        bool InExpectedBuilt) -> bool
    {
        const auto HasState = [&InCoord, InExpectedBuilt](const FCk_GroundNav_FieldPtr& InField) -> bool
        {
            const auto* Tile = InField.IsValid() ? InField->Get_Tile(InCoord) : nullptr;
            return Tile != nullptr && Tile->Get_IsBuilt() == InExpectedBuilt;
        };

        if (NOT HasState(InSnapshot._DefaultField))
        { return false; }
        for (const auto& Variant : InSnapshot._VariantFields)
        {
            if (NOT HasState(Variant.Value))
            { return false; }
        }
        return true;
    }

    auto Set_BundleTileTriangleCount(
        FCk_GroundNav_StreamFieldBundle& InOutBundle,
        const FCk_GroundNav_TileCoord& InCoord,
        int32 InTriangleCount) -> void
    {
        const auto SetCount = [&InCoord, InTriangleCount](FCk_GroundNav_Field& InOutField) -> void
        {
            const auto TileIndex = Get_TileIndex(InOutField._Params._Divisions, InCoord);
            InOutField._Tiles[TileIndex]._BakeStats._SourceTriangleCount = InTriangleCount;
        };

        SetCount(InOutBundle._DefaultField);
        for (auto& Variant : InOutBundle._VariantFields)
        { SetCount(Variant.Value); }
    }

    auto SnapshotHasTileTriangleCount(
        const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InSnapshot,
        const FCk_GroundNav_TileCoord& InCoord,
        int32 InTriangleCount) -> bool
    {
        const auto HasCount = [&InCoord, InTriangleCount](const FCk_GroundNav_FieldPtr& InField) -> bool
        {
            const auto* Tile = InField.IsValid() ? InField->Get_Tile(InCoord) : nullptr;
            return Tile != nullptr && Tile->Get_IsBuilt() &&
                   Tile->_BakeStats._SourceTriangleCount == InTriangleCount;
        };

        if (NOT HasCount(InSnapshot._DefaultField))
        { return false; }

        for (const auto& Variant : InSnapshot._VariantFields)
        {
            if (NOT HasCount(Variant.Value))
            { return false; }
        }

        return true;
    }

    auto Get_SnapshotPointersAndEpochMatch(
        const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InLhs,
        const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InRhs) -> bool
    {
        if (InLhs._DefaultField != InRhs._DefaultField || InLhs._Epoch != InRhs._Epoch ||
            InLhs._VariantFields.Num() != InRhs._VariantFields.Num())
        { return false; }

        for (const auto& [Tag, Field] : InLhs._VariantFields)
        {
            const auto* Other = InRhs._VariantFields.Find(Tag);
            if (Other == nullptr || *Other != Field)
            { return false; }
        }

        return true;
    }

    auto Get_FirstBundleDifference(
        const FCk_GroundNav_StreamFieldBundle& InLhs,
        const FCk_GroundNav_StreamFieldBundle& InRhs) -> FString
    {
        const auto DefaultDifference = Get_FirstFieldDifference(
            InLhs._DefaultField, InRhs._DefaultField, EPolicyComparison::Include);

        if (NOT DefaultDifference.IsEmpty())
        { return FString::Printf(TEXT("_DefaultField%s"), *DefaultDifference); }

        if (InLhs._VariantFields.Num() != InRhs._VariantFields.Num())
        { return FString::Printf(TEXT("_VariantFields count %d vs %d"), InLhs._VariantFields.Num(), InRhs._VariantFields.Num()); }

        for (const auto& [Tag, LeftField] : InLhs._VariantFields)
        {
            const auto* RightField = InRhs._VariantFields.Find(Tag);

            if (RightField == nullptr)
            { return FString::Printf(TEXT("_VariantFields is missing %s"), *Tag.ToString()); }

            const auto Difference = Get_FirstFieldDifference(LeftField, *RightField, EPolicyComparison::Include);

            if (NOT Difference.IsEmpty())
            { return FString::Printf(TEXT("_VariantFields[%s]%s"), *Tag.ToString(), *Difference); }
        }

        return {};
    }

    auto Make_EmptyStreamingBundleLike(
        const FCk_GroundNav_StreamFieldBundle& InReference) -> FCk_GroundNav_StreamFieldBundle
    {
        auto Bundle = FCk_GroundNav_StreamFieldBundle{};

        Bundle._DefaultField = Make_EmptyFieldLike(InReference._DefaultField._Params);

        for (const auto& [Tag, Field] : InReference._VariantFields)
        { Bundle._VariantFields.Add(Tag, Make_EmptyFieldLike(Field._Params)); }

        return Bundle;
    }

    auto Make_WholeStreamingBundle(
        const FCk_GroundNav_Field& InDefaultField,
        const FCk_GroundNav_Field& InAlphaField,
        const FCk_GroundNav_Field& InZuluField) -> FCk_GroundNav_StreamFieldBundle
    {
        auto Bundle = FCk_GroundNav_StreamFieldBundle{};

        Bundle._DefaultField = InDefaultField;
        Bundle._VariantFields.Add(TAG_CkTests_GroundNav_Serialization_AreaAlpha, InAlphaField);
        Bundle._VariantFields.Add(TAG_CkTests_GroundNav_Serialization_AreaZulu, InZuluField);

        return Bundle;
    }

    auto Bake_DistinctStreamingSource(
        FCk_GroundNav_StreamFieldBundle& OutBundle) -> bool
    {
        auto DefaultField = FCk_GroundNav_Field{};

        if (NOT Bake(Make_QueryScene(), Make_QueryParams(), DefaultField))
        { return false; }

        auto AlphaParams = Make_QueryParams();
        AlphaParams._Profile.Set_LedgeSensitivity(0.5f);

        auto AlphaField = FCk_GroundNav_Field{};

        if (NOT Bake(Make_QueryScene(), AlphaParams, AlphaField))
        { return false; }

        OutBundle = Make_WholeStreamingBundle(DefaultField, AlphaField, DefaultField);
        return true;
    }

    auto Get_AreBundleTilesBuilt(
        const FCk_GroundNav_StreamFieldBundle& InBundle,
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> bool
    {
        const auto AreBuilt = [&InCoords](const FCk_GroundNav_Field& InField) -> bool
        {
            for (const auto& Coord : InCoords)
            {
                const auto* Tile = InField.Get_Tile(Coord);

                if (Tile == nullptr || NOT Tile->Get_IsBuilt())
                { return false; }
            }

            return true;
        };

        if (NOT AreBuilt(InBundle._DefaultField))
        { return false; }

        for (const auto& [Tag, Field] : InBundle._VariantFields)
        {
            if (NOT AreBuilt(Field))
            { return false; }
        }

        return true;
    }

    auto Make_ReplaceTransitions(
        const FCk_GroundNav_StreamFieldBundle& InSource,
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> TArray<FCk_GroundNav_StreamTileTransition>
    {
        auto Transitions = TArray<FCk_GroundNav_StreamTileTransition>{};

        for (const auto& Coord : InCoords)
        {
            auto Transition = FCk_GroundNav_StreamTileTransition{};
            Transition._TileId = FCk_GroundNav_StreamTileId{FCk_GroundNav_VolumeId{kStreamingVolumeValue}, Coord};
            Transition._Kind = ECk_GroundNav_StreamTileTransitionKind::Replace;
            Write_Tile(InSource._DefaultField, Coord, Transition._DefaultBlob);

            for (const auto& [Tag, Field] : InSource._VariantFields)
            { Write_Tile(Field, Coord, Transition._VariantBlobs.Add(Tag)); }

            Transitions.Emplace(MoveTemp(Transition));
        }

        return Transitions;
    }

    auto Make_RemoveTransitions(
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> TArray<FCk_GroundNav_StreamTileTransition>
    {
        auto Transitions = TArray<FCk_GroundNav_StreamTileTransition>{};

        for (const auto& Coord : InCoords)
        {
            auto Transition = FCk_GroundNav_StreamTileTransition{};
            Transition._TileId = FCk_GroundNav_StreamTileId{FCk_GroundNav_VolumeId{kStreamingVolumeValue}, Coord};
            Transition._Kind = ECk_GroundNav_StreamTileTransitionKind::Remove;
            Transitions.Emplace(MoveTemp(Transition));
        }

        return Transitions;
    }

    auto Make_OracleBundle(
        const FCk_GroundNav_StreamFieldBundle& InSource,
        const TArray<FCk_GroundNav_TileCoord>& InCoords) -> FCk_GroundNav_StreamFieldBundle
    {
        auto Oracle = Make_EmptyStreamingBundleLike(InSource);

        const auto LoadTiles = [&InCoords](const FCk_GroundNav_Field& InSourceField,
            FCk_GroundNav_Field& OutField) -> void
        {
            for (const auto& Coord : InCoords)
            {
                auto Blob = TArray<uint8>{};
                Write_Tile(InSourceField, Coord, Blob);
                Read_TileInto(Blob, OutField, ECk_GroundNav_ComposeOnLoad::Deferred);
            }

            Compose_LoadedField(OutField);
        };

        LoadTiles(InSource._DefaultField, Oracle._DefaultField);

        for (const auto& [Tag, Field] : InSource._VariantFields)
        { LoadTiles(Field, Oracle._VariantFields.FindChecked(Tag)); }

        return Oracle;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_WholeFieldRoundTripsThroughTheComparator,
    "CkTests.UnitTests.CkGroundNav.Serialization.WholeFieldRoundTripsThroughTheComparator",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_WholeFieldRoundTripsThroughTheComparator::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the field writes to a non-empty blob"), Blob.Num() > 0))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("the blob reads back [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    // Every derived array in the loaded field was re-derived, never read, so this compares the derives
    // against themselves as much as it compares the tiles.
    const auto Difference = Get_FirstFieldDifference(Field, Loaded, EPolicyComparison::Include);

    TestTrue(FString::Printf(TEXT("the loaded field equals the baked one [%s]"), *Difference), Difference.IsEmpty());

    TestEqual(TEXT("and holds the same number of tiles"), Loaded._Tiles.Num(), Field._Tiles.Num());

    TestTrue(TEXT("and the same params divisions"), Loaded._Params._Divisions == Field._Params._Divisions);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_ParamsRoundTripEveryMember,
    "CkTests.UnitTests.CkGroundNav.Serialization.ParamsRoundTripEveryMember",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_ParamsRoundTripEveryMember::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes under fully authored params"),
        Bake(Make_FlatScene(), Make_AuthoredParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("the blob reads back [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    // The comparator names the member, so a writer that drops one says which one it dropped.
    const auto Difference = Get_FirstParamsDifference(Field._Params, Loaded._Params);

    TestTrue(FString::Printf(TEXT("every params member survives the round trip [%s]"), *Difference),
        Difference.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_CorruptTransformIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.CorruptTransformIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_CorruptTransformIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes under fully authored params"),
        Bake(Make_FlatScene(), Make_AuthoredParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    // A NaN where the markup's transform carries its X. Nothing downstream would catch it: a bound
    // built from it compares false against every point tested against it, and the field would simply
    // stop deciding anything there without a reader ever being told.
    if (NOT TestTrue(TEXT("the markup's translation is in the blob and can be overwritten"),
        Do_ReplaceDouble(Blob, kAuthoredMarkupCentreX, Get_NotANumber())))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a non-finite transform is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Corrupt);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    TestEqual(TEXT("including its records"), Loaded._Params._MarkupRecords.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_TileRoundTripEqualsTheWholeFieldsTile,
    "CkTests.UnitTests.CkGroundNav.Serialization.TileRoundTripEqualsTheWholeFieldsTile",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_TileRoundTripEqualsTheWholeFieldsTile::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Field)))
    { return false; }

    const auto Coord = FCk_GroundNav_TileCoord{1, 0};
    const auto TileIndex = Get_TileIndex(Field._Params._Divisions, Coord);

    if (NOT TestTrue(TEXT("the field has the tile the pin writes"), Field._Tiles.IsValidIndex(TileIndex)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Tile(Field, Coord, Blob);

    auto Target = Make_EmptyFieldLike(Field._Params);
    const auto Status = Read_TileInto(Blob, Target);

    if (NOT TestTrue(FString::Printf(TEXT("the tile blob reads into a field of the same lattice [%s]"),
        *Get_StatusName(Status)), Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    TestTrue(TEXT("the loaded tile equals the whole field's tile"),
        Get_TilesEqual(Field._Tiles[TileIndex], Target._Tiles[TileIndex], EPolicyComparison::Include));

    // The rest of the target is untouched, which is what makes a per-tile read a per-tile read.
    for (auto OtherIndex = 0; OtherIndex < Target._Tiles.Num(); ++OtherIndex)
    {
        if (OtherIndex == TileIndex)
        { continue; }

        TestTrue(FString::Printf(TEXT("tile %d stays unbuilt"), OtherIndex),
            Target._Tiles[OtherIndex]._Status == ECk_GroundNav_BuildStatus::Unbuilt);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_SubsetDropsPortalsAndLinksTouchingAbsentTiles,
    "CkTests.UnitTests.CkGroundNav.Serialization.SubsetDropsPortalsAndLinksTouchingAbsentTiles",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_SubsetDropsPortalsAndLinksTouchingAbsentTiles::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    // A link with one end on the tile the subset keeps and the other on a tile it leaves out, so the
    // resolution has something to lose.
    auto Params = Make_QueryParams();
    Params._Links = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, FVector{200.0, 200.0, kGroundZ}, FVector{1200.0, 200.0, kGroundZ},
            TAG_CkTests_GroundNav_Serialization_AreaAlpha)};

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Params, Field)))
    { return false; }

    if (NOT TestTrue(TEXT("the whole field has crossings between its tiles"), Field.Get_SeamPortalCount() > 0))
    { return false; }

    // The drop only means something if the link reached both tiles to begin with.
    if (NOT TestTrue(TEXT("and the authored link resolves on the whole field"),
        Field._ResolvedLinks.Num() == 1 && Field._ResolvedLinks[0].Get_IsResolved()))
    { return false; }

    const auto KeptTiles = TArray<FCk_GroundNav_TileCoord>{
        FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1}};

    auto Blob = TArray<uint8>{};
    Write_FieldSubset(Field, KeptTiles, Blob);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    if (NOT TestTrue(FString::Printf(TEXT("the subset reads back [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    if (NOT TestEqual(TEXT("the subset keeps the whole lattice"), Loaded._Tiles.Num(), Field._Tiles.Num()))
    { return false; }

    auto IsKept = TArray<bool>{};
    IsKept.Init(false, Loaded._Tiles.Num());

    for (const auto& Coord : KeptTiles)
    {
        const auto KeptIndex = Get_TileIndex(Field._Params._Divisions, Coord);

        if (IsKept.IsValidIndex(KeptIndex))
        { IsKept[KeptIndex] = true; }
    }

    for (auto TileIndex = 0; TileIndex < Loaded._Tiles.Num(); ++TileIndex)
    {
        if (IsKept[TileIndex])
        {
            TestTrue(FString::Printf(TEXT("kept tile %d equals the original's"), TileIndex),
                Get_TilesEqual(Field._Tiles[TileIndex], Loaded._Tiles[TileIndex], EPolicyComparison::Include));

            continue;
        }

        TestTrue(FString::Printf(TEXT("absent tile %d reads unbuilt"), TileIndex),
            Loaded._Tiles[TileIndex]._Status == ECk_GroundNav_BuildStatus::Unbuilt);

        TestEqual(FString::Printf(TEXT("absent tile %d holds no cells"), TileIndex),
            Loaded._Tiles[TileIndex]._SurfaceZ.Num(), 0);

        TestEqual(FString::Printf(TEXT("absent tile %d holds no plates"), TileIndex),
            Loaded._Tiles[TileIndex]._Plates._Plates.Num(), 0);
    }

    for (const auto& Portal : Loaded._SeamPortals)
    {
        TestTrue(TEXT("no seam portal names an absent tile"),
            IsKept.IsValidIndex(Portal._TileIndexA) && IsKept[Portal._TileIndexA] &&
            IsKept.IsValidIndex(Portal._TileIndexB) && IsKept[Portal._TileIndexB]);
    }

    if (NOT TestEqual(TEXT("the authored link survives the subset"), Loaded._ResolvedLinks.Num(), 1))
    { return false; }

    const auto& ResolvedLink = Loaded._ResolvedLinks[0];

    TestTrue(TEXT("the link end over an absent tile resolved to no plate"),
        ResolvedLink._EndFlatPlate == INDEX_NONE);

    TestTrue(TEXT("and the link is therefore counted unresolved"), Loaded.Get_UnresolvedLinkCount() > 0);

    for (const auto& Link : Loaded._ResolvedLinks)
    {
        const auto StartIsAnchored = Link._StartFlatPlate == INDEX_NONE ||
                                     (IsKept.IsValidIndex(Link._StartSurface._TileIndex) &&
                                      IsKept[Link._StartSurface._TileIndex]);

        const auto EndIsAnchored = Link._EndFlatPlate == INDEX_NONE ||
                                   (IsKept.IsValidIndex(Link._EndSurface._TileIndex) &&
                                    IsKept[Link._EndSurface._TileIndex]);

        TestTrue(TEXT("no resolved link holds a flat plate on an absent tile"), StartIsAnchored && EndIsAnchored);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_WrongVersionIsAStatusNotAnEnsure,
    "CkTests.UnitTests.CkGroundNav.Serialization.WrongVersionIsAStatusNotAnEnsure",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_WrongVersionIsAStatusNotAnEnsure::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake(Make_FlatScene(), Make_FlatParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the blob is long enough to carry a version"), Blob.Num() > 8))
    { return false; }

    // The format version's low byte, straight after the magic.
    Blob[4] = static_cast<uint8>(Blob[4] + 1);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a bumped version is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::WrongVersion);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    TestTrue(TEXT("including its params"), Loaded._Params._Divisions == FIntPoint{1, 1});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_TruncatedBlobIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.TruncatedBlobIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_TruncatedBlobIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the flat scene bakes"), Bake(Make_FlatScene(), Make_FlatParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the blob is long enough to halve"), Blob.Num() > 64))
    { return false; }

    // Half a blob still carries an intact magic and version, so what is being pinned is the body
    // running out rather than the header being refused.
    Blob.SetNum(Blob.Num() / 2);

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a half blob is refused as truncated [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::Truncated);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_UnknownTagOnLoadIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.UnknownTagOnLoadIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_UnknownTagOnLoadIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    const auto Links = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, FVector{200.0, 200.0, kGroundZ}, FVector{600.0, 200.0, kGroundZ},
            TAG_CkTests_GroundNav_Serialization_AreaAlpha)};

    if (NOT TestTrue(TEXT("the flat scene bakes with a tagged link"), Bake_FlatSceneWithLinks(Links, Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Field(Field, Blob);

    if (NOT TestTrue(TEXT("the tag's name is in the blob and can be overwritten"),
        Do_ReplaceBytes(Blob, kAlphaTagName, kUnregisteredTagName)))
    { return false; }

    auto Loaded = FCk_GroundNav_Field{};
    const auto Status = Read_Field(Blob, Loaded);

    TestTrue(FString::Printf(TEXT("a name that resolves to no tag is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::UnknownTag);

    TestEqual(TEXT("and the caller's field is untouched"), Loaded._Tiles.Num(), 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_LatticeMismatchIsAStatus,
    "CkTests.UnitTests.CkGroundNav.Serialization.LatticeMismatchIsAStatus",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_LatticeMismatchIsAStatus::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Field = FCk_GroundNav_Field{};

    if (NOT TestTrue(TEXT("the reference scene bakes"), Bake(Make_QueryScene(), Make_QueryParams(), Field)))
    { return false; }

    auto Blob = TArray<uint8>{};
    Write_Tile(Field, FCk_GroundNav_TileCoord{0, 0}, Blob);

    // Same origin, same cell size, a different number of divisions: a lattice the tile's indices were
    // never derived against.
    auto Target = Make_EmptyFieldLike(Make_FlatParams());
    const auto Status = Read_TileInto(Blob, Target);

    TestTrue(FString::Printf(TEXT("a tile from another lattice is refused [%s]"), *Get_StatusName(Status)),
        Status == ECk_GroundNav_LoadStatus::LatticeMismatch);

    TestTrue(TEXT("and the caller's field is untouched"),
        Target._Tiles[0]._Status == ECk_GroundNav_BuildStatus::Unbuilt);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_NothingProcessRelativeIsPersisted,
    "CkTests.UnitTests.CkGroundNav.Serialization.NothingProcessRelativeIsPersisted",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_NothingProcessRelativeIsPersisted::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    const auto StartA = FVector{200.0, 200.0, kGroundZ};
    const auto EndA = FVector{600.0, 200.0, kGroundZ};
    const auto StartB = FVector{200.0, 600.0, kGroundZ};
    const auto EndB = FVector{600.0, 600.0, kGroundZ};

    auto AlphaFirst = FCk_GroundNav_Field{};

    const auto AlphaFirstLinks = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, StartA, EndA, TAG_CkTests_GroundNav_Serialization_AreaAlpha),
        Make_Link(2, StartB, EndB, TAG_CkTests_GroundNav_Serialization_AreaZulu)};

    if (NOT TestTrue(TEXT("the flat scene bakes with alpha first"), Bake_FlatSceneWithLinks(AlphaFirstLinks, AlphaFirst)))
    { return false; }

    auto FirstWrite = TArray<uint8>{};
    auto SecondWrite = TArray<uint8>{};

    Write_Field(AlphaFirst, FirstWrite);
    Write_Field(AlphaFirst, SecondWrite);

    TestTrue(TEXT("two writes of one field differ only in the header's cook date"),
        Get_BlobsMatchOutsideTheCookDate(FirstWrite, SecondWrite));

    // The same two tags, reached in the opposite order. What makes this evidence is the ASCENDING-SORT
    // assertion at the end rather than the reversal itself: two authored orders could agree by luck,
    // where a table sorted by string cannot come out in any order but that one whatever reached the
    // writer first.
    auto ZuluFirst = FCk_GroundNav_Field{};

    const auto ZuluFirstLinks = TArray<FCk_GroundNav_LinkRecord>{
        Make_Link(1, StartA, EndA, TAG_CkTests_GroundNav_Serialization_AreaZulu),
        Make_Link(2, StartB, EndB, TAG_CkTests_GroundNav_Serialization_AreaAlpha)};

    if (NOT TestTrue(TEXT("the flat scene bakes with zulu first"), Bake_FlatSceneWithLinks(ZuluFirstLinks, ZuluFirst)))
    { return false; }

    auto ZuluFirstBlob = TArray<uint8>{};
    Write_Field(ZuluFirst, ZuluFirstBlob);

    auto AlphaFirstTable = TArray<FString>{};
    auto ZuluFirstTable = TArray<FString>{};

    const auto AlphaStatus = Read_TagTable(FirstWrite, AlphaFirstTable);
    const auto ZuluStatus = Read_TagTable(ZuluFirstBlob, ZuluFirstTable);

    if (NOT TestTrue(FString::Printf(TEXT("both tables read back [%s] [%s]"),
        *Get_StatusName(AlphaStatus), *Get_StatusName(ZuluStatus)),
        AlphaStatus == ECk_GroundNav_LoadStatus::Loaded && ZuluStatus == ECk_GroundNav_LoadStatus::Loaded))
    { return false; }

    if (NOT TestEqual(TEXT("the table carries both tags"), AlphaFirstTable.Num(), 2))
    { return false; }

    TestEqual(TEXT("and both blobs carry the same number of names"), ZuluFirstTable.Num(), AlphaFirstTable.Num());

    for (auto Index = 0; Index < AlphaFirstTable.Num(); ++Index)
    {
        TestEqual(FString::Printf(TEXT("table entry %d is the same whichever order the tags were authored in"), Index),
            ZuluFirstTable[Index], AlphaFirstTable[Index]);
    }

    for (auto Index = 1; Index < AlphaFirstTable.Num(); ++Index)
    {
        TestTrue(FString::Printf(TEXT("table entry %d sorts after the one before it"), Index),
            AlphaFirstTable[Index - 1].Compare(AlphaFirstTable[Index], ESearchCase::CaseSensitive) < 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_StreamingCompositionOrderMatchesWholeFieldOracle,
    "CkTests.UnitTests.CkGroundNav.Serialization.StreamingCompositionOrderMatchesWholeFieldOracle",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_StreamingCompositionOrderMatchesWholeFieldOracle::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};

    if (NOT TestTrue(TEXT("the distinct multi-tile profile sources bake"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    const auto Empty = Make_EmptyStreamingBundleLike(Source);
    const auto A = TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1}};
    const auto B = TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}};

    if (NOT TestTrue(TEXT("every 2x2 source tile is built before it becomes a blob"),
        Get_AreBundleTilesBuilt(Source, TArray<FCk_GroundNav_TileCoord>{
            FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1},
            FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}})))
    { return false; }

    const auto AlphaParamsDifference = Get_FirstParamsDifference(
        Source._DefaultField._Params,
        Source._VariantFields.FindChecked(TAG_CkTests_GroundNav_Serialization_AreaAlpha)._Params);

    if (NOT TestTrue(TEXT("the alpha variant carries a distinct but compatible profile payload"),
        NOT AlphaParamsDifference.IsEmpty()))
    { return false; }

    const auto AReplace = Make_ReplaceTransitions(Source, A);
    const auto BReplace = Make_ReplaceTransitions(Source, B);

    auto AfterA = FCk_GroundNav_StreamFieldBundle{};
    const auto AFirst = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, AReplace, AfterA);

    if (NOT TestTrue(TEXT("source A composes"), AFirst._Status == ECk_GroundNav_StreamCompositionStatus::Composed))
    { return false; }

    auto AThenB = FCk_GroundNav_StreamFieldBundle{};
    const auto BSecond = Compose_StreamTileTransitions(
        AfterA, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, BReplace, AThenB);

    if (NOT TestTrue(TEXT("source B follows A"), BSecond._Status == ECk_GroundNav_StreamCompositionStatus::Composed))
    { return false; }

    auto AfterB = FCk_GroundNav_StreamFieldBundle{};
    const auto BFirst = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, BReplace, AfterB);

    if (NOT TestTrue(TEXT("source B composes"), BFirst._Status == ECk_GroundNav_StreamCompositionStatus::Composed))
    { return false; }

    auto BThenA = FCk_GroundNav_StreamFieldBundle{};
    const auto ASecond = Compose_StreamTileTransitions(
        AfterB, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, AReplace, BThenA);

    if (NOT TestTrue(TEXT("source A follows B"), ASecond._Status == ECk_GroundNav_StreamCompositionStatus::Composed))
    { return false; }

    const auto Oracle = Make_OracleBundle(Source, TArray<FCk_GroundNav_TileCoord>{
        FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1},
        FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}});
    const auto AThenBDifference = Get_FirstBundleDifference(AThenB, Oracle);
    const auto BThenADifference = Get_FirstBundleDifference(BThenA, Oracle);

    TestTrue(FString::Printf(TEXT("A then B equals the whole-field oracle with epochs ignored [%s]"),
        *AThenBDifference), AThenBDifference.IsEmpty());
    TestTrue(FString::Printf(TEXT("B then A equals the whole-field oracle with epochs ignored [%s]"),
        *BThenADifference), BThenADifference.IsEmpty());
    TestTrue(TEXT("the alpha variant keeps its own profile through composition"),
        Get_FirstParamsDifference(
            AThenB._VariantFields.FindChecked(TAG_CkTests_GroundNav_Serialization_AreaAlpha)._Params,
            Oracle._VariantFields.FindChecked(TAG_CkTests_GroundNav_Serialization_AreaAlpha)._Params).IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_StreamingRemovalAndReplacementMatchTheWholeFieldOracle,
    "CkTests.UnitTests.CkGroundNav.Serialization.StreamingRemovalAndReplacementMatchTheWholeFieldOracle",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_StreamingRemovalAndReplacementMatchTheWholeFieldOracle::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};

    if (NOT TestTrue(TEXT("the distinct multi-tile profile sources bake"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    const auto A = TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1}};
    const auto B = TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}};

    if (NOT TestTrue(TEXT("every 2x2 source tile is built before it becomes a blob"),
        Get_AreBundleTilesBuilt(Source, TArray<FCk_GroundNav_TileCoord>{
            FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1},
            FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}})))
    { return false; }

    const auto RemoveA = Make_RemoveTransitions(A);
    const auto ReplaceA = Make_ReplaceTransitions(Source, A);

    auto WithoutA = FCk_GroundNav_StreamFieldBundle{};
    const auto Removed = Compose_StreamTileTransitions(
        Source, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, RemoveA, WithoutA);

    if (NOT TestTrue(TEXT("source A removes as one transaction"),
        Removed._Status == ECk_GroundNav_StreamCompositionStatus::Composed))
    { return false; }

    const auto BOnlyOracle = Make_OracleBundle(Source, B);
    const auto RemovalDifference = Get_FirstBundleDifference(WithoutA, BOnlyOracle);

    if (NOT TestTrue(FString::Printf(TEXT("removing A leaves exactly B [%s]"), *RemovalDifference),
        RemovalDifference.IsEmpty()))
    { return false; }

    auto Restored = FCk_GroundNav_StreamFieldBundle{};
    const auto Replaced = Compose_StreamTileTransitions(
        WithoutA, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, ReplaceA, Restored);

    if (NOT TestTrue(TEXT("the removed source replaces from its retained tile blobs"),
        Replaced._Status == ECk_GroundNav_StreamCompositionStatus::Composed))
    { return false; }

    const auto RestoreDifference = Get_FirstBundleDifference(Restored, Source);
    TestTrue(FString::Printf(TEXT("remove then replace restores the original without a geometry query [%s]"),
        *RestoreDifference), RestoreDifference.IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_StreamingIdentityRefusalsLeaveTheOutputUntouched,
    "CkTests.UnitTests.CkGroundNav.Serialization.StreamingIdentityRefusalsLeaveTheOutputUntouched",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_StreamingIdentityRefusalsLeaveTheOutputUntouched::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};

    if (NOT TestTrue(TEXT("the distinct multi-tile profile sources bake"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    const auto Empty = Make_EmptyStreamingBundleLike(Source);

    if (NOT TestTrue(TEXT("the source tile is built before it becomes a blob"),
        Get_AreBundleTilesBuilt(Source, TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{0, 0}})))
    { return false; }

    const auto ReplaceA = Make_ReplaceTransitions(Source, TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{0, 0}});
    const auto Sentinel = Source;

    auto Output = Sentinel;
    const auto InvalidVolume = Compose_StreamTileTransitions(Empty, FCk_GroundNav_VolumeId{0}, ReplaceA, Output);
    TestTrue(TEXT("zero volume identity is refused"),
        InvalidVolume._Status == ECk_GroundNav_StreamCompositionStatus::InvalidVolumeId);
    TestTrue(TEXT("invalid volume identity leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    Output = Sentinel;
    const auto LegacyVolume = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{INDEX_NONE}, ReplaceA, Output);
    TestTrue(TEXT("the legacy whole-volume identity is refused by streaming composition"),
        LegacyVolume._Status == ECk_GroundNav_StreamCompositionStatus::InvalidVolumeId);
    TestTrue(TEXT("the legacy whole-volume identity leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    auto WrongVolumeTransition = ReplaceA;
    WrongVolumeTransition[0]._TileId._VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue + 1};
    Output = Sentinel;
    const auto MismatchedVolume = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, WrongVolumeTransition, Output);
    TestTrue(TEXT("a tile for another volume is refused"),
        MismatchedVolume._Status == ECk_GroundNav_StreamCompositionStatus::InvalidTileId);
    TestTrue(TEXT("mismatched volume identity leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    auto NegativeVolumeTile = ReplaceA;
    NegativeVolumeTile[0]._TileId._VolumeId = FCk_GroundNav_VolumeId{-2};
    Output = Sentinel;
    const auto NegativeTile = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, NegativeVolumeTile, Output);
    TestTrue(TEXT("another negative volume identity is refused by a streamed tile"),
        NegativeTile._Status == ECk_GroundNav_StreamCompositionStatus::InvalidTileId);
    TestTrue(TEXT("another negative tile volume identity leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    auto DuplicateCoord = ReplaceA;
    DuplicateCoord.Emplace(ReplaceA[0]);
    Output = Sentinel;
    const auto Duplicate = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, DuplicateCoord, Output);
    TestTrue(TEXT("a duplicate tile coordinate is refused"),
        Duplicate._Status == ECk_GroundNav_StreamCompositionStatus::DuplicateTileCoord);
    TestTrue(TEXT("duplicate tile coordinates leave the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_StreamingVariantRefusalsAreAtomic,
    "CkTests.UnitTests.CkGroundNav.Serialization.StreamingVariantRefusalsAreAtomic",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_StreamingVariantRefusalsAreAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};

    if (NOT TestTrue(TEXT("the distinct multi-tile profile sources bake"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    const auto Empty = Make_EmptyStreamingBundleLike(Source);

    if (NOT TestTrue(TEXT("the source tile is built before it becomes a blob"),
        Get_AreBundleTilesBuilt(Source, TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{0, 0}})))
    { return false; }

    const auto ReplaceA = Make_ReplaceTransitions(Source, TArray<FCk_GroundNav_TileCoord>{FCk_GroundNav_TileCoord{0, 0}});
    const auto Sentinel = Source;

    auto MissingVariant = ReplaceA;
    MissingVariant[0]._VariantBlobs.Remove(TAG_CkTests_GroundNav_Serialization_AreaAlpha);
    auto Output = Sentinel;
    const auto Missing = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, MissingVariant, Output);
    TestTrue(TEXT("a missing profile tile blob is refused"),
        Missing._Status == ECk_GroundNav_StreamCompositionStatus::InvalidTransition);
    TestTrue(TEXT("a missing profile tile blob leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    auto ExtraVariant = ReplaceA;
    ExtraVariant[0]._VariantBlobs.Add(TAG_CkTests_GroundNav_Serialization_AreaBeta,
        ExtraVariant[0]._VariantBlobs.FindChecked(TAG_CkTests_GroundNav_Serialization_AreaAlpha));
    Output = Sentinel;
    const auto Extra = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, ExtraVariant, Output);
    TestTrue(TEXT("an extra profile tile blob is refused"),
        Extra._Status == ECk_GroundNav_StreamCompositionStatus::InvalidTransition);
    TestTrue(TEXT("an extra profile tile blob leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    auto CorruptVariant = ReplaceA;
    CorruptVariant[0]._VariantBlobs.FindChecked(TAG_CkTests_GroundNav_Serialization_AreaAlpha).SetNum(1);
    Output = Sentinel;
    const auto Corrupt = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, CorruptVariant, Output);
    TestTrue(TEXT("a corrupt profile tile blob is refused"),
        Corrupt._Status == ECk_GroundNav_StreamCompositionStatus::BlobRefused);
    TestTrue(TEXT("a corrupt profile tile blob leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_Serialization_StreamingNoChangeLeavesTheOutputUntouched,
    "CkTests.UnitTests.CkGroundNav.Serialization.StreamingNoChangeLeavesTheOutputUntouched",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_Serialization_StreamingNoChangeLeavesTheOutputUntouched::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};

    if (NOT TestTrue(TEXT("the distinct multi-tile profile sources bake"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    const auto Empty = Make_EmptyStreamingBundleLike(Source);
    const auto Sentinel = Source;
    const auto NoTransitions = TArray<FCk_GroundNav_StreamTileTransition>{};
    auto Output = Sentinel;
    const auto NoChange = Compose_StreamTileTransitions(
        Empty, FCk_GroundNav_VolumeId{kStreamingVolumeValue}, NoTransitions, Output);

    TestTrue(TEXT("an empty transition set reports no change"),
        NoChange._Status == ECk_GroundNav_StreamCompositionStatus::NoChange);
    TestTrue(TEXT("an empty transition set leaves the sentinel untouched"),
        Get_FirstBundleDifference(Output, Sentinel).IsEmpty());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingRegistry_RegistrationIsAtomic,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Registry.RegistrationIsAtomic",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingRegistry_RegistrationIsAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingRegistryRegistration"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };

    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto Initial = Make_EmptyStreamingBundleLike(Source);
    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    AddExpectedError(TEXT("GroundNav stream registration requires a valid all-profile bundle"),
        EAutomationExpectedErrorFlags::Contains, 2);
    const auto Invalid = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, FCk_GroundNav_StreamFieldBundle{});
    if (NOT TestEqual(TEXT("invalid registration is refused before reserving the owner and id"), Invalid._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::InvalidBundle))
    { return false; }
    if (NOT TestFalse(TEXT("invalid registration leaves no sidecar"),
        world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId).IsSet()))
    { return false; }

    const auto Registered = world_fields::Register_StreamOwner(Fixture._World, Fixture._Owner, VolumeId, Initial);
    if (NOT TestEqual(TEXT("the valid registration publishes"), Registered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    if (NOT TestTrue(TEXT("registration returns its bootstrap source"), Registered._Source.Get_IsValid()))
    { return false; }

    const auto Before = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("the successful registration is observable through the public snapshot"), Before.IsSet()))
    { return false; }

    const auto DuplicateOwner = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, FCk_GroundNav_VolumeId{kStreamingVolumeValue + 1}, Initial);
    TestEqual(TEXT("one owner cannot reserve a second streaming id"), DuplicateOwner._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::OwnerAlreadyRegistered);

    const auto AfterDuplicateOwner = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("duplicate owner refusal retains the original publication"), AfterDuplicateOwner.IsSet()))
    { return false; }
    TestTrue(TEXT("duplicate owner refusal retains every profile pointer and the epoch"),
        Get_SnapshotPointersAndEpochMatch(*AfterDuplicateOwner, *Before));

    const auto OtherOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture._WorldEntity);
    if (NOT TestTrue(TEXT("a distinct ECS owner is valid"), ck::IsValid(OtherOwner)))
    { return false; }

    const auto DuplicateId = world_fields::Register_StreamOwner(Fixture._World, OtherOwner, VolumeId, Initial);
    TestEqual(TEXT("one streaming id cannot reserve a second owner"), DuplicateId._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::OwnerAlreadyRegistered);

    const auto After = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("duplicate id refusal retains the original publication"), After.IsSet()))
    { return false; }

    TestTrue(TEXT("duplicate registration leaves every profile pointer and the epoch unchanged"),
        Get_SnapshotPointersAndEpochMatch(*After, *Before));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingRegistry_LoadingIsAtomic,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Registry.LoadingIsAtomic",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingRegistry_LoadingIsAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingRegistryLoading"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    if (NOT TestEqual(TEXT("the empty all-profile owner registers"), Registered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    const auto Coords = TArray<FCk_GroundNav_TileCoord>{
        FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1},
        FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}};
    const auto Replacements = Make_ReplaceTransitions(Source, Coords);
    const auto Loaded = world_fields::Load_StreamSource(Fixture._World, VolumeId, Replacements);
    if (NOT TestEqual(TEXT("a source load publishes every profile"), Loaded._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    const auto Before = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("load publishes default alpha and zulu fields with built tiles"),
        Before.IsSet() && Get_SnapshotHasBuiltTiles(*Before, Coords)))
    { return false; }

    const auto Duplicate = world_fields::Load_StreamSource(
        Fixture._World, VolumeId, TArray<FCk_GroundNav_StreamTileTransition>{Replacements[0]});
    TestEqual(TEXT("a second source cannot claim an occupied coordinate"), Duplicate._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::CoordinateAlreadyOwned);

    const auto AfterDuplicate = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("duplicate coordinate refusal retains a snapshot"), AfterDuplicate.IsSet()))
    { return false; }
    TestTrue(TEXT("duplicate coordinate refusal retains every profile pointer and the epoch"),
        Get_SnapshotPointersAndEpochMatch(*AfterDuplicate, *Before));

    auto Corrupt = TArray<FCk_GroundNav_StreamTileTransition>{Replacements[0]};
    Corrupt[0]._DefaultBlob.SetNum(1);
    AddExpectedError(TEXT("GroundNav stream transaction composition was refused"),
        EAutomationExpectedErrorFlags::Contains, 2);
    const auto Refused = world_fields::Replace_StreamSourceTiles(Fixture._World, VolumeId, Loaded._Source, Corrupt);
    TestEqual(TEXT("a corrupt replacement is refused by composition"), Refused._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::CompositionRefused);
    TestEqual(TEXT("the composition refusal reports the corrupt blob"), Refused._CompositionStatus,
        ECk_GroundNav_StreamCompositionStatus::BlobRefused);

    const auto AfterCorrupt = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("corrupt replacement refusal retains a snapshot"), AfterCorrupt.IsSet()))
    { return false; }
    TestTrue(TEXT("corrupt replacement refusal retains every profile pointer and the epoch"),
        Get_SnapshotPointersAndEpochMatch(*AfterCorrupt, *Before));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingRegistry_LifecyclePublishesAndCleansUp,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Registry.LifecyclePublishesAndCleansUp",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingRegistry_LifecyclePublishesAndCleansUp::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingRegistryLifecycle"));
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    {
        Destroy_StreamingRegistryFixture(Fixture);
        return false;
    }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Coords = TArray<FCk_GroundNav_TileCoord>{
        FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1},
        FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}};
    const auto Initial = Make_EmptyStreamingBundleLike(Source);
    const auto Registered = world_fields::Register_StreamOwner(Fixture._World, Fixture._Owner, VolumeId, Initial);
    if (NOT TestEqual(TEXT("the lifecycle owner registers"), Registered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }

    const auto Loaded = world_fields::Load_StreamSource(Fixture._World, VolumeId, Make_ReplaceTransitions(Source, Coords));
    if (NOT TestEqual(TEXT("the lifecycle source loads"), Loaded._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }
    const auto LoadedSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("load builds every profile"), LoadedSnapshot.IsSet() && Get_SnapshotHasBuiltTiles(*LoadedSnapshot, Coords)))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }

    const auto Disabled = world_fields::Disable_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("disable publishes geometry removal"), Disabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }
    const auto DisabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("disable leaves all profiles unbuilt"), DisabledSnapshot.IsSet() && Get_SnapshotHasUnbuiltTiles(*DisabledSnapshot, Coords)))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }
    TestTrue(TEXT("disable publishes a new immutable field"), DisabledSnapshot->_DefaultField != LoadedSnapshot->_DefaultField);

    const auto Enabled = world_fields::Enable_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("enable republishes geometry"), Enabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }
    const auto EnabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("enable rebuilds every profile"), EnabledSnapshot.IsSet() && Get_SnapshotHasBuiltTiles(*EnabledSnapshot, Coords)))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }

    const auto Unloaded = world_fields::Unload_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("unload publishes geometry removal"), Unloaded._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }
    const auto UnloadedSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("unload leaves all profiles unbuilt"), UnloadedSnapshot.IsSet() && Get_SnapshotHasUnbuiltTiles(*UnloadedSnapshot, Coords)))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }
    TestTrue(TEXT("unload publishes a new immutable field"), UnloadedSnapshot->_DefaultField != EnabledSnapshot->_DefaultField);

    const auto Stale = world_fields::Enable_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    TestEqual(TEXT("an unloaded source handle is not found"), Stale._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::SourceNotFound);

    const auto Unregistered = world_fields::Unregister_StreamOwner(Fixture._World, Fixture._Owner, VolumeId);
    if (NOT TestEqual(TEXT("unregister drops the owner publication"), Unregistered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }
    if (NOT TestFalse(TEXT("unregister removes the public snapshot"),
        world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId).IsSet()))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }

    const auto Reregistered = world_fields::Register_StreamOwner(Fixture._World, Fixture._Owner, VolumeId, Initial);
    if (NOT TestEqual(TEXT("the same owner and id can register after cleanup"), Reregistered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { Destroy_StreamingRegistryFixture(Fixture); return false; }

    auto* DestroyedWorld = Fixture._World;
    Destroy_StreamingRegistryFixture(Fixture);
    TestFalse(TEXT("world cleanup drops the re-registered sidecar"),
        world_fields::TryGet_StreamOwnerSnapshot(DestroyedWorld, VolumeId).IsSet());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingRegistry_SourceHandlesDoNotAliasOwners,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Registry.SourceHandlesDoNotAliasOwners",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingRegistry_SourceHandlesDoNotAliasOwners::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingRegistrySourceIdentity"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeA = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto VolumeB = FCk_GroundNav_VolumeId{kStreamingVolumeValue + 1};
    const auto OwnerB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Fixture._WorldEntity);
    if (NOT TestTrue(TEXT("a second ECS owner is valid"), ck::IsValid(OwnerB)))
    { return false; }

    const auto RegisteredA = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeA, Make_EmptyStreamingBundleLike(Source));
    const auto RegisteredB = world_fields::Register_StreamOwner(
        Fixture._World, OwnerB, VolumeB, Make_EmptyStreamingBundleLike(Source));
    if (NOT TestEqual(TEXT("owner A registers"), RegisteredA._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published) ||
        NOT TestEqual(TEXT("owner B registers"), RegisteredB._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    if (NOT TestFalse(TEXT("different owners receive distinct opaque source handles"),
        RegisteredA._Source == RegisteredB._Source))
    { return false; }

    const auto BeforeB = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeB);
    if (NOT TestTrue(TEXT("owner B has a public snapshot"), BeforeB.IsSet()))
    { return false; }

    const auto Misused = world_fields::Disable_StreamSource(Fixture._World, VolumeB, RegisteredA._Source);
    TestEqual(TEXT("owner A's source handle cannot mutate owner B"), Misused._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::SourceNotFound);

    const auto AfterB = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeB);
    if (NOT TestTrue(TEXT("owner B remains published after foreign-handle refusal"), AfterB.IsSet()))
    { return false; }
    TestTrue(TEXT("foreign-handle refusal preserves owner B's immutable pointers and epoch"),
        Get_SnapshotPointersAndEpochMatch(*AfterB, *BeforeB));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingRegistry_RefreshReconcilesRetainedSources,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Registry.RefreshReconcilesRetainedSources",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingRegistry_RefreshReconcilesRetainedSources::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }

    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingRegistryRefresh"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Coords = TArray<FCk_GroundNav_TileCoord>{
        FCk_GroundNav_TileCoord{0, 0}, FCk_GroundNav_TileCoord{0, 1},
        FCk_GroundNav_TileCoord{1, 0}, FCk_GroundNav_TileCoord{1, 1}};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    if (NOT TestEqual(TEXT("the refresh owner registers"), Registered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    const auto Loaded = world_fields::Load_StreamSource(Fixture._World, VolumeId, Make_ReplaceTransitions(Source, Coords));
    if (NOT TestEqual(TEXT("the refresh source loads"), Loaded._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    const auto Disabled = world_fields::Disable_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("the refresh source disables"), Disabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto DisabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("disable leaves the refresh publication unbuilt"),
        DisabledSnapshot.IsSet() && Get_SnapshotHasUnbuiltTiles(*DisabledSnapshot, Coords)))
    { return false; }

    constexpr auto kRefreshedTriangleCount = 123456;
    auto Refreshed = Source;
    Set_BundleTileTriangleCount(Refreshed, FCk_GroundNav_TileCoord{0, 0}, kRefreshedTriangleCount);

    const auto RefreshWhileDisabled = world_fields::Refresh_StreamOwnerBundle(
        Fixture._World, VolumeId, Refreshed, world_fields::FCk_GroundNav_PublishClaim::Geometry());
    if (NOT TestEqual(TEXT("refresh accepts a complete bundle while a source is disabled"), RefreshWhileDisabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    TestTrue(TEXT("refresh publishes an epoch newer than the disabled registry publication"),
        RefreshWhileDisabled._Epoch.Get_IsNewerThan(DisabledSnapshot->_Epoch));

    const auto RefreshedDisabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("refresh preserves the disabled publication mask"),
        RefreshedDisabledSnapshot.IsSet() && Get_SnapshotHasUnbuiltTiles(*RefreshedDisabledSnapshot, Coords)))
    { return false; }

    const auto Enabled = world_fields::Enable_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("enable restores refreshed retained tiles"), Enabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto EnabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("enable publishes the refreshed retained tile payload for every profile"),
        EnabledSnapshot.IsSet() && SnapshotHasTileTriangleCount(
            *EnabledSnapshot, FCk_GroundNav_TileCoord{0, 0}, kRefreshedTriangleCount)))
    { return false; }

    const auto Unloaded = world_fields::Unload_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("the refreshed source unloads"), Unloaded._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    const auto RefreshAfterUnload = world_fields::Refresh_StreamOwnerBundle(
        Fixture._World, VolumeId, Refreshed, world_fields::FCk_GroundNav_PublishClaim::Geometry());
    if (NOT TestEqual(TEXT("refresh after unload still publishes lifecycle state"), RefreshAfterUnload._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto UnloadedRefreshSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestTrue(TEXT("an unloaded coordinate remains unbuilt after a complete refresh bundle arrives"),
        UnloadedRefreshSnapshot.IsSet() && Get_SnapshotHasUnbuiltTiles(*UnloadedRefreshSnapshot, Coords));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingRegistry_RefreshDisabledTileUsesFreshBlob,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Invoker.Registry.RefreshDisabledTileUsesFreshBlob",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingRegistry_RefreshDisabledTileUsesFreshBlob::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_serialization;

    auto Source = FCk_GroundNav_StreamFieldBundle{};
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_DistinctStreamingSource(Source)))
    { return false; }
    auto Fixture = Make_StreamingRegistryFixture(TEXT("CkGroundNavStreamingRefreshFreshBlob"));
    ON_SCOPE_EXIT { Destroy_StreamingRegistryFixture(Fixture); };
    if (NOT TestTrue(TEXT("a real world and ECS owner are ready"), Get_IsReady(Fixture)))
    { return false; }

    const auto VolumeId = FCk_GroundNav_VolumeId{kStreamingVolumeValue};
    const auto Coord = FCk_GroundNav_TileCoord{0, 0};
    const auto Registered = world_fields::Register_StreamOwner(
        Fixture._World, Fixture._Owner, VolumeId, Make_EmptyStreamingBundleLike(Source));
    if (NOT TestEqual(TEXT("the owner registers"), Registered._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto Loaded = world_fields::Load_StreamSource(
        Fixture._World, VolumeId, Make_ReplaceTransitions(Source, TArray<FCk_GroundNav_TileCoord>{Coord}));
    if (NOT TestEqual(TEXT("the retained source loads"), Loaded._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto Disabled = world_fields::Disable_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("the source disables before refresh"), Disabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }

    constexpr auto kFreshTriangleCount = 654321;
    auto Refreshed = Source;
    Set_BundleTileTriangleCount(Refreshed, Coord, kFreshTriangleCount);
    const auto RefreshedResult = world_fields::Refresh_StreamOwnerBundle(
        Fixture._World, VolumeId, Refreshed, world_fields::FCk_GroundNav_PublishClaim::Geometry());
    if (NOT TestEqual(TEXT("refresh stages the disabled source's new all-profile blobs"), RefreshedResult._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto StillDisabled = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("refresh leaves the retained source unbuilt while disabled"), StillDisabled.IsSet() &&
        SnapshotHasTileBuiltState(*StillDisabled, Coord, false)))
    { return false; }

    const auto Enabled = world_fields::Enable_StreamSource(Fixture._World, VolumeId, Loaded._Source);
    if (NOT TestEqual(TEXT("re-enable publishes the retained source"), Enabled._Status,
        world_fields::ECk_GroundNav_StreamRegistryStatus::Published))
    { return false; }
    const auto AfterEnable = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestTrue(TEXT("re-enable exposes the refreshed payload in every profile rather than the stale blob"),
        AfterEnable.IsSet() && SnapshotHasTileTriangleCount(*AfterEnable, Coord, kFreshTriangleCount));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
