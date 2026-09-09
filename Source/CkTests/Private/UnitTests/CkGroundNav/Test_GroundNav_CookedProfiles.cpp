// Cooked GroundNav profile bundles through the real volume Setup path.
//
// The assets are transient UObjects in their convention packages. No package is saved: this pins the
// runtime lookup, bundle admission and atomic world-field publication without an editor boot or cook.

#include "CkCore/Time/CkTime.h"
#include "CkCore/Validation/CkIsValid.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"

#include "CkGroundNav/Backend/CkGroundNav_GeometryBackend_Stub.h"
#include "CkGroundNav/Bake/CkGroundNav_Fingerprint.h"
#include "CkGroundNav/Bake/CkGroundNav_LinkTypes.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedFieldIndex.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedFieldLoad.h"
#include "CkGroundNav/Cook/CkGroundNav_CookedTile.h"
#include "CkGroundNav/Field/CkGroundNav_Field.h"
#include "CkGroundNav/Field/CkGroundNav_FieldSerialize.h"
#include "CkGroundNav/Field/CkGroundNav_TileBake.h"
#include "CkGroundNav/Facade/CkGroundNav_WorldFieldRegistry.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Processor.h"
#include "CkGroundNav/Volume/CkGroundNavVolume_Utils.h"

#include "CkShapes/Capsule/CkShapeCapsule_Fragment_Data.h"

#include "../CkUnitTest_Common.h"

#include <Engine/World.h>
#include <Misc/PackageName.h>
#include <Misc/ScopeExit.h>
#include <Misc/Guid.h>
#include <NativeGameplayTags.h>
#include <UObject/Package.h>
#include <UObject/StrongObjectPtr.h>

// --------------------------------------------------------------------------------------------------------------------

using ck::tests::kCkUnitTestFlags;

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_CookedProfile_A, "CkTests.GroundNav.CookedProfile.A");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_CkTests_GroundNav_CookedProfile_B, "CkTests.GroundNav.CookedProfile.B");

namespace ck_test_groundnav_cookedprofiles
{
    constexpr auto kInformEngineOfWorld = false;
    const auto kCookKey = FName{TEXT("SharedCookKey")};

    struct FSourceLevels
    {
        FName _A;
        FName _B;
    };

    auto Make_SourceLevels() -> FSourceLevels
    {
        const auto Root = FString::Printf(TEXT("/Game/CkTests/CookedProfiles/%s"),
            *FGuid::NewGuid().ToString(EGuidFormats::Digits));
        return {FName{FString::Printf(TEXT("%s/LevelA"), *Root)}, FName{FString::Printf(TEXT("%s/LevelB"), *Root)}};
    }

    struct FInstalledAssets
    {
        TArray<TStrongObjectPtr<UCk_GroundNav_CookedFieldIndex_UE>> _Indices;
        TArray<TStrongObjectPtr<UCk_GroundNav_CookedTile_UE>> _Tiles;

        void Release()
        {
            for (const auto& Index : _Indices)
            { if (Index.IsValid()) { Index->ClearFlags(RF_Standalone); Index->MarkAsGarbage(); } }
            for (const auto& Tile : _Tiles)
            { if (Tile.IsValid()) { Tile->ClearFlags(RF_Standalone); Tile->MarkAsGarbage(); } }
            _Indices.Reset();
            _Tiles.Reset();
        }
    };

    auto Make_Params(FName InSourceLevel, FName InCookKey = kCookKey) -> FCk_Fragment_GroundNavVolume_ParamsData
    {
        auto Config = FCk_GroundNav_BakeConfig{25.0f, 10.0f};
        Config.Set_TileSizeUu(400.0f);
        auto Profile = FCk_GroundNav_AgentProfile{
            FCk_AnyShape{FCk_ShapeCapsule_Dimensions{70.0f, 20.0f}}};
        auto Params = FCk_Fragment_GroundNavVolume_ParamsData{
            FBox{FVector{0.0, 0.0, -50.0}, FVector{800.0, 800.0, 300.0}}, Config, Profile};
        Params.Set_CookKey(InCookKey);
        Params.Set_CookLevelPackage(InSourceLevel);
        Params.Set_AutoBuildOnSetup(ECk_EnableDisable::Disable);
        Params.Get_ProfileVariants().Emplace(TAG_CkTests_GroundNav_CookedProfile_A.GetTag(), Profile);
        Params.Get_ProfileVariants().Emplace(TAG_CkTests_GroundNav_CookedProfile_B.GetTag(), Profile);
        return Params;
    }

    auto Get_Fingerprint(const FCk_Fragment_GroundNavVolume_ParamsData& InParams) -> uint64
    {
        auto Variants = TArray<TPair<FName, FCk_GroundNav_AgentProfile>>{};

        for (const auto& Variant : InParams.Get_ProfileVariants())
        { Variants.Emplace(Variant.Get_ProfileTag().GetTagName(), Variant.Get_Profile()); }

        return ck::groundnav::Get_InputFingerprint(InParams.Get_VolumeBounds(), InParams.Get_Config(),
            InParams.Get_Profile(), {}, {}, InParams.Get_MergeTunables(), InParams.Get_MaxClearanceUu(), Variants,
            InParams.Get_DataLayerSelector())._Value;
    }

    auto Install_Field(
        const FCk_Fragment_GroundNavVolume_ParamsData& InParams,
        FGameplayTag InProfileTag,
        FInstalledAssets& InOutAssets,
        bool InHasWalkableGround = false) -> bool
    {
        auto FieldParams = ck::groundnav::Get_VolumeFieldParams(InParams, {}, {});

        for (const auto& Variant : InParams.Get_ProfileVariants())
        {
            if (Variant.Get_ProfileTag() == InProfileTag)
            { FieldParams._Profile = Variant.Get_Profile(); }
        }

        auto Field = ck::groundnav::FCk_GroundNav_Field{};
        const auto Ground = InHasWalkableGround
            ? TArray<FBox>{FBox{FVector{-400.0, -400.0, -10.0}, FVector{1200.0, 1200.0, 0.0}}}
            : TArray<FBox>{};
        const auto Backend = ck::groundnav::FCk_GroundNav_GeometryBackend_Stub{Ground};

        if (NOT ck::groundnav::DoBake_Field(Backend, FieldParams, ck::groundnav::FCk_GroundNav_Epoch{1}, Field).Get_IsCompleted())
        { return false; }

        const auto Fingerprint = Get_Fingerprint(InParams);
        const auto LatticeKey = ck::groundnav::Get_CookedLatticeKey(FieldParams);
        auto TileRefs = TArray<TSoftObjectPtr<UCk_GroundNav_CookedTile_UE>>{};

        for (const auto& FieldTile : Field._Tiles)
        {
            const auto Coord = FIntPoint{FieldTile._Coord._X, FieldTile._Coord._Y};
            const auto TilePath = ck::groundnav::Get_CookedTileAssetPath(ck::groundnav::kCookedDataRootPath,
                InParams.Get_CookLevelPackage().ToString(), InParams.Get_CookKey(), Coord, InProfileTag,
                InParams.Get_DataLayerSelector());
            auto* Package = CreatePackage(*FPackageName::ObjectPathToPackageName(TilePath));
            auto* Tile = NewObject<UCk_GroundNav_CookedTile_UE>(Package,
                *FPackageName::ObjectPathToObjectName(TilePath), RF_Public | RF_Transient);

            if (Package == nullptr || Tile == nullptr)
            { return false; }

            auto Blob = TArray<uint8>{};
            ck::groundnav::Write_Tile(Field, FieldTile._Coord, Blob);
            Tile->Set_FormatVersion(ck::groundnav::kFieldBlobFormatVersion);
            Tile->Set_TileCoord(Coord);
            Tile->Set_StreamingVolumeId(InParams.Get_StreamingVolumeId());
            Tile->Set_WorldBounds(ck::groundnav::Get_TileBounds(
                FieldParams.Get_TileBakeParams(FieldTile._Coord, ck::groundnav::FCk_GroundNav_Epoch{})));
            Tile->Set_DataLayerNames(InParams.Get_DataLayerSelector().Get_LayerNames());
            Tile->Set_ProfileTag(InProfileTag);
            Tile->Set_Fingerprint(Fingerprint);
            Tile->Set_LatticeKey(LatticeKey);
            Tile->Set_Blob(MoveTemp(Blob));
            Tile->Set_ContentHash(ck::groundnav::Get_CookedTileContentHash(Tile->Get_Blob()));
            TileRefs.Emplace(Tile);
            InOutAssets._Tiles.Emplace(Tile);
        }

        const auto IndexPath = ck::groundnav::Get_CookedIndexAssetPath(ck::groundnav::kCookedDataRootPath,
            InParams.Get_CookLevelPackage().ToString(), InParams.Get_CookKey(), InProfileTag,
            InParams.Get_DataLayerSelector());
        auto* IndexPackage = CreatePackage(*FPackageName::ObjectPathToPackageName(IndexPath));
        auto* Index = NewObject<UCk_GroundNav_CookedFieldIndex_UE>(IndexPackage,
            *FPackageName::ObjectPathToObjectName(IndexPath), RF_Public | RF_Transient);

        if (IndexPackage == nullptr || Index == nullptr)
        { return false; }

        Index->Set_LevelPackage(InParams.Get_CookLevelPackage());
        Index->Set_CookKey(InParams.Get_CookKey());
        Index->Set_StreamingVolumeId(InParams.Get_StreamingVolumeId());
        Index->Set_DataLayerNames(InParams.Get_DataLayerSelector().Get_LayerNames());
        Index->Set_ProfileTag(InProfileTag);
        Index->Set_Fingerprint(Fingerprint);
        Index->Set_FormatVersion(ck::groundnav::kFieldBlobFormatVersion);
        Index->Set_LatticeKey(LatticeKey);
        Index->Set_Tiles(MoveTemp(TileRefs));
        InOutAssets._Indices.Emplace(Index);
        return true;
    }

    auto Install_Bundle(const FCk_Fragment_GroundNavVolume_ParamsData& InParams, FInstalledAssets& InOutAssets,
                         int32 InProfileCount = 2, bool InHasWalkableGround = false) -> bool
    {
        if (NOT Install_Field(InParams, {}, InOutAssets, InHasWalkableGround))
        { return false; }

        for (auto Index = 0; Index < InProfileCount; ++Index)
        {
            if (NOT Install_Field(InParams, InParams.Get_ProfileVariants()[Index].Get_ProfileTag(), InOutAssets,
                InHasWalkableGround))
            { return false; }
        }

        return true;
    }

    auto Make_World(const TCHAR* InName) -> UWorld*
    { return UWorld::CreateWorld(EWorldType::Game, kInformEngineOfWorld, FName{InName}); }

    auto Add_AndSetup(UWorld& InWorld, const FCk_Fragment_GroundNavVolume_ParamsData& InParams) -> FCk_Handle_GroundNavVolume
    {
        const auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(&InWorld);
        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
        auto Volume = UCk_Utils_GroundNavVolume_UE::Add(Owner, InParams);

        if (NOT ck::IsValid(Volume))
        { return {}; }

        ck::FProcessor_GroundNavVolume_Setup{WorldEntity.Get_RegistryView()}.ForEachEntity(
            FCk_Time{}, Volume, Volume.Get<ck::FFragment_GroundNavVolume_Params>(),
            Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>());
        return Volume;
    }

    auto DoDrain_LinkRequests(UWorld& InWorld, FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        const auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(&InWorld);
        ck::FProcessor_GroundNavVolume_HandleLinkRequests{WorldEntity.Get_RegistryView()}.ForEachEntity(
            FCk_Time{},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_Params>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_Links>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_LinkRequests>());
    }

    auto DoDerive_Links(UWorld& InWorld, FCk_Handle_GroundNavVolume& InVolume) -> void
    {
        const auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(&InWorld);
        ck::FProcessor_GroundNavVolume_LinkDerive{WorldEntity.Get_RegistryView()}.ForEachEntity(
            FCk_Time{},
            InVolume,
            InVolume.Get<ck::FFragment_GroundNavVolume_Links>(),
            InVolume.Get<ck::FFragment_GroundNavVolume_BuiltField>());
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedProfiles_SetupPublishesAllProfilesAtomically,
    "CkTests.UnitTests.CkGroundNav.CookedProfiles.SetupPublishesAllProfilesAtomically",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedProfiles_SetupPublishesAllProfilesAtomically::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedprofiles;
    auto Assets = FInstalledAssets{};
    auto* World = Make_World(TEXT("CkGroundNavCookedProfilesComplete"));
    if (NOT TestNotNull(TEXT("the runtime world exists"), World)) { return false; }
    ON_SCOPE_EXIT { Assets.Release(); World->DestroyWorld(kInformEngineOfWorld); };

    const auto SourceLevels = Make_SourceLevels();
    const auto Params = Make_Params(SourceLevels._A, FName{TEXT("CompleteBundle")});
    if (NOT TestTrue(TEXT("the default and two variant bundles install"), Install_Bundle(Params, Assets))) { return false; }

    const auto Volume = Add_AndSetup(*World, Params);
    if (NOT TestTrue(TEXT("the volume is created"), ck::IsValid(Volume))) { return false; }
    const auto& Built = Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>();
    TestTrue(TEXT("setup loads cooked ground"), Built.Get_CookStatus() == ECk_GroundNav_CookStatus::Cooked);
    TestTrue(TEXT("the default field publishes"), Built.Get_Field().IsValid());
    TestEqual(TEXT("both requested variants publish with the default"), Built.Get_VariantFields().Num(), 2);
    const auto Probe = FVector{100.0, 100.0, 0.0};
    const auto PublishedDefault = ck::groundnav::world_fields::TryGet_Field(World, Probe);
    const auto PublishedA = ck::groundnav::world_fields::TryGet_Field(World, Probe,
        TAG_CkTests_GroundNav_CookedProfile_A.GetTag());
    const auto PublishedB = ck::groundnav::world_fields::TryGet_Field(World, Probe,
        TAG_CkTests_GroundNav_CookedProfile_B.GetTag());
    TestTrue(TEXT("the registry contains the published default field"), PublishedDefault == Built.Get_Field());
    const auto* BuiltA = Built.Get_VariantFields().Find(TAG_CkTests_GroundNav_CookedProfile_A.GetTag());
    const auto* BuiltB = Built.Get_VariantFields().Find(TAG_CkTests_GroundNav_CookedProfile_B.GetTag());
    TestTrue(TEXT("the registry contains profile A"), BuiltA != nullptr && PublishedA.IsValid() && PublishedA == *BuiltA);
    TestTrue(TEXT("the registry contains profile B"), BuiltB != nullptr && PublishedB.IsValid() && PublishedB == *BuiltB);
    TestTrue(TEXT("default and both variants share the setup epoch"),
        PublishedDefault != nullptr && PublishedA != nullptr && PublishedB != nullptr &&
        PublishedDefault->_Epoch == PublishedA->_Epoch && PublishedDefault->_Epoch == PublishedB->_Epoch);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_StreamingAcceptance_CookedSetupRefreshesAndUnregisters,
    "CkTests.UnitTests.CkGroundNav.StreamingAcceptance.Volume.CookedSetupRefreshesAndUnregisters",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_StreamingAcceptance_CookedSetupRefreshesAndUnregisters::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedprofiles;

    constexpr auto kStreamingVolumeId = int32{7001};
    const auto VolumeId = ck::groundnav::FCk_GroundNav_VolumeId{kStreamingVolumeId};
    const auto Probe = FVector{100.0, 100.0, 0.0};
    const auto LinkStart = FVector{200.0, 200.0, 0.0};
    const auto LinkEnd = FVector{600.0, 200.0, 0.0};

    auto Assets = FInstalledAssets{};
    auto* World = Make_World(TEXT("CkGroundNavStreamingProductionLifecycle"));
    if (NOT TestNotNull(TEXT("the runtime world exists"), World))
    { return false; }
    ON_SCOPE_EXIT { Assets.Release(); World->DestroyWorld(kInformEngineOfWorld); };

    const auto SourceLevels = Make_SourceLevels();
    auto Params = Make_Params(SourceLevels._A, FName{TEXT("StreamingProductionLifecycle")});
    Params.Set_StreamingVolumeId(kStreamingVolumeId);

    if (NOT TestTrue(TEXT("the complete cooked bundle installs with navigable ground"),
        Install_Bundle(Params, Assets, 2, true)))
    { return false; }

    auto Volume = Add_AndSetup(*World, Params);
    if (NOT TestTrue(TEXT("the positive-id volume is created"), ck::IsValid(Volume)))
    { return false; }
    ON_SCOPE_EXIT
    {
        if (ck::groundnav::world_fields::TryGet_StreamOwnerSnapshot(World, VolumeId).IsSet())
        {
            ck::FProcessor_GroundNavVolume_Unpublish::ForEachEntity(
                FCk_Time{},
                Volume,
                Volume.Get<ck::FFragment_GroundNavVolume_Params>(),
                Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>());
        }
    };

    const auto& InitialBuilt = Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>();
    if (NOT TestTrue(TEXT("setup registers the volume as a streaming owner"),
        InitialBuilt.Get_IsStreamOwnerRegistered()))
    { return false; }

    const auto Initial = ck::groundnav::world_fields::TryGet_StreamOwnerSnapshot(World, VolumeId);
    if (NOT TestTrue(TEXT("the registry exposes the setup publication"), Initial.IsSet()))
    { return false; }

    TestTrue(TEXT("setup publishes the registry's composed default for queries"),
        ck::groundnav::world_fields::TryGet_Field(World, Probe) == Initial->_DefaultField);
    TestTrue(TEXT("the producer and registry publication agree on the setup epoch"),
        Initial->_DefaultField.IsValid() && InitialBuilt.Get_Field().IsValid() &&
        Initial->_DefaultField->_Epoch == InitialBuilt.Get_Field()->_Epoch);
    TestEqual(TEXT("setup publishes every authored profile through the streaming owner"),
        Initial->_VariantFields.Num(), 2);

    const auto WorldEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(World);
    auto LinkEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldEntity);
    if (NOT TestTrue(TEXT("a link entity is created"), ck::IsValid(LinkEntity)))
    { return false; }

    UCk_Utils_GroundNavVolume_UE::Request_Link(
        Volume,
        FCk_Request_GroundNavVolume_Link{
            LinkEntity,
            FCk_GroundNav_LinkRecord{INDEX_NONE, LinkStart, LinkEnd}},
        {});
    DoDrain_LinkRequests(*World, Volume);
    DoDerive_Links(*World, Volume);

    const auto Refreshed = ck::groundnav::world_fields::TryGet_StreamOwnerSnapshot(World, VolumeId);
    if (NOT TestTrue(TEXT("the link derive leaves a complete streaming-owner snapshot"), Refreshed.IsSet()))
    { return false; }

    const auto& RefreshedBuilt = Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>();
    TestTrue(TEXT("the link derive refreshes the streaming owner to a newer epoch"),
        Refreshed->_Epoch.Get_IsNewerThan(Initial->_Epoch));
    TestTrue(TEXT("the refreshed registry default is the current query publication"),
        ck::groundnav::world_fields::TryGet_Field(World, Probe) == Refreshed->_DefaultField);
    TestTrue(TEXT("the producer and registry publication agree on the refreshed epoch"),
        Refreshed->_DefaultField.IsValid() && RefreshedBuilt.Get_Field().IsValid() &&
        Refreshed->_DefaultField->_Epoch == RefreshedBuilt.Get_Field()->_Epoch);
    TestEqual(TEXT("the production derive retains the admitted link in the producer"),
        RefreshedBuilt.Get_Field()->Get_ResolvedLinkCount(), 1);
    TestEqual(TEXT("the refresh preserves every authored profile"), Refreshed->_VariantFields.Num(), 2);
    TestTrue(TEXT("the refresh records the admitted link identity"),
        Refreshed->_DefaultPublishNote._ChangedLinkEpochsSinceGeometry.Contains(0));

    auto VolumeEntity = Volume.ConvertToHandle();
    UCk_Utils_EntityLifetime_UE::Request_DestroyEntity(VolumeEntity);
    ck::FProcessor_GroundNavVolume_Unpublish::ForEachEntity(
        FCk_Time{},
        Volume,
        Volume.Get<ck::FFragment_GroundNavVolume_Params>(),
        Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>());

    TestFalse(TEXT("the teardown unregisters the streaming owner"),
        ck::groundnav::world_fields::TryGet_StreamOwnerSnapshot(World, VolumeId).IsSet());
    TestFalse(TEXT("the torn-down owner answers no field query"),
        ck::groundnav::world_fields::TryGet_Field(World, Probe).IsValid());
    TestEqual(TEXT("the torn-down owner leaves no live field entry"),
        ck::groundnav::world_fields::Get_FieldCount(World), 0);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedProfiles_MissingVariantDoesNotPartiallyPublish,
    "CkTests.UnitTests.CkGroundNav.CookedProfiles.MissingVariantDoesNotPartiallyPublish",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedProfiles_MissingVariantDoesNotPartiallyPublish::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedprofiles;
    auto Assets = FInstalledAssets{};
    auto* World = Make_World(TEXT("CkGroundNavCookedProfilesMissing"));
    if (NOT TestNotNull(TEXT("the runtime world exists"), World)) { return false; }
    ON_SCOPE_EXIT { Assets.Release(); World->DestroyWorld(kInformEngineOfWorld); };

    const auto SourceLevels = Make_SourceLevels();
    const auto Params = Make_Params(SourceLevels._A, FName{TEXT("MissingBundle")});
    if (NOT TestTrue(TEXT("only default and first variant install"), Install_Bundle(Params, Assets, 1))) { return false; }

    const auto Volume = Add_AndSetup(*World, Params);
    if (NOT TestTrue(TEXT("the volume is created"), ck::IsValid(Volume))) { return false; }
    const auto& Built = Volume.Get<ck::FFragment_GroundNavVolume_BuiltField>();
    TestTrue(TEXT("the missing final variant is reported"), Built.Get_CookStatus() == ECk_GroundNav_CookStatus::MissingCook);
    TestFalse(TEXT("no default field leaks from the incomplete bundle"), Built.Get_Field().IsValid());
    TestTrue(TEXT("no variant field leaks from the incomplete bundle"), Built.Get_VariantFields().IsEmpty());
    TestFalse(TEXT("the incomplete default was never published"), ck::groundnav::world_fields::TryGet_Field(World,
        FVector{100.0, 100.0, 0.0}).IsValid());
    TestFalse(TEXT("the incomplete profile was never published"), ck::groundnav::world_fields::TryGet_Field(World,
        FVector{100.0, 100.0, 0.0}, TAG_CkTests_GroundNav_CookedProfile_A.GetTag()).IsValid());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_GroundNav_CookedProfiles_CookKeyIsUniqueOnlyWithinItsSourceLevel,
    "CkTests.UnitTests.CkGroundNav.CookedProfiles.CookKeyIsUniqueOnlyWithinItsSourceLevel",
    kCkUnitTestFlags)

bool FCkTest_GroundNav_CookedProfiles_CookKeyIsUniqueOnlyWithinItsSourceLevel::RunTest(const FString& Parameters)
{
    using namespace ck_test_groundnav_cookedprofiles;
    auto Assets = FInstalledAssets{};
    auto* World = Make_World(TEXT("CkGroundNavCookedProfilesSourceLevels"));
    if (NOT TestNotNull(TEXT("the runtime world exists"), World)) { return false; }
    ON_SCOPE_EXIT { Assets.Release(); World->DestroyWorld(kInformEngineOfWorld); };

    const auto SourceLevels = Make_SourceLevels();
    const auto ParamsA = Make_Params(SourceLevels._A);
    const auto ParamsB = Make_Params(SourceLevels._B);
    if (NOT TestTrue(TEXT("both source-level bundles install"),
        Install_Bundle(ParamsA, Assets) && Install_Bundle(ParamsB, Assets))) { return false; }

    const auto VolumeA = Add_AndSetup(*World, ParamsA);
    const auto VolumeB = Add_AndSetup(*World, ParamsB);
    AddExpectedError(TEXT("another volume in this world already carries the cook key"), EAutomationExpectedErrorFlags::Contains, -1);
    const auto DuplicateA = Add_AndSetup(*World, ParamsA);

    if (NOT TestTrue(TEXT("all volumes are created"),
        ck::IsValid(VolumeA) && ck::IsValid(VolumeB) && ck::IsValid(DuplicateA))) { return false; }

    TestTrue(TEXT("the same key from source level A publishes"),
        VolumeA.Get<ck::FFragment_GroundNavVolume_BuiltField>().Get_CookStatus() == ECk_GroundNav_CookStatus::Cooked);
    TestTrue(TEXT("the same key from distinct source level B also publishes"),
        VolumeB.Get<ck::FFragment_GroundNavVolume_BuiltField>().Get_CookStatus() == ECk_GroundNav_CookStatus::Cooked);
    TestFalse(TEXT("the duplicate within source level A is not admitted"),
        DuplicateA.Get<ck::FFragment_GroundNavVolume_BuiltField>().Get_Field().IsValid());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
