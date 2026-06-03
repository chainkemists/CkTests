// Low-level C++ automation test for the CkSnapshot registry-core round-trip.
//
// Proves the save -> wipe -> restore contract on a standalone ck::FEcsWorld (no UWorld / PIE / subsystem):
//   1. A plain-value fragment round-trips its known field value.
//   2. The wipe-then-restore semantics actually replace the registry (mutating a live fragment between
//      capture and restore is reverted by the restore).
//   3. The entity-handle remap path (FSnapshotContext::Snapshot_Handle via continuous_loader::map) rewrites
//      a saved handle field to the restored target entity's live ID.
//
// This test drives the registry-level entry points directly:
//   ck::snapshot::Run_Capture_Registry / ck::snapshot::Run_Restore_Registry.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/Context/CkSnapshot_Context.h"
#include "CkSnapshot/Context/CkSnapshot_FragmentRegistry.h"
#include "CkSnapshot/Archive/CkSnapshot_Archive_Writer.h"
#include "CkSnapshot/Archive/CkSnapshot_Archive_Reader.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
// Test-only snapshotable fragments (Tier-C: non-USTRUCT, custom SerializeSnapshot — no UHT/.generated.h needed).
//
// Registered globally via CK_REGISTER_SNAPSHOTABLE at module load, so the manifest loop in Run_Capture_Registry
// picks them up like any production snapshotable fragment.
// --------------------------------------------------------------------------------------------------------------------

// Declared at file scope (single, unqualified identifiers) because CK_REGISTER_SNAPSHOTABLE token-pastes the
// type name into a generated struct name and cannot accept a namespace-qualified argument.

// Tier-C plain-value fragment: a single int32, serialized straight through the archive.
struct FFragment_SnapshotTest_Value
{
    CK_GENERATED_BODY(FFragment_SnapshotTest_Value);
    using IsSnapshotable = void;

public:
    int32 _Value = 0;

public:
    auto SerializeSnapshot(FArchive& InAr, ck::FSnapshotContext& /*InCtx*/) -> void
    {
        InAr << _Value;
    }
};

// Tier-C handle-ref fragment: holds an FCk_Handle and routes it through Snapshot_Handle so the
// continuous_loader remaps its entity ID on restore. Proves the ID-remap path.
struct FFragment_SnapshotTest_HandleRef
{
    CK_GENERATED_BODY(FFragment_SnapshotTest_HandleRef);
    using IsSnapshotable = void;

public:
    FCk_Handle _Target;

public:
    auto SerializeSnapshot(FArchive& InAr, ck::FSnapshotContext& InCtx) -> void
    {
        InCtx.Snapshot_Handle(InAr, _Target);
    }
};

// Registration must see the complete Archive writer/reader types (the std::function closures reference them).
CK_REGISTER_SNAPSHOTABLE(FFragment_SnapshotTest_Value);
CK_REGISTER_SNAPSHOTABLE(FFragment_SnapshotTest_HandleRef);

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_Core_RoundTrip_Test,
    "Ck.Snapshot.Core.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_Core_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    constexpr auto KnownValue = 4242;

    // ---- Arrange: stand up a private ECS world and populate it -------------------------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    // Target entity carries the known-value fragment. Referrer entity carries a handle pointing at the target.
    auto TargetEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto ReferrerEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    if (NOT TestTrue(TEXT("Target entity is valid"), ck::IsValid(TargetEntity)) ||
        NOT TestTrue(TEXT("Referrer entity is valid"), ck::IsValid(ReferrerEntity)))
    { return false; }

    TargetEntity.Add<FFragment_SnapshotTest_Value>().      _Value  = KnownValue;
    ReferrerEntity.Add<FFragment_SnapshotTest_HandleRef>(). _Target = TargetEntity;

    const auto SavedTargetEnttId = TargetEntity.Get_Entity().Get_ID();

    // ---- Act (capture) ----------------------------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    // FEcsWorld always carries its own transient bookkeeping entity, so the count is >= our two entities.
    const auto CapturedEntityCount = Header.Get_EntityCount();
    TestTrue(TEXT("Header recorded at least the two populated entities"), CapturedEntityCount >= 2);

    // ---- Mutate live state so a successful restore visibly reverts it ------------------------------------------
    {
        auto& LiveValue = TargetEntity.Get<FFragment_SnapshotTest_Value>();
        LiveValue._Value = KnownValue + 1000;
        TestEqual(TEXT("Live value was mutated pre-restore"), LiveValue._Value, KnownValue + 1000);
    }

    // ---- Act (restore) ----------------------------------------------------------------------------------------
    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    // The two fragment-carrying entities must survive restore. (The exact count is asserted via the
    // per-fragment views below; the transient bookkeeping entity may be culled by Loader.orphans() since
    // it carries no snapshotable fragment, so we only assert a floor here.)
    TestTrue(TEXT("Restore reproduced at least the two fragment-carrying entities"),
        Report.Get_EntitiesRestored() >= 2);
    TestEqual(TEXT("No fragment types were skipped"), Report.Get_SkippedFragmentTypes().Num(), 0);

    // ---- Assert: the value fragment round-tripped to its saved value -------------------------------------------
    // After wipe-then-restore the prior handles are stale (the registry was cleared). Re-find the restored
    // entities by iterating the raw registry's storages directly.
    auto RestoredTargetEnttId = TOptional<entt::entity>{};
    {
        auto ValueView = RawRegistry->view<FFragment_SnapshotTest_Value>();
        auto ValueCount = 0;

        for (const auto Entity : ValueView)
        {
            ++ValueCount;
            const auto& RestoredValue = ValueView.get<FFragment_SnapshotTest_Value>(Entity);
            TestEqual(TEXT("Restored value reverted to the SAVED value (not the mutated one)"),
                RestoredValue._Value, KnownValue);

            RestoredTargetEnttId = Entity;
        }

        TestEqual(TEXT("Exactly one entity carries the value fragment"), ValueCount, 1);
    }

    if (NOT TestTrue(TEXT("Found the restored target entity id"), RestoredTargetEnttId.IsSet()))
    { return false; }

    // ---- Assert: the handle field was REMAPPED to the restored target entity -----------------------------------
    {
        auto RefView = RawRegistry->view<FFragment_SnapshotTest_HandleRef>();
        auto RefCount = 0;

        for (const auto Entity : RefView)
        {
            ++RefCount;
            const auto& RestoredRef = RefView.get<FFragment_SnapshotTest_HandleRef>(Entity);
            const auto RestoredRefTargetId = RestoredRef._Target.Get_Entity().Get_ID();

            // The saved-time target id was remapped into the restored space; it must now equal the restored
            // target entity's live id (NOT the saved id, since continuous_loader allocates fresh ids).
            TestTrue(TEXT("Handle-ref entity id was remapped to the restored target entity"),
                RestoredRefTargetId == RestoredTargetEnttId.GetValue());

            AddInfo(FString::Printf(
                TEXT("Handle remap: saved target id [%u] -> restored target id [%u]"),
                static_cast<uint32>(SavedTargetEnttId),
                static_cast<uint32>(RestoredTargetEnttId.GetValue())));
        }

        TestEqual(TEXT("Exactly one entity carries the handle-ref fragment"), RefCount, 1);
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
