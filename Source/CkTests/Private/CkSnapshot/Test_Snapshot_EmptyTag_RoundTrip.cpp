// Low-level C++ automation test for CkSnapshot "Tier-T" empty-tag round-trip.
//
// Proves an EMPTY ECS tag (no data members) survives capture -> wipe -> restore with its presence intact.
// entt's snapshot serializes empty types as entity-presence only (zero per-instance bytes); this test confirms
// the CkSnapshot framework now admits empty tags through CK_REGISTER_SNAPSHOTABLE (Tier-T) and round-trips them.
//
// Mirrors the registry-core harness of Test_Snapshot_Core_RoundTrip.cpp (standalone ck::FEcsWorld, no PIE).

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_FragmentRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Writer.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Reader.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Tag/CkTag.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
// Test-only empty tag. CK_DEFINE_ECS_TAG produces an empty struct (static_asserts std::is_empty_v) AND auto-registers
// it as snapshotable via the tag registry — no explicit CK_REGISTER_SNAPSHOTABLE needed. The capture tag pass picks
// it up like any production tag.

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_SnapshotTest_EmptyTag);
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_EmptyTag_RoundTrip_Test,
    "Ck.Snapshot.EmptyTag.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_EmptyTag_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    // ---- Arrange: stand up a private ECS world and tag one entity --------------------------------------------
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto TaggedEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("Tagged entity is valid"), ck::IsValid(TaggedEntity)))
    { return false; }

    TaggedEntity.Add<ck::FTag_SnapshotTest_EmptyTag>();
    TestTrue(TEXT("Tag present pre-capture"), TaggedEntity.Has<ck::FTag_SnapshotTest_EmptyTag>());

    // ---- Act (capture) ---------------------------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture result is Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    // ---- Act (restore: wipe-then-restore in place) -----------------------------------------------------------
    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);

    TestEqual(TEXT("Restore result is Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    TestEqual(TEXT("No fragment types were skipped"), Report.Get_SkippedFragmentTypes().Num(), 0);

    // ---- Assert: exactly one entity carries the restored empty tag -------------------------------------------
    auto TaggedCount = 0;
    RawRegistry->view<ck::FTag_SnapshotTest_EmptyTag>().each([&](auto /*Entity*/) { ++TaggedCount; });

    TestEqual(TEXT("Exactly one entity carries the restored empty tag"), TaggedCount, 1);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
