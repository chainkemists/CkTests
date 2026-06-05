// Multi-tag snapshot round-trip. Three distinct CK_DEFINE_ECS_TAG tags auto-register (no explicit
// CK_REGISTER_SNAPSHOTABLE). Entities carry overlapping tag sets; capture -> wipe -> restore must preserve each
// entity's exact tag membership (verified via co-presence views, which are robust to id remap).

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
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

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_SnapshotTest_MultiA);
    CK_DEFINE_ECS_TAG(FTag_SnapshotTest_MultiB);
    CK_DEFINE_ECS_TAG(FTag_SnapshotTest_MultiC);
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_MultiTag_RoundTrip_Test,
    "Ck.Snapshot.MultiTag.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_MultiTag_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry"), RawRegistry))
    { return false; }

    // E1: A+B   E2: B+C   E3: C
    auto E1 = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto E2 = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto E3 = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());

    E1.Add<ck::FTag_SnapshotTest_MultiA>();
    E1.Add<ck::FTag_SnapshotTest_MultiB>();
    E2.Add<ck::FTag_SnapshotTest_MultiB>();
    E2.Add<ck::FTag_SnapshotTest_MultiC>();
    E3.Add<ck::FTag_SnapshotTest_MultiC>();

    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};

    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);
    TestEqual(TEXT("Restore success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));

    const auto CountView = [&](auto View)
    {
        auto N = 0;
        for (const auto Entity : View) { (void)Entity; ++N; }
        return N;
    };

    TestEqual(TEXT("TagA present on exactly 1 entity"),  CountView(RawRegistry->view<ck::FTag_SnapshotTest_MultiA>()), 1);
    TestEqual(TEXT("TagB present on exactly 2 entities"), CountView(RawRegistry->view<ck::FTag_SnapshotTest_MultiB>()), 2);
    TestEqual(TEXT("TagC present on exactly 2 entities"), CountView(RawRegistry->view<ck::FTag_SnapshotTest_MultiC>()), 2);

    // Co-presence (id-remap-robust): A&B together is E1 only; B&C together is E2 only.
    TestEqual(TEXT("A&B co-present on exactly 1 entity (E1)"),
        CountView(RawRegistry->view<ck::FTag_SnapshotTest_MultiA, ck::FTag_SnapshotTest_MultiB>()), 1);
    TestEqual(TEXT("B&C co-present on exactly 1 entity (E2)"),
        CountView(RawRegistry->view<ck::FTag_SnapshotTest_MultiB, ck::FTag_SnapshotTest_MultiC>()), 1);
    TestEqual(TEXT("A&C never co-present"),
        CountView(RawRegistry->view<ck::FTag_SnapshotTest_MultiA, ck::FTag_SnapshotTest_MultiC>()), 0);

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
