// Phase 3A v3-capture gates (spec §4.2). CaptureClassification proves the provenance filter (EngineOwned /
// ConstructSpawned / RuntimeSpawned counts, unlabeled-child skip, audit warning). RecipeParamsHandleRemap proves a
// FCk_Handle inside RuntimeSpawned spawn params is captured through FSnapshotContext handle-remap (round-trips to the
// sibling's saved-id via a reader stub). Both run on a bare FEcsWorld, composing each provenance class by hand.

#include "CkSnapshot/Snapshot/CkSnapshot_CaptureV3.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Settings/CkSnapshot_Settings.h"
#include "CkEcs/Snapshot/CkSaveKey_Fragment.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/EntityScript/CkEntityScript_SpawnRecipe.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_HandleWalk.h"
#include "CkEcs/Snapshot/CkSnapshot_RestoreMarker.h"
#include "CkEcsExt/OwningActor/CkActorSpawnIntent_Fragment.h"

#include "CkLabel/CkLabel_Utils.h"
#include "CkPhysics/Velocity/CkVelocity_Utils.h"

#include "Test_Snapshot_DynamicFragment_Fixtures.h" // FCk_Test_DynFrag_WithHandle (params struct with a handle)

#include "CkCore/Macros/CkMacros.h"

#include "Misc/ScopeExit.h"
#include "NativeGameplayTags.h"
#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"
#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"
#include "UObject/Package.h"

#include "CkCore/Validation/CkIsValid.h" // ck::IsValid (v3 map-backed disk smoke)

#include "Misc/AutomationTest.h"

#include <StructUtils/InstancedStruct.h>

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_V3_ConstructLabel, "Test.V3.ConstructLabel");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_V3_PayloadLabel, "Test.V3.PayloadLabel");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_V3_ReconstructOnlyLabel, "Test.V3.ReconstructOnlyLabel");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_V3_ReconstructOnlyDescendantLabel, "Test.V3.ReconstructOnlyDescendantLabel");
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_V3_SaveTransientDescendantLabel, "Test.V3.SaveTransientDescendantLabel");

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

    // A normal labeled child still persists its payload.
    auto PayloadEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    PayloadEntity.Add<ck::FTag_ConstructSpawned>();
    UCk_Utils_GameplayLabel_UE::Add(PayloadEntity, TAG_Test_V3_PayloadLabel);
    UCk_Utils_Velocity_UE::Add(PayloadEntity,
        FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, FVector{2.0, 0.0, 0.0}},
        ECk_Replication::DoesNotReplicate);

    // A labeled payload-bearing child whose feature explicitly declares reconstruct/reset-only state. It must not
    // become a ConstructSpawned row or affect the ordinary unlabeled-payload audit.
    auto ReconstructOnlyEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    ReconstructOnlyEntity.Add<ck::FTag_ConstructSpawned>();
    ReconstructOnlyEntity.Add<ck::FTag_Snapshot_ReconstructOnly>();
    UCk_Utils_GameplayLabel_UE::Add(ReconstructOnlyEntity, TAG_Test_V3_ReconstructOnlyLabel);
    UCk_Utils_Velocity_UE::Add(ReconstructOnlyEntity,
        FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, FVector{3.0, 0.0, 0.0}},
        ECk_Replication::DoesNotReplicate);

    // RuntimeSpawned — a retained recipe.
    auto RuntimeEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    {
        auto* Holder = NewObject<UCk_EntityScript_SpawnRecipe_UE>(GetTransientPackage());
        Holder->Populate(UCk_EntityScript_UE::StaticClass(), FInstancedStruct{});
        RuntimeEntity.Add<ck::FFragment_SpawnRecipe>(TStrongObjectPtr<UCk_EntityScript_SpawnRecipe_UE>{Holder});
    }

    // RuntimeSpawned with stable identity — explicit actor respawn intent wins over SaveKey provenance.
    const auto RespawnKey = FGuid::NewGuid();
    auto KeyedRuntimeEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    KeyedRuntimeEntity.Add<FFragment_SaveKey>(RespawnKey);
    KeyedRuntimeEntity.Add<FFragment_ActorSpawnIntent>(AActor::StaticClass()->GetPathName());
    {
        auto* Holder = NewObject<UCk_EntityScript_SpawnRecipe_UE>(GetTransientPackage());
        Holder->Populate(UCk_EntityScript_UE::StaticClass(), FInstancedStruct{});
        KeyedRuntimeEntity.Add<ck::FFragment_SpawnRecipe>(TStrongObjectPtr<UCk_EntityScript_SpawnRecipe_UE>{Holder});
    }

    // This gate asserts the dropped-payload audit, whose probe CaptureAuditMode gates — a project shipping
    // Disabled would otherwise make the assertion unreachable rather than failing honestly.
    auto* SnapshotSettings = GetMutableDefault<UCk_Snapshot_Settings>();
    const auto RestoreAuditMode = SnapshotSettings->Get_CaptureAuditMode();
    SnapshotSettings->TestOnly_Set_CaptureAuditMode(ECk_Snapshot_CaptureAuditMode::Summary);
    ON_SCOPE_EXIT { SnapshotSettings->TestOnly_Set_CaptureAuditMode(RestoreAuditMode); };

    auto ByteWriter = FBufferArchive{};
    auto Header = FCk_Snapshot_HeaderV3{};
    const auto Result = ck::snapshot::Run_CaptureV3_Registry(*RawRegistry, RegistryHandle, /*World=*/nullptr, ByteWriter, Header);

    TestEqual(TEXT("v3 capture succeeded"), static_cast<int32>(Result), static_cast<int32>(ECk_SnapshotResult::Success));

    TestEqual(TEXT("One EngineOwned entity"),      Header.Get_EngineOwnedCount(),      1);
    TestEqual(TEXT("Two ConstructSpawned entities"), Header.Get_ConstructSpawnedCount(), 2);
    TestEqual(TEXT("Two RuntimeSpawned entities"),  Header.Get_RuntimeSpawnedCount(),   2);
    TestEqual(TEXT("Five persisted entities"),      Header.Get_EntityCount(),           5);
    TestEqual(TEXT("Only normal payload-bearing child persisted a payload"), Header.Get_PayloadCount(), 1);
    TestEqual(TEXT("One unlabeled ConstructSpawned skipped"),
        Header.Get_UnlabeledConstructSkippedCount(), 1);
    TestEqual(TEXT("Unlabeled child with a payload raised one audit"),
        Header.Get_UnlabeledWithPayloadAuditCount(), 1);
    TestTrue(TEXT("v3 stream is non-empty"), ByteWriter.Num() > 0);

    auto Reader = FMemoryReader{ByteWriter, /*bIsPersistent=*/true};
    auto Tables = FCk_Snapshot_V3_Tables{};
    FCk_Snapshot_V3_Tables::StaticStruct()->SerializeItem(Reader, &Tables, /*Defaults=*/nullptr);

    const FCk_Snapshot_V3_EntityEntry* KeyedRuntimeEntry = nullptr;
    for (const auto& Entry : Tables.Get_Entities())
    {
        if (Entry.Get_SaveKey() == RespawnKey)
        { KeyedRuntimeEntry = &Entry; break; }
    }
    if (NOT TestNotNull(TEXT("Found the keyed runtime entry"), KeyedRuntimeEntry))
    { return false; }

    TestEqual(TEXT("Keyed actor is RuntimeSpawned"), KeyedRuntimeEntry->Get_Provenance(),
        ECk_Snapshot_V3_Provenance::RuntimeSpawned);
    TestEqual(TEXT("Runtime entry retained stable SaveKey"), KeyedRuntimeEntry->Get_SaveKey(), RespawnKey);
    TestEqual(TEXT("Runtime entry retained actor class"), KeyedRuntimeEntry->Get_ActorClassPath(),
        AActor::StaticClass()->GetPathName());
    TestEqual(TEXT("Runtime entry retained script class"), KeyedRuntimeEntry->Get_ScriptClassPath(),
        UCk_EntityScript_UE::StaticClass()->GetPathName());

    const auto ReconstructOnlyLabel = TAG_Test_V3_ReconstructOnlyLabel.GetTag().ToString();
    const auto bReconstructOnlyPersisted = Tables.Get_Entities().ContainsByPredicate(
        [&ReconstructOnlyLabel](const FCk_Snapshot_V3_EntityEntry& Entry)
        { return Entry.Get_Label() == ReconstructOnlyLabel; });
    TestFalse(TEXT("Reconstruct-only child omitted without a row or payload"), bReconstructOnlyPersisted);

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_CaptureAncestorExclusion_Test,
    "Ck.Snapshot.V3.CaptureAncestorExclusion",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_CaptureAncestorExclusion_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    auto* RawRegistry = ck::registry_table::TryResolve(RegistryHandle);
    if (NOT TestNotNull(TEXT("Resolved raw entt registry"), RawRegistry))
    { return false; }

    // A reconstruct-only owner intentionally omits its whole construction subtree, including a named child that
    // would otherwise be ConstructSpawned and carries a hydration payload. The child also carries SaveTransient to
    // pin the precedence rule: the enclosing reconstruct-only contract suppresses the false data-loss audit.
    auto ReconstructOnlyOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    ReconstructOnlyOwner.Add<ck::FTag_Snapshot_ReconstructOnly>();
    auto ReconstructOnlyChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(ReconstructOnlyOwner, {});
    ReconstructOnlyChild.Add<ck::FTag_ConstructSpawned>();
    ReconstructOnlyChild.Add<ck::FTag_Snapshot_SaveTransient>();
    UCk_Utils_GameplayLabel_UE::Add(ReconstructOnlyChild, TAG_Test_V3_ReconstructOnlyDescendantLabel);
    UCk_Utils_Velocity_UE::Add(ReconstructOnlyChild,
        FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, FVector{4.0, 0.0, 0.0}},
        ECk_Replication::DoesNotReplicate);

    // SaveTransient also owns its descendants: the named, payload-bearing child must be omitted rather than become
    // an orphaned ConstructSpawned row. The warning is intentional and inspected in the focused test log.
    auto SaveTransientOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    SaveTransientOwner.Add<ck::FTag_Snapshot_SaveTransient>();
    auto SaveTransientChild = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(SaveTransientOwner, {});
    SaveTransientChild.Add<ck::FTag_ConstructSpawned>();
    UCk_Utils_GameplayLabel_UE::Add(SaveTransientChild, TAG_Test_V3_SaveTransientDescendantLabel);
    UCk_Utils_Velocity_UE::Add(SaveTransientChild,
        FCk_Fragment_Velocity_ParamsData{ECk_LocalWorld::World, FVector{5.0, 0.0, 0.0}},
        ECk_Replication::DoesNotReplicate);

    auto ByteWriter = FBufferArchive{};
    auto Header = FCk_Snapshot_HeaderV3{};
    const auto Result = ck::snapshot::Run_CaptureV3_Registry(*RawRegistry, RegistryHandle, /*World=*/nullptr, ByteWriter, Header);

    TestEqual(TEXT("v3 capture succeeded"), static_cast<int32>(Result), static_cast<int32>(ECk_SnapshotResult::Success));
    TestEqual(TEXT("Ancestor-excluded subtrees produced no rows"), Header.Get_EntityCount(), 0);
    TestEqual(TEXT("Ancestor-excluded subtrees produced no payloads"), Header.Get_PayloadCount(), 0);

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

// --------------------------------------------------------------------------------------------------------------------

// Ck.Snapshot.V3.InstancedStructDiskSmoke — validates Fork A (Phase 3B): a v3 blob written save-mode (raw saved id)
// is deserialized through the map-backed FSnapshotContext and the handle field REMAPS to the live target the map
// points at (not the saved id); a raw id absent from the map rewrites to an INVALID handle (dangling-ref semantics).
// Registry-level (bare FEcsWorld) — cheap, no travel.

namespace ck_test_snapshot_v3
{
    // Save-mode serialize (mirrors ck::snapshot::SerializeInstancedStruct): raw handle ids written.
    auto SerializeBlob_Save(const FInstancedStruct& InStruct) -> TArray<uint8>
    {
        auto Blob = TArray<uint8>{};
        if (InStruct.GetScriptStruct() == nullptr) { return Blob; }
        auto Writer = FMemoryWriter{Blob, /*bIsPersistent=*/true};
        constexpr auto LoadIfFindFails = true;
        auto Proxy = FObjectAndNameAsStringProxyArchive{Writer, LoadIfFindFails};
        Proxy.ArIsSaveGame = false;
        Proxy.SetIsPersistent(true);
        auto Ctx = ck::FSnapshotContext{};
        auto Copy = FInstancedStruct{InStruct};
        Copy.Serialize(Proxy);
        ck::snapshot::RemapHandles(Copy.GetScriptStruct(), Copy.GetMutableMemory(), Proxy, Ctx);
        return Blob;
    }

    // Load-mode deserialize through the v3 saved-id -> live-handle map (the Phase-3B FSnapshotContext mode).
    auto DeserializeBlob_Mapped(const TArray<uint8>& InBytes, const TMap<uint32, FCk_Handle>& InMap,
                                FCk_RegistryHandle InReg) -> FInstancedStruct
    {
        auto Reader = FMemoryReader{InBytes, /*bIsPersistent=*/true};
        constexpr auto LoadIfFindFails = true;
        auto Proxy = FObjectAndNameAsStringProxyArchive{Reader, LoadIfFindFails};
        Proxy.ArIsSaveGame = false;
        Proxy.SetIsPersistent(true);
        auto Ctx = ck::FSnapshotContext{&InMap, InReg};
        auto Out = FInstancedStruct{};
        Out.Serialize(Proxy);
        ck::snapshot::RemapHandles(Out.GetScriptStruct(), Out.GetMutableMemory(), Proxy, Ctx);
        return Out;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_V3_InstancedStructDiskSmoke_Test,
    "Ck.Snapshot.V3.InstancedStructDiskSmoke",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_V3_InstancedStructDiskSmoke_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& CkRegistry = EcsWorld.Get_Registry();
    const auto RegistryHandle = CkRegistry.Get_RegistryHandle();

    auto* RawRegistry = ck::registry_table::TryResolve(RegistryHandle);
    if (NOT TestNotNull(TEXT("Resolved raw entt registry"), RawRegistry))
    { return false; }

    // The id written into the blob (the "saved" target) and a DISTINCT live target the map redirects to.
    auto SavedTarget = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    auto LiveTarget  = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(CkRegistry);
    const auto SavedTargetId = static_cast<uint32>(SavedTarget.Get_Entity().Get_ID());

    auto Params = FCk_Test_DynFrag_WithHandle{};
    Params.Marker = 99;
    Params.TargetHandle = SavedTarget;

    const auto Blob = ck_test_snapshot_v3::SerializeBlob_Save(FInstancedStruct::Make(Params));
    if (NOT TestTrue(TEXT("blob non-empty"), Blob.Num() > 0))
    { return false; }

    auto Map = TMap<uint32, FCk_Handle>{};
    Map.Add(SavedTargetId, LiveTarget);

    const auto Out = ck_test_snapshot_v3::DeserializeBlob_Mapped(Blob, Map, RegistryHandle);
    if (NOT TestTrue(TEXT("deserialized to the test struct"),
        Out.GetScriptStruct() == FCk_Test_DynFrag_WithHandle::StaticStruct()))
    { return false; }

    const auto& OutParams = Out.Get<FCk_Test_DynFrag_WithHandle>();
    TestEqual(TEXT("scalar param round-tripped over disk"), OutParams.Marker, 99);

    // The whole point: the handle written as SavedTarget's id was REMAPPED to LiveTarget by the map-backed context.
    TestEqual(TEXT("handle remapped to the live target (not the saved id)"),
        static_cast<int64>(OutParams.TargetHandle.Get_Entity().Get_ID()),
        static_cast<int64>(LiveTarget.Get_Entity().Get_ID()));
    TestTrue(TEXT("remapped handle is valid"), ck::IsValid(OutParams.TargetHandle));

    // And a raw id NOT in the map rewrites to an INVALID handle (dangling-ref semantics).
    auto EmptyMap = TMap<uint32, FCk_Handle>{};
    const auto OutUnmapped = ck_test_snapshot_v3::DeserializeBlob_Mapped(Blob, EmptyMap, RegistryHandle);
    const auto& UnmappedParams = OutUnmapped.Get<FCk_Test_DynFrag_WithHandle>();
    TestFalse(TEXT("unmapped handle rewrites to invalid"), ck::IsValid(UnmappedParams.TargetHandle));

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
