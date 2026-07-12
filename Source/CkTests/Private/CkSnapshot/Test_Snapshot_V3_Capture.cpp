// Phase 3A v3-capture gates (spec §4.2). CaptureClassification proves the provenance filter (EngineOwned /
// ConstructSpawned / RuntimeSpawned counts, unlabeled-child skip, audit warning). RecipeParamsHandleRemap proves a
// FCk_Handle inside RuntimeSpawned spawn params is captured through FSnapshotContext handle-remap (round-trips to the
// sibling's saved-id via a reader stub). Both run on a bare FEcsWorld, composing each provenance class by hand.

#include "CkSnapshot/Snapshot/CkSnapshot_CaptureV3.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/SaveKey/CkSnapshot_SaveKey_Fragment.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/EntityScript/CkEntityScript_SpawnRecipe.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_HandleWalk.h"

#include "CkLabel/CkLabel_Utils.h"
#include "CkPhysics/Velocity/CkVelocity_Utils.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h" // FCk_Test_DynFrag_WithHandle (params struct with a handle)

#include "CkCore/Macros/CkMacros.h"

#include "NativeGameplayTags.h"
#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"
#include "UObject/Package.h"

#include "Misc/AutomationTest.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_V3_ConstructLabel, "Test.V3.ConstructLabel");

namespace ck_test_snapshot_v3
{
    // Deserialize a v3 param/payload blob back to an FInstancedStruct: symmetric with
    // ck::snapshot::SerializeInstancedStruct (proxy archive + a default FSnapshotContext, which on a reader with no
    // continuous-loader reads each handle's RAW saved id back — no remap, which is what the capture wrote).
    auto DeserializeBlob(const TArray<uint8>& InBytes) -> FInstancedStruct
    {
        auto Reader = FMemoryReader{InBytes, /*bIsPersistent=*/true};
        constexpr auto LoadIfFindFails = true;
        auto Proxy = FObjectAndNameAsStringProxyArchive{Reader, LoadIfFindFails};
        Proxy.ArIsSaveGame = false;
        Proxy.SetIsPersistent(true);

        auto Context = ck::FSnapshotContext{};

        auto Out = FInstancedStruct{};
        Out.Serialize(Proxy);
        ck::snapshot::RemapHandles(Out.GetScriptStruct(), Out.GetMutableMemory(), Proxy, Context);
        return Out;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_CaptureClassification_Test,
    "Ck.Snapshot.V3.CaptureClassification",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_CaptureClassification_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    auto* RawRegistry = ck::registry_table::TryResolve(RegistryHandle);
    if (NOT TestNotNull(TEXT("Resolved raw entt registry"), RawRegistry))
    { return false; }

    // EngineOwned — a level actor's SaveKey.
    auto EngineEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    EngineEntity.Add<FFragment_SaveKey>(FGuid::NewGuid());

    // ConstructSpawned (labeled) — persisted, adopted by (owner, label) on load.
    auto ConstructEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    ConstructEntity.Add<ck::FTag_ConstructSpawned>();
    UCk_Utils_GameplayLabel_UE::Add(ConstructEntity, TAG_Test_V3_ConstructLabel);

    // ConstructSpawned (UNLABELED) carrying a Produce payload — save-transient (skipped) + audit warning.
    auto UnlabeledEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    UnlabeledEntity.Add<ck::FTag_ConstructSpawned>();
    UCk_Utils_Velocity_UE::Add(UnlabeledEntity,
        FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, FVector{1.0, 0.0, 0.0}},
        ECk_Replication::DoesNotReplicate);

    // RuntimeSpawned — a retained recipe.
    auto RuntimeEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto* Holder = NewObject<UCk_EntityScript_SpawnRecipe_UE>(GetTransientPackage());
        Holder->Populate(UCk_EntityScript_UE::StaticClass(), FInstancedStruct{});
        RuntimeEntity.Add<ck::FFragment_SpawnRecipe>(TStrongObjectPtr<UCk_EntityScript_SpawnRecipe_UE>{Holder});
    }

    auto ByteWriter = FBufferArchive{};
    auto Header = FCk_Snapshot_HeaderV3{};
    const auto Result = ck::snapshot::Run_CaptureV3_Registry(*RawRegistry, RegistryHandle, /*World=*/nullptr, ByteWriter, Header);

    TestEqual(TEXT("v3 capture succeeded"), static_cast<int32>(Result), static_cast<int32>(ECk_SnapshotResult::Success));

    TestEqual(TEXT("One EngineOwned entity"),      Header.Get_EngineOwnedCount(),      1);
    TestEqual(TEXT("One ConstructSpawned entity"), Header.Get_ConstructSpawnedCount(), 1);
    TestEqual(TEXT("One RuntimeSpawned entity"),   Header.Get_RuntimeSpawnedCount(),   1);
    TestEqual(TEXT("Three persisted entities"),    Header.Get_EntityCount(),           3);
    TestEqual(TEXT("One unlabeled ConstructSpawned skipped"),
        Header.Get_UnlabeledConstructSkippedCount(), 1);
    TestEqual(TEXT("Unlabeled child with a payload raised one audit"),
        Header.Get_UnlabeledWithPayloadAuditCount(), 1);
    TestTrue(TEXT("v3 stream is non-empty"), ByteWriter.Num() > 0);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_RecipeParamsHandleRemap_Test,
    "Ck.Snapshot.V3.RecipeParamsHandleRemap",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_RecipeParamsHandleRemap_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    auto* RawRegistry = ck::registry_table::TryResolve(RegistryHandle);
    if (NOT TestNotNull(TEXT("Resolved raw entt registry"), RawRegistry))
    { return false; }

    // The sibling the recipe params point at — persisted (EngineOwned) so the capture's forward-ref guard passes.
    auto Sibling = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    Sibling.Add<FFragment_SaveKey>(FGuid::NewGuid());
    const auto SiblingSavedId = static_cast<uint32>(Sibling.Get_Entity().Get_ID());

    // A RuntimeSpawned entity whose spawn params carry a handle to the sibling.
    auto RuntimeEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto Params = FCk_Test_DynFrag_WithHandle{};
        Params.Marker = 77;
        Params.TargetHandle = Sibling;

        auto* Holder = NewObject<UCk_EntityScript_SpawnRecipe_UE>(GetTransientPackage());
        Holder->Populate(UCk_EntityScript_UE::StaticClass(), FInstancedStruct::Make(Params));
        RuntimeEntity.Add<ck::FFragment_SpawnRecipe>(TStrongObjectPtr<UCk_EntityScript_SpawnRecipe_UE>{Holder});
    }

    auto ByteWriter = FBufferArchive{};
    auto Header = FCk_Snapshot_HeaderV3{};
    const auto Result = ck::snapshot::Run_CaptureV3_Registry(*RawRegistry, RegistryHandle, /*World=*/nullptr, ByteWriter, Header);
    if (NOT TestEqual(TEXT("v3 capture succeeded"),
        static_cast<int32>(Result), static_cast<int32>(ECk_SnapshotResult::Success)))
    { return false; }

    // ---- Reader stub: deserialize the tables, then the RuntimeSpawned entry's params blob ----
    auto Reader = FMemoryReader{ByteWriter, /*bIsPersistent=*/true};
    auto Tables = FCk_Snapshot_V3_Tables{};
    FCk_Snapshot_V3_Tables::StaticStruct()->SerializeItem(Reader, &Tables, /*Defaults=*/nullptr);

    const FCk_Snapshot_V3_EntityEntry* RuntimeEntry = nullptr;
    for (const auto& Entry : Tables.Get_Entities())
    {
        if (Entry.Get_Provenance() == ECk_Snapshot_V3_Provenance::RuntimeSpawned)
        { RuntimeEntry = &Entry; }
    }
    if (NOT TestNotNull(TEXT("Found the RuntimeSpawned entry"), RuntimeEntry))
    { return false; }

    const auto ParamsOut = ck_test_snapshot_v3::DeserializeBlob(RuntimeEntry->Get_SpawnParamsBytes());
    if (NOT TestTrue(TEXT("Params blob deserialized to the test struct"),
        ParamsOut.GetScriptStruct() == FCk_Test_DynFrag_WithHandle::StaticStruct()))
    { return false; }

    const auto& OutParams = ParamsOut.Get<FCk_Test_DynFrag_WithHandle>();
    TestEqual(TEXT("Scalar param round-tripped"), OutParams.Marker, 77);

    const auto RemappedSavedId = static_cast<uint32>(OutParams.TargetHandle.Get_Entity().Get_ID());
    return TestEqual(TEXT("Params handle references the sibling's saved-id"),
        static_cast<int64>(RemappedSavedId), static_cast<int64>(SiblingSavedId));
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
