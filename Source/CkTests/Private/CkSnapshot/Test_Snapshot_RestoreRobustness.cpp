// Robustness round-trips for the CkSnapshot registry core:
//   1. CrossRegistry.Rehome  — capture in world A, restore into a SEPARATE world B; restored handles must
//      re-home onto B and resolve there (fast unit coverage of the cross-world registry-rehome fix that was
//      previously only exercised by the slow MP seamless-travel gate). A negative control (restore without the
//      load-target handle) proves the re-home is what makes the difference.
//   2. RestoreTwice.Idempotent — restoring the same snapshot twice into a world yields identical state both times.
//   3. EmptyWorld.RoundTrip — capturing + restoring a world with no populated entities succeeds without crashing.

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkEcs/Snapshot/CkSnapshot_Context.h"
#include "CkEcs/Snapshot/CkSnapshot_FragmentRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Writer.h"
#include "CkEcs/Snapshot/CkSnapshot_Archive_Reader.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// Tier-C node: a stable index + a neighbour handle routed through Snapshot_Handle (so the handle's entity is
// remapped, and — when a load-target registry is supplied — its registry is re-homed).
struct FFragment_RobustnessTest_Node
{
    CK_GENERATED_BODY(FFragment_RobustnessTest_Node);
    using IsSnapshotable = void;

public:
    int32      _Index = -1;
    FCk_Handle _Neighbor;

public:
    auto SerializeSnapshot(FArchive& InAr, ck::FSnapshotContext& InCtx) -> void
    {
        InAr << _Index;
        InCtx.Snapshot_Handle(InAr, _Neighbor);
    }
};

CK_REGISTER_SNAPSHOTABLE(FFragment_RobustnessTest_Node);

namespace ck_robustness_test
{
    // Build a ring of N nodes in InWorld and capture it. Returns the captured buffer + header by out-param.
    static auto Build_And_Capture(
        ck::FEcsWorld& InWorld, int32 InNumNodes, FBufferArchive& OutBuffer, FCk_Snapshot_Header& OutHeader) -> bool
    {
        auto* Raw = ck::registry_table::TryResolve(InWorld.Get_Registry().Get_RegistryHandle());
        if (Raw == nullptr)
        { return false; }

        auto Entities = TArray<FCk_Handle>{};
        for (auto Index = 0; Index < InNumNodes; ++Index)
        { Entities.Add(UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InWorld.Get_Registry())); }
        for (auto Index = 0; Index < InNumNodes; ++Index)
        {
            auto& Node     = Entities[Index].Add<FFragment_RobustnessTest_Node>();
            Node._Index    = Index;
            Node._Neighbor = Entities[(Index + 1) % InNumNodes];
        }

        return ck::snapshot::Run_Capture_Registry(*Raw, OutBuffer, OutHeader) == ECk_SnapshotResult::Success;
    }
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_CrossRegistry_Rehome_Test,
    "Ck.Snapshot.CrossRegistry.Rehome",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_CrossRegistry_Rehome_Test::
    RunTest(const FString& /*InParameters*/)
{
    constexpr auto NumNodes = 5;

    // ---- Arrange: build + capture a handle ring in world A -----------------------------------------------------
    auto WorldA = ck::FEcsWorld{};
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};
    if (NOT TestTrue(TEXT("Captured ring in world A"),
            ck_robustness_test::Build_And_Capture(WorldA, NumNodes, Buffer, Header)))
    { return false; }

    // ---- Act + Assert (positive): restore into a SEPARATE world B WITH B's load-target registry handle --------
    {
        auto WorldB = ck::FEcsWorld{};
        auto* RawB = ck::registry_table::TryResolve(WorldB.Get_Registry().Get_RegistryHandle());
        if (NOT TestNotNull(TEXT("Resolved world B registry"), RawB))
        { return false; }

        auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
        const auto Report = ck::snapshot::Run_Restore_Registry(
            *RawB, Reader, Header, WorldB.Get_Registry().Get_RegistryHandle());
        TestEqual(TEXT("Restore into B is Success"),
            static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));

        auto ResolvedNeighbors = 0;
        auto NodeCount = 0;
        auto NodeView = RawB->view<FFragment_RobustnessTest_Node>();
        for (const auto Entity : NodeView)
        {
            ++NodeCount;
            const auto& Node = NodeView.get<FFragment_RobustnessTest_Node>(Entity);
            // The neighbour handle must RESOLVE in world B — i.e. its registry was re-homed onto B (not left
            // pointing at world A's slot). IncludePendingKill avoids the lifetime-system dependency after a raw
            // wipe-restore; we only care that the handle resolves to a live entity in B.
            if (ck::IsValid(Node._Neighbor, ck::IsValid_Policy_IncludePendingKill{}))
            { ++ResolvedNeighbors; }
        }
        TestEqual(TEXT("All N nodes restored into B"), NodeCount, NumNodes);
        TestEqual(TEXT("All neighbour handles re-homed + resolve in world B"), ResolvedNeighbors, NumNodes);
    }

    // ---- Act + Assert (negative control): restore WITHOUT a load-target handle — handles do NOT re-home -------
    {
        auto WorldC = ck::FEcsWorld{};
        auto* RawC = ck::registry_table::TryResolve(WorldC.Get_Registry().Get_RegistryHandle());
        if (NOT TestNotNull(TEXT("Resolved world C registry"), RawC))
        { return false; }

        auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
        const auto Report = ck::snapshot::Run_Restore_Registry(*RawC, Reader, Header); // no load-target handle
        TestEqual(TEXT("Restore into C is Success"),
            static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));

        auto ResolvedNeighbors = 0;
        auto NodeView = RawC->view<FFragment_RobustnessTest_Node>();
        for (const auto Entity : NodeView)
        {
            const auto& Node = NodeView.get<FFragment_RobustnessTest_Node>(Entity);
            if (ck::IsValid(Node._Neighbor, ck::IsValid_Policy_IncludePendingKill{}))
            { ++ResolvedNeighbors; }
        }
        // Without re-homing, the handle carries no live registry -> it must NOT resolve. This proves the
        // load-target handle is what makes the cross-registry case work (not an accident of same-id reuse).
        TestEqual(TEXT("Neighbour handles do NOT resolve without re-homing (negative control)"), ResolvedNeighbors, 0);
    }

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_RestoreTwice_Idempotent_Test,
    "Ck.Snapshot.RestoreTwice.Idempotent",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_RestoreTwice_Idempotent_Test::
    RunTest(const FString& /*InParameters*/)
{
    constexpr auto NumNodes = 6;

    auto World = ck::FEcsWorld{};
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};
    if (NOT TestTrue(TEXT("Captured ring"),
            ck_robustness_test::Build_And_Capture(World, NumNodes, Buffer, Header)))
    { return false; }

    auto* Raw = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved registry"), Raw))
    { return false; }

    const auto CountNodes = [&]() -> int32
    {
        auto Count = 0;
        for (const auto Entity : Raw->view<FFragment_RobustnessTest_Node>())
        { (void)Entity; ++Count; }
        return Count;
    };

    auto Reader1 = FMemoryReader{Buffer, true};
    const auto Report1 = ck::snapshot::Run_Restore_Registry(*Raw, Reader1, Header);
    TestEqual(TEXT("First restore Success"),
        static_cast<uint8>(Report1.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    const auto CountAfterFirst = CountNodes();
    TestEqual(TEXT("First restore reproduced all nodes"), CountAfterFirst, NumNodes);

    auto Reader2 = FMemoryReader{Buffer, true};
    const auto Report2 = ck::snapshot::Run_Restore_Registry(*Raw, Reader2, Header);
    TestEqual(TEXT("Second restore Success"),
        static_cast<uint8>(Report2.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    const auto CountAfterSecond = CountNodes();

    // Idempotence: restoring the SAME snapshot again (wipe-then-restore) yields the same node count, not a
    // doubling/merge.
    TestEqual(TEXT("Second restore is idempotent (same node count)"), CountAfterSecond, CountAfterFirst);
    TestEqual(TEXT("Restore report entity counts match"),
        Report2.Get_EntitiesRestored(), Report1.Get_EntitiesRestored());

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_EmptyWorld_RoundTrip_Test,
    "Ck.Snapshot.EmptyWorld.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_EmptyWorld_RoundTrip_Test::
    RunTest(const FString& /*InParameters*/)
{
    // A world with no populated test entities (only the FEcsWorld's own transient bookkeeping) must capture +
    // restore without error or crash.
    auto World = ck::FEcsWorld{};
    auto* Raw = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved registry"), Raw))
    { return false; }

    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};
    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*Raw, Buffer, Header);
    TestEqual(TEXT("Empty-world capture Success"),
        static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success));

    auto Reader = FMemoryReader{Buffer, true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*Raw, Reader, Header);
    TestEqual(TEXT("Empty-world restore Success"),
        static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    AddInfo(FString::Printf(TEXT("Empty-world restore skipped [%d] fragment types"),
        Report.Get_SkippedFragmentTypes().Num()));

    // Restoring an empty-ish snapshot into a fresh, separate world must also succeed.
    {
        auto World2 = ck::FEcsWorld{};
        auto* Raw2 = ck::registry_table::TryResolve(World2.Get_Registry().Get_RegistryHandle());
        if (NOT TestNotNull(TEXT("Resolved world2 registry"), Raw2))
        { return false; }
        auto Reader2 = FMemoryReader{Buffer, true};
        const auto Report2 = ck::snapshot::Run_Restore_Registry(
            *Raw2, Reader2, Header, World2.Get_Registry().Get_RegistryHandle());
        TestEqual(TEXT("Empty-world restore into fresh world Success"),
            static_cast<uint8>(Report2.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success));
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
