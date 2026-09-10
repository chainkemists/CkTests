#include "Misc/AutomationTest.h"

#if WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS

#include "CkCore/Validation/CkIsValid.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkGroundNav/Bake/CkGroundNav_DataLayerSelector.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedFieldLoad.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedSourceManifest.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedTile.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Field/CkGroundNav_TileBake.h"
#include "CkGroundNav/Streaming/CkGroundNav_StreamPartitionLifecycle.h"
#include "CkGroundNav/Streaming/CkGroundNav_StreamManifestSubsystem_UE.h"
#include "../CkUnitTest_Common.h"
#include "Test_GroundNav_QueryFixtures.h"
#include <Engine/World.h>
#include <Misc/ScopeExit.h>
#include <NativeGameplayTags.h>
#include <UObject/Class.h>
#include <UObject/Package.h>
#include <WorldPartition/DataLayer/DataLayerManager.h>

namespace ck_test_groundnav_stream_partition_manifest
{
    using namespace ck::groundnav;
    namespace stream_partitions = ck::groundnav::stream_partitions;
    namespace world_fields = ck::groundnav::world_fields;

    UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_StreamManifestVariant, "CkTests.GroundNav.StreamManifest.Variant");
    constexpr auto kTestFlags = ck::tests::kCkUnitTestFlags;
    constexpr auto kInformEngineOfWorld = false;
    constexpr auto kVolumeId = int32{7107};
    constexpr auto kPartitionId = int32{41};
    constexpr auto kDefaultFingerprint = uint64{0x1234567890ABCDEFull};
    constexpr auto kVariantFingerprint = uint64{0x0FEDCBA098765432ull};

    struct FRegistryFixture { UWorld* _World = nullptr; FCk_Handle _WorldEntity; FCk_Handle _Owner; };

    auto Make_Selector() -> FCk_GroundNav_DataLayerSelector
    {
        auto Result = FCk_GroundNav_DataLayerSelector{};
        TryMake_DataLayerSelector(TArray<FName>{FName{"Gameplay"}, FName{"Navigation"}}, Result);
        return Result;
    }

    auto Bake_Bundle(FCk_GroundNav_StreamFieldBundle& OutBundle) -> bool
    {
        auto DefaultField = FCk_GroundNav_Field{};
        if (NOT ck_test_groundnav_queryfixtures::Bake(ck_test_groundnav_queryfixtures::Make_QueryScene(), ck_test_groundnav_queryfixtures::Make_QueryParams(), DefaultField)) { return false; }
        auto VariantParams = ck_test_groundnav_queryfixtures::Make_QueryParams();
        VariantParams._Profile.Set_LedgeSensitivity(0.5f);
        auto VariantField = FCk_GroundNav_Field{};
        if (NOT ck_test_groundnav_queryfixtures::Bake(ck_test_groundnav_queryfixtures::Make_QueryScene(), VariantParams, VariantField)) { return false; }
        OutBundle._DefaultField = MoveTemp(DefaultField);
        OutBundle._VariantFields.Add(TAG_CkTests_GroundNav_StreamManifestVariant, MoveTemp(VariantField));
        return true;
    }

    auto Make_EmptyBundleLike(const FCk_GroundNav_StreamFieldBundle& InSource) -> FCk_GroundNav_StreamFieldBundle
    {
        const auto MakeEmpty = [](const FCk_GroundNav_Field& InField)
        {
            auto Result = FCk_GroundNav_Field{};
            Result._Params = InField._Params;
            Result._Tiles.SetNum(InField._Tiles.Num());
            for (auto Index = 0; Index < Result._Tiles.Num(); ++Index) { Result._Tiles[Index]._Coord = Get_TileCoord(Result._Params._Divisions, Index); }
            return Result;
        };
        auto Result = FCk_GroundNav_StreamFieldBundle{};
        Result._DefaultField = MakeEmpty(InSource._DefaultField);
        for (const auto& Variant : InSource._VariantFields) { Result._VariantFields.Add(Variant.Key, MakeEmpty(Variant.Value)); }
        return Result;
    }

    auto Make_CookedTiles(const FCk_GroundNav_Field& InField, FGameplayTag InProfileTag, uint64 InFingerprint, const FCk_GroundNav_DataLayerSelector& InSelector) -> TArray<TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>>
    {
        auto Result = TArray<TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>>{};
        Result.Reserve(InField._Tiles.Num());
        const auto LatticeKey = Get_CookedLatticeKey(InField._Params);
        for (const auto& FieldTile : InField._Tiles)
        {
            auto Blob = TArray<uint8>{}; Write_Tile(InField, FieldTile._Coord, Blob);
            auto* Tile = NewObject<UCk_GroundNav_CookedTile_UE>(GetTransientPackage());
            if (NOT ck::IsValid(Tile)) { return {}; }
            Tile->Set_FormatVersion(kFieldBlobFormatVersion); Tile->Set_StreamingVolumeId(kVolumeId);
            Tile->Set_TileCoord({FieldTile._Coord._X, FieldTile._Coord._Y});
            Tile->Set_WorldBounds(Get_TileBounds(InField._Params.Get_TileBakeParams(FieldTile._Coord, FCk_GroundNav_Epoch{})));
            Tile->Set_DataLayerNames(InSelector.Get_LayerNames()); Tile->Set_Fingerprint(InFingerprint);
            Tile->Set_ProfileTag(InProfileTag); Tile->Set_LatticeKey(LatticeKey); Tile->Set_Blob(MoveTemp(Blob));
            Tile->Set_ContentHash(Get_CookedTileContentHash(Tile->Get_Blob())); Result.Add(Tile);
        }
        return Result;
    }

    auto Make_Manifest(const FCk_GroundNav_StreamFieldBundle& InBundle, const FCk_GroundNav_DataLayerSelector& InSelector) -> UCk_GroundNav_CookedSourceManifest_UE*
    {
        auto* Manifest = NewObject<UCk_GroundNav_CookedSourceManifest_UE>(GetTransientPackage());
        if (NOT ck::IsValid(Manifest)) { return nullptr; }
        Manifest->Set_FormatVersion(kFieldBlobFormatVersion); Manifest->Set_StreamingVolumeId(kVolumeId); Manifest->Set_PartitionId(kPartitionId);
        Manifest->Set_DataLayerNames(InSelector.Get_LayerNames()); Manifest->Set_LatticeKey(Get_CookedLatticeKey(InBundle._DefaultField._Params));
        auto Coords = TArray<FIntPoint>{}; for (const auto& Tile : InBundle._DefaultField._Tiles) { Coords.Add({Tile._Coord._X, Tile._Coord._Y}); }
        Manifest->Set_TileCoords(MoveTemp(Coords));
        auto Profiles = TArray<FCk_GroundNav_CookedSourceProfile_UE>{};
        auto Default = FCk_GroundNav_CookedSourceProfile_UE{}; Default.Set_Fingerprint(kDefaultFingerprint);
        Default.Set_Tiles(Make_CookedTiles(InBundle._DefaultField, {}, kDefaultFingerprint, InSelector)); Profiles.Add(MoveTemp(Default));
        const auto& Variant = InBundle._VariantFields.FindChecked(TAG_CkTests_GroundNav_StreamManifestVariant);
        auto VariantProfile = FCk_GroundNav_CookedSourceProfile_UE{}; VariantProfile.Set_ProfileTag(TAG_CkTests_GroundNav_StreamManifestVariant); VariantProfile.Set_Fingerprint(kVariantFingerprint);
        VariantProfile.Set_Tiles(Make_CookedTiles(Variant, TAG_CkTests_GroundNav_StreamManifestVariant, kVariantFingerprint, InSelector)); Profiles.Add(MoveTemp(VariantProfile));
        Manifest->Set_Profiles(MoveTemp(Profiles)); return Manifest;
    }

    auto Try_LoadManifest(const UCk_GroundNav_CookedSourceManifest_UE& InManifest, const FCk_GroundNav_StreamFieldBundle& InTemplate, const FCk_GroundNav_DataLayerSelector& InSelector, TArray<FCk_GroundNav_StreamTileTransition>& OutTransitions) -> ECk_GroundNav_CookStatus
    {
        auto VariantFingerprints = TMap<FGameplayTag, uint64>{}; VariantFingerprints.Add(TAG_CkTests_GroundNav_StreamManifestVariant, kVariantFingerprint);
        return Try_LoadCookedSourceManifest(InManifest, InTemplate, kDefaultFingerprint, VariantFingerprints, kVolumeId, kPartitionId, InSelector, OutTransitions);
    }

    auto Make_Fixture(const TCHAR* InName) -> FRegistryFixture
    {
        auto Result = FRegistryFixture{}; Result._World = UWorld::CreateWorld(EWorldType::Game, kInformEngineOfWorld, FName{InName});
        if (Result._World == nullptr) { return Result; }
        Result._WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(Result._World);
        if (ck::Is_NOT_Valid(Result._WorldEntity)) { return Result; }
        Result._Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Result._WorldEntity); return Result;
    }
    auto Destroy_Fixture(FRegistryFixture& InFixture) -> void { if (InFixture._World != nullptr) { InFixture._World->DestroyWorld(kInformEngineOfWorld); } InFixture._World = nullptr; }
    auto Get_IsReady(const FRegistryFixture& InFixture) -> bool { return InFixture._World != nullptr && ck::IsValid(InFixture._Owner); }
    auto Get_SnapshotMatches(const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InLeft, const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InRight) -> bool
    {
        if (InLeft._DefaultField != InRight._DefaultField || InLeft._Epoch != InRight._Epoch || InLeft._VariantFields.Num() != InRight._VariantFields.Num()) { return false; }
        for (const auto& Variant : InLeft._VariantFields) { const auto* Other = InRight._VariantFields.Find(Variant.Key); if (Other == nullptr || *Other != Variant.Value) { return false; } }
        return true;
    }
    auto Get_HasBuiltTiles(const world_fields::FCk_GroundNav_StreamOwnerSnapshot& InSnapshot, bool InExpectedBuilt) -> bool
    {
        const auto HasExpectedState = [InExpectedBuilt](const FCk_GroundNav_FieldPtr& InField) { if (NOT InField.IsValid()) { return false; } for (const auto& Tile : InField->_Tiles) { if (Tile.Get_IsBuilt() != InExpectedBuilt) { return false; } } return true; };
        if (NOT HasExpectedState(InSnapshot._DefaultField)) { return false; }
        for (const auto& Variant : InSnapshot._VariantFields) { if (NOT HasExpectedState(Variant.Value)) { return false; } }
        return true;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_GroundNav_StreamManifest_ValidAllProfileLoad, "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Manifest.ValidAllProfileLoad", ck_test_groundnav_stream_partition_manifest::kTestFlags)
bool FCkTest_GroundNav_StreamManifest_ValidAllProfileLoad::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_stream_partition_manifest;
    auto Bundle = FCk_GroundNav_StreamFieldBundle{}; const auto Selector = Make_Selector();
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_Bundle(Bundle))) { return false; }
    auto* Manifest = Make_Manifest(Bundle, Selector); if (NOT TestNotNull(TEXT("the transient source manifest exists"), Manifest)) { return false; }
    auto Transitions = TArray<FCk_GroundNav_StreamTileTransition>{}; const auto Status = Try_LoadManifest(*Manifest, Make_EmptyBundleLike(Bundle), Selector, Transitions);
    TestEqual(TEXT("a complete source manifest loads"), Status, ECk_GroundNav_CookStatus::Cooked);
    TestEqual(TEXT("the loader returns one transition per manifest coordinate"), Transitions.Num(), Manifest->Get_TileCoords().Num());
    TestTrue(TEXT("each transition retains the default and exact variant blob"), NOT Transitions.IsEmpty() && Transitions[0]._VariantBlobs.Contains(TAG_CkTests_GroundNav_StreamManifestVariant)); return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_GroundNav_StreamManifest_MalformedInputIsAtomic, "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Manifest.MalformedInputIsAtomic", ck_test_groundnav_stream_partition_manifest::kTestFlags)
bool FCkTest_GroundNav_StreamManifest_MalformedInputIsAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_stream_partition_manifest;
    auto Bundle = FCk_GroundNav_StreamFieldBundle{}; const auto Selector = Make_Selector();
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_Bundle(Bundle))) { return false; }
    auto* Manifest = Make_Manifest(Bundle, Selector); if (NOT TestNotNull(TEXT("the transient source manifest exists"), Manifest)) { return false; }
    auto Sentinel = TArray<FCk_GroundNav_StreamTileTransition>{}; Sentinel.Add({FCk_GroundNav_StreamTileId{FCk_GroundNav_VolumeId{kVolumeId}, {0, 0}}});
    Manifest->Set_PartitionId(kPartitionId + 1);
    TestEqual(TEXT("a partition identity mismatch refuses"), Try_LoadManifest(*Manifest, Make_EmptyBundleLike(Bundle), Selector, Sentinel), ECk_GroundNav_CookStatus::StaleCook); TestEqual(TEXT("identity refusal preserves output"), Sentinel.Num(), 1);
    Manifest->Set_PartitionId(kPartitionId); auto Profiles = Manifest->Get_Profiles(); Profiles.Pop(); Manifest->Set_Profiles(Profiles);
    TestEqual(TEXT("a missing variant profile refuses"), Try_LoadManifest(*Manifest, Make_EmptyBundleLike(Bundle), Selector, Sentinel), ECk_GroundNav_CookStatus::StaleCook); TestEqual(TEXT("profile refusal preserves output"), Sentinel.Num(), 1);
    Manifest = Make_Manifest(Bundle, Selector); auto Coords = Manifest->Get_TileCoords(); Coords[0] = FIntPoint{99, 99}; Manifest->Set_TileCoords(Coords);
    TestEqual(TEXT("an out-of-lattice coordinate refuses"), Try_LoadManifest(*Manifest, Make_EmptyBundleLike(Bundle), Selector, Sentinel), ECk_GroundNav_CookStatus::StaleCook); TestEqual(TEXT("coordinate refusal preserves output"), Sentinel.Num(), 1);
    Manifest = Make_Manifest(Bundle, Selector); auto Tiles = Manifest->Get_Profiles()[0].Get_Tiles(); auto* FirstTile = Tiles[0].LoadSynchronous(); FirstTile->Set_TileCoord({88, 88});
    TestEqual(TEXT("a tile whose identity disagrees with the manifest refuses"), Try_LoadManifest(*Manifest, Make_EmptyBundleLike(Bundle), Selector, Sentinel), ECk_GroundNav_CookStatus::StaleCook); TestEqual(TEXT("tile refusal preserves output"), Sentinel.Num(), 1); return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_GroundNav_StreamManifest_DataLayerActivationReducer, "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Manifest.DataLayerActivationReducer", ck_test_groundnav_stream_partition_manifest::kTestFlags)
bool FCkTest_GroundNav_StreamManifest_DataLayerActivationReducer::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_stream_partition_manifest;
    TestTrue(TEXT("an empty canonical selector has no runtime data-layer gate"),
        UCk_GroundNav_StreamManifestSubsystem_UE::Get_AreDataLayerRuntimeStatesActivated(
            TArray<EDataLayerRuntimeState>{}));
    TestFalse(TEXT("a partial selected-layer activation keeps the source disabled"),
        UCk_GroundNav_StreamManifestSubsystem_UE::Get_AreDataLayerRuntimeStatesActivated(
            TArray<EDataLayerRuntimeState>{EDataLayerRuntimeState::Activated, EDataLayerRuntimeState::Loaded}));
    TestTrue(TEXT("every selected layer activated enables the source"),
        UCk_GroundNav_StreamManifestSubsystem_UE::Get_AreDataLayerRuntimeStatesActivated(
            TArray<EDataLayerRuntimeState>{EDataLayerRuntimeState::Activated, EDataLayerRuntimeState::Activated}));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_GroundNav_StreamManifest_BindingCoordinatesAreAtomic, "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Manifest.BindingCoordinatesAreAtomic", ck_test_groundnav_stream_partition_manifest::kTestFlags)
bool FCkTest_GroundNav_StreamManifest_BindingCoordinatesAreAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_stream_partition_manifest;
    auto Bundle = FCk_GroundNav_StreamFieldBundle{}; const auto Selector = Make_Selector();
    if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_Bundle(Bundle))) { return false; }
    auto* Manifest = Make_Manifest(Bundle, Selector);
    if (NOT TestNotNull(TEXT("the transient source manifest exists"), Manifest)) { return false; }
    auto BindingCoords = Manifest->Get_TileCoords(); BindingCoords[0].X += 1;
    auto Sentinel = TArray<FCk_GroundNav_StreamTileTransition>{};
    Sentinel.Add({FCk_GroundNav_StreamTileId{FCk_GroundNav_VolumeId{kVolumeId}, {0, 0}}});
    auto VariantFingerprints = TMap<FGameplayTag, uint64>{};
    VariantFingerprints.Add(TAG_CkTests_GroundNav_StreamManifestVariant, kVariantFingerprint);
    TestFalse(TEXT("a binding must own the manifest's exact ordered coordinate set"),
        UCk_GroundNav_StreamManifestSubsystem_UE::Get_AreManifestTileCoordsCompatible(
            BindingCoords, Manifest->Get_TileCoords()));
    TestEqual(TEXT("a binding coordinate mismatch refuses before publication"),
        UCk_GroundNav_StreamManifestSubsystem_UE::Try_LoadBoundCookedSourceManifest(
            *Manifest, BindingCoords, Make_EmptyBundleLike(Bundle), kDefaultFingerprint, VariantFingerprints,
            kVolumeId, kPartitionId, Selector, Sentinel), ECk_GroundNav_CookStatus::StaleCook);
    TestEqual(TEXT("the binding mismatch preserves the caller's transition sentinel"), Sentinel.Num(), 1);
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FCkTest_GroundNav_StreamPartition_LifecycleIsAtomic, "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Manifest.LifecycleIsAtomic", ck_test_groundnav_stream_partition_manifest::kTestFlags)
bool FCkTest_GroundNav_StreamPartition_LifecycleIsAtomic::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_stream_partition_manifest;
    auto Bundle = FCk_GroundNav_StreamFieldBundle{}; if (NOT TestTrue(TEXT("the all-profile source bakes"), Bake_Bundle(Bundle))) { return false; }
    auto Fixture = Make_Fixture(TEXT("CkGroundNavStreamPartitionLifecycle")); ON_SCOPE_EXIT { Destroy_Fixture(Fixture); };
    if (NOT TestTrue(TEXT("the production registry fixture is ready"), Get_IsReady(Fixture))) { return false; }
    const auto VolumeId = FCk_GroundNav_VolumeId{kVolumeId}; const auto Registered = stream_partitions::Register_ManifestOwner(Fixture._World, Fixture._Owner, VolumeId, Make_EmptyBundleLike(Bundle));
    if (NOT TestEqual(TEXT("the manifest owner registers without a bootstrap source"), Registered._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published) || NOT TestTrue(TEXT("registration returns a positive owner lifetime fence"), Registered._OwnerInstance != 0) || NOT TestFalse(TEXT("a manifest owner reserves no bootstrap source"), Registered._Registry._Source.Get_IsValid())) { return false; }
    const auto EmptyOwnerSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    const auto DuplicateOwner = stream_partitions::Register_ManifestOwner(Fixture._World, Fixture._Owner, VolumeId, Make_EmptyBundleLike(Bundle));
    TestEqual(TEXT("a duplicate manifest-owner registration refuses"), DuplicateOwner._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::RegistryRefused);
    const auto AfterDuplicateOwner = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    if (NOT TestTrue(TEXT("a refused manifest-owner registration leaves the source-free publication unchanged"), EmptyOwnerSnapshot.IsSet() && AfterDuplicateOwner.IsSet() && Get_SnapshotMatches(*EmptyOwnerSnapshot, *AfterDuplicateOwner))) { return false; }
    auto Load = stream_partitions::FCk_GroundNav_StreamPartitionLoad{}; Load._Key = {VolumeId, kPartitionId}; Load._OwnerInstance = Registered._OwnerInstance; Load._Generation = 1;
    for (const auto& Tile : Bundle._DefaultField._Tiles) { auto Transition = FCk_GroundNav_StreamTileTransition{}; Transition._TileId = {VolumeId, Tile._Coord}; Write_Tile(Bundle._DefaultField, Tile._Coord, Transition._DefaultBlob); for (const auto& Variant : Bundle._VariantFields) { Write_Tile(Variant.Value, Tile._Coord, Transition._VariantBlobs.Add(Variant.Key)); } Load._Transitions.Add(MoveTemp(Transition)); }
    const auto Loaded = stream_partitions::Load(Fixture._World, Load); if (NOT TestEqual(TEXT("a decoded manifest source publishes"), Loaded._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published)) { return false; }
    const auto LoadedSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId); if (NOT TestTrue(TEXT("load publishes every profile"), LoadedSnapshot.IsSet() && Get_HasBuiltTiles(*LoadedSnapshot, true))) { return false; }
    Load._Generation = 2; const auto Duplicate = stream_partitions::Load(Fixture._World, Load); TestEqual(TEXT("a second active partition source refuses"), Duplicate._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::DuplicateActivePartition);
    const auto AfterDuplicate = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId); TestTrue(TEXT("duplicate source refusal preserves publication pointers and epoch"), AfterDuplicate.IsSet() && Get_SnapshotMatches(*LoadedSnapshot, *AfterDuplicate));
    const auto Key = Load._Key; const auto Disabled = stream_partitions::Deactivate(Fixture._World, Key, Load._OwnerInstance, 3); if (NOT TestEqual(TEXT("data-layer deactivation removes every profile together"), Disabled._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published)) { return false; }
    const auto DisabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId); if (NOT TestTrue(TEXT("deactivation publishes an all-profile empty source"), DisabledSnapshot.IsSet() && Get_HasBuiltTiles(*DisabledSnapshot, false))) { return false; }
    const auto StaleReactivate = stream_partitions::Reactivate(Fixture._World, Key, Load._OwnerInstance, 3); TestEqual(TEXT("a stale lifecycle generation cannot mutate the disabled source"), StaleReactivate._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::StaleEvent);
    const auto AfterStale = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId); TestTrue(TEXT("a stale event leaves the disabled publication intact"), AfterStale.IsSet() && Get_SnapshotMatches(*DisabledSnapshot, *AfterStale));
    const auto Enabled = stream_partitions::Reactivate(Fixture._World, Key, Load._OwnerInstance, 4); if (NOT TestEqual(TEXT("reactivation restores retained all-profile blobs"), Enabled._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published)) { return false; }
    const auto EnabledSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId); if (NOT TestTrue(TEXT("reactivation restores all profiles"), EnabledSnapshot.IsSet() && Get_HasBuiltTiles(*EnabledSnapshot, true))) { return false; }
    const auto Unloaded = stream_partitions::Unload(Fixture._World, Key, Load._OwnerInstance, 5); if (NOT TestEqual(TEXT("cell unload drops the source"), Unloaded._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published)) { return false; }
    const auto UnloadedSnapshot = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId); if (NOT TestTrue(TEXT("unload removes every profile's tiles"), UnloadedSnapshot.IsSet() && Get_HasBuiltTiles(*UnloadedSnapshot, false))) { return false; }
    TestEqual(TEXT("a late reactivation after unload cannot resurrect tiles"), stream_partitions::Reactivate(Fixture._World, Key, Load._OwnerInstance, 6)._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::PartitionNotActive);
    const auto Purged = stream_partitions::Purge_OwnerPartitions(Fixture._World, Fixture._Owner, VolumeId); TestEqual(TEXT("owner purge removes the logical owner publication"), Purged._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published); TestFalse(TEXT("owner purge removes the public snapshot"), world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId).IsSet());
    auto LateLoad = Load; LateLoad._Generation = 1;
    TestEqual(TEXT("late events after owner purge are refused"), stream_partitions::Load(Fixture._World, LateLoad)._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::StaleEvent);
    const auto Reregistered = stream_partitions::Register_ManifestOwner(Fixture._World, Fixture._Owner, VolumeId, Make_EmptyBundleLike(Bundle));
    if (NOT TestEqual(TEXT("the same volume can register after teardown"), Reregistered._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published) || NOT TestTrue(TEXT("a re-registration receives a newer owner lifetime fence"), Reregistered._OwnerInstance > Load._OwnerInstance)) { return false; }
    const auto BeforeOldOwnerEvent = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestEqual(TEXT("a stale old-owner event is refused after re-registration"), stream_partitions::Load(Fixture._World, LateLoad)._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::StaleEvent);
    const auto AfterOldOwnerEvent = world_fields::TryGet_StreamOwnerSnapshot(Fixture._World, VolumeId);
    TestTrue(TEXT("a stale old-owner event leaves the new empty owner publication unchanged"), BeforeOldOwnerEvent.IsSet() && AfterOldOwnerEvent.IsSet() && Get_SnapshotMatches(*BeforeOldOwnerEvent, *AfterOldOwnerEvent));
    Load._OwnerInstance = Reregistered._OwnerInstance; Load._Generation = 1;
    TestEqual(TEXT("a new owner lifetime accepts generation one"), stream_partitions::Load(Fixture._World, Load)._Status, stream_partitions::ECk_GroundNav_StreamPartitionLifecycleStatus::Published);
    return true;
}

#endif // WITH_EDITOR && WITH_DEV_AUTOMATION_TESTS
