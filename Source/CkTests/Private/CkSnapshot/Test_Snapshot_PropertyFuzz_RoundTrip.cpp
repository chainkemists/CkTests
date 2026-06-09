// Property / fuzz round-trip test for the CkSnapshot registry core.
//
// Hand-written gates exercise a handful of fixed scenarios; this exercises MANY randomized entity graphs
// to find combinations those gates miss. It builds N entities, each carrying a unique index, a random
// payload, and a handle to a randomly-chosen neighbour (forming an arbitrary directed graph incl. self-loops),
// then asserts the save -> wipe -> restore contract holds over the whole graph:
//   - every node's payload round-trips to its SAVED value (mutations between capture and restore are reverted);
//   - every node's neighbour handle is REMAPPED to the restored neighbour (the graph topology survives);
//   - a second capture reproduces the same entity/node count (semantic idempotence).
//
// Deterministic: a fixed FRandomStream seed makes failures reproducible. (Date.now()/rand() are avoided.)

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
#include "Math/RandomStream.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// Tier-C fuzz node: a stable index, a random payload, and a neighbour handle routed through Snapshot_Handle.
struct FFragment_FuzzTest_Node
{
    CK_GENERATED_BODY(FFragment_FuzzTest_Node);
    using IsSnapshotable = void;

public:
    int32      _Index   = -1;
    int32      _Payload = 0;
    FCk_Handle _Neighbor;

public:
    auto SerializeSnapshot(FArchive& InAr, ck::FSnapshotContext& InCtx) -> void
    {
        InAr << _Index;
        InAr << _Payload;
        InCtx.Snapshot_Handle(InAr, _Neighbor);
    }
};

CK_REGISTER_SNAPSHOTABLE(FFragment_FuzzTest_Node);

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_PropertyFuzz_RoundTrip_Test,
    "Ck.Snapshot.Property.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_PropertyFuzz_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    constexpr auto NumNodes = 48;
    auto Rng = FRandomStream{/*Seed=*/1337};

    auto EcsWorld = ck::FEcsWorld{};
    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry"), RawRegistry))
    { return false; }

    // ---- Arrange: build a random directed graph over N entities -------------------------------------------------
    auto Entities = TArray<FCk_Handle>{};
    Entities.Reserve(NumNodes);
    for (auto Index = 0; Index < NumNodes; ++Index)
    { Entities.Add(UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry())); }

    auto ExpectedPayload  = TArray<int32>{}; ExpectedPayload.SetNum(NumNodes);
    auto ExpectedNeighbor = TArray<int32>{}; ExpectedNeighbor.SetNum(NumNodes); // neighbour INDEX

    for (auto Index = 0; Index < NumNodes; ++Index)
    {
        const auto Payload      = Rng.RandRange(-1000000, 1000000);
        const auto NeighborIdx  = Rng.RandRange(0, NumNodes - 1); // may be self
        ExpectedPayload[Index]  = Payload;
        ExpectedNeighbor[Index] = NeighborIdx;

        auto& Node     = Entities[Index].Add<FFragment_FuzzTest_Node>();
        Node._Index    = Index;
        Node._Payload  = Payload;
        Node._Neighbor = Entities[NeighborIdx];
    }

    // ---- Act (capture) ------------------------------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};
    const auto CaptureResult = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header);
    if (NOT TestEqual(TEXT("Capture is Success"),
            static_cast<uint8>(CaptureResult), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    // ---- Mutate live payloads so a successful restore visibly reverts them ---------------------------------------
    for (auto Index = 0; Index < NumNodes; Index += 7)
    { Entities[Index].Get<FFragment_FuzzTest_Node>()._Payload += 999999; }

    // ---- Act (restore) ------------------------------------------------------------------------------------------
    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header);
    if (NOT TestEqual(TEXT("Restore is Success"),
            static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }
    TestEqual(TEXT("No fragment types skipped"), Report.Get_SkippedFragmentTypes().Num(), 0);

    // ---- Assert: re-find restored nodes by their stable index, verify payload + graph topology -------------------
    auto RestoredByIndex = TMap<int32, ck::SnapshotEntityType>{};
    {
        auto NodeView = RawRegistry->view<FFragment_FuzzTest_Node>();
        auto NodeCount = 0;
        for (const auto Entity : NodeView)
        {
            ++NodeCount;
            const auto& Node = NodeView.get<FFragment_FuzzTest_Node>(Entity);
            if (Node._Index >= 0 && Node._Index < NumNodes)
            { RestoredByIndex.Add(Node._Index, Entity); }
        }
        TestEqual(TEXT("All N nodes survived restore"), NodeCount, NumNodes);
        TestEqual(TEXT("All N node indices are present + unique"), RestoredByIndex.Num(), NumNodes);
    }

    auto PayloadFailures  = 0;
    auto TopologyFailures = 0;
    {
        auto NodeView = RawRegistry->view<FFragment_FuzzTest_Node>();
        for (const auto Entity : NodeView)
        {
            const auto& Node = NodeView.get<FFragment_FuzzTest_Node>(Entity);
            if (Node._Index < 0 || Node._Index >= NumNodes)
            { continue; }

            if (Node._Payload != ExpectedPayload[Node._Index])
            { ++PayloadFailures; }

            // Neighbour handle must have been REMAPPED to the restored neighbour entity.
            const auto ExpectedNeighborEntity = RestoredByIndex.FindRef(ExpectedNeighbor[Node._Index]);
            const auto ActualNeighborId       = Node._Neighbor.Get_Entity().Get_ID();
            if (ActualNeighborId != ExpectedNeighborEntity)
            { ++TopologyFailures; }
        }
    }
    TestEqual(TEXT("Every node payload reverted to its SAVED value"), PayloadFailures, 0);
    TestEqual(TEXT("Every neighbour handle remapped to the restored neighbour (graph topology survived)"), TopologyFailures, 0);

    // ---- Assert: idempotence — a second capture reproduces the same node count -----------------------------------
    {
        auto Buffer2 = FBufferArchive{};
        auto Header2 = FCk_Snapshot_Header{};
        const auto Recapture = ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer2, Header2);
        TestEqual(TEXT("Re-capture is Success"),
            static_cast<uint8>(Recapture), static_cast<uint8>(ECk_SnapshotResult::Success));
        TestEqual(TEXT("Re-capture entity count equals first capture"),
            Header2.Get_EntityCount(), Header.Get_EntityCount());
    }

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
