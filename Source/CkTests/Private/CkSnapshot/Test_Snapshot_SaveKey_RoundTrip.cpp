// Low-level C++ automation test for the CkSnapshot SaveKey round-trip (Phase-0 backbone regression guard).
//
// Proves FFragment_SaveKey._Key survives capture -> wipe -> restore. This is the Tier-A reflection path
// (USTRUCT, no custom SerializeSnapshot, serialized via UScriptStruct::SerializeItem under ArIsSaveGame=true),
// which is exactly the path the historic bug broke: _Key was UPROPERTY(meta=(SaveGame)) (metadata map, not the
// real CPF_SaveGame flag), so it round-tripped EMPTY. With the flag fixed, a non-empty GUID round-trips intact.
//
// Drives the registry-level entry points directly, mirroring Test_Snapshot_Core_RoundTrip.cpp:
//   ck::snapshot::Run_Capture_Registry / ck::snapshot::Run_Restore_Registry.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveKey/CkSnapshot_SaveKey_Fragment.h"
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

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_SaveKey_RoundTrip_Test,
    "Ck.Snapshot.SaveKey.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_SaveKey_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // A fixed, non-empty GUID. If Bug-1 regresses, the restored key is empty (all-zero) and the equality fails.
    const auto KnownGuid = FGuid(0x11112222, 0x33334444, 0x55556666, 0x77778888);

    // ---- Arrange: stand up a private ECS world and stamp one entity with a SaveKey ----------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto KeyedEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("Keyed entity is valid"), ck::IsValid(KeyedEntity)))
    { return false; }

    // Add<T>(args...) forwards to the fragment ctor (CK_DEFINE_CONSTRUCTORS(FFragment_SaveKey, _Key)).
    KeyedEntity.Add<FFragment_SaveKey>(KnownGuid);

    if (NOT TestTrue(TEXT("Pre-capture: live SaveKey matches the known GUID"),
            KeyedEntity.Get<FFragment_SaveKey>().Get_Key() == KnownGuid))
    { return false; }

    // ---- Act (capture) ----------------------------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    // ---- Act (restore: wipe-then-rebuild) ---------------------------------------------------------------------
    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    TestEqual(TEXT("No fragment types were skipped"), Report.Get_SkippedFragmentTypes().Num(), 0);

    // ---- Assert: the SaveKey GUID survived the round-trip non-empty + intact -----------------------------------
    // The pre-restore handle is stale (registry was cleared); re-find the restored entity by iterating the view.
    auto FoundCount = 0;
    for (const auto Entity : RawRegistry->view<FFragment_SaveKey>())
    {
        ++FoundCount;
        const auto& RestoredKey = RawRegistry->get<FFragment_SaveKey>(Entity);

        TestTrue(TEXT("Restored SaveKey GUID is non-empty (Bug-1 regression guard)"),
            RestoredKey.Get_Key().IsValid());
        TestTrue(TEXT("Restored SaveKey GUID equals the saved GUID"),
            RestoredKey.Get_Key() == KnownGuid);
    }

    TestEqual(TEXT("Exactly one entity carries the SaveKey fragment after restore"), FoundCount, 1);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
