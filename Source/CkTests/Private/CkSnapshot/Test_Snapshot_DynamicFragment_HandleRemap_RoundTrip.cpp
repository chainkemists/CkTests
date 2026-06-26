// Low-level C++ automation test: does a DYNAMIC fragment (the mechanism AngelScript fragments use) survive a
// CkSnapshot capture -> wipe -> restore, and is its cross-entity handle remapped to the restored entity?
//
// AS fragments are stored wrapped in ck::FFragment_DynamicFragment_Data inside PER-TYPE NAMED entt storages
// keyed by UCk_Utils_DynamicFragment_UE::Get_StorageId(StructType). Get_Fragment/Has_Fragment read from those
// named storages. There are three places this can break across a snapshot, and this test distinguishes them by
// asserting in order:
//   1. Survival  — the capture loop does a single get<FFragment_DynamicFragment_Data>() which only traverses the
//                  DEFAULT storage, not the named per-type storages. If those aren't captured, the fragment is
//                  GONE after restore (Has_Fragment == false).
//   2. Data      — even the default-storage copy serializes _StructData via meta=(SaveGame) (a metadata string,
//                  not the real CPF_SaveGame flag), so the scalar payload can round-trip empty.
//   3. Handle    — the dynamic wrapper has no custom SerializeSnapshot, so the FInstancedStruct's handle field
//                  never reaches FSnapshotContext::Snapshot_Handle and is NOT remapped to the restored entity.
//
// Drives the registry-level entry points directly, mirroring Test_Snapshot_SaveKey_RoundTrip.cpp.

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveKey/CkSnapshot_SaveKey_Fragment.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkDynamic/CkDynamic_Fragment.h"   // ck::FFragment_DynamicFragment_Data
#include "CkDynamic/CkDynamic_Utils.h"      // UCk_Utils_DynamicFragment_UE

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include <StructUtils/InstancedStruct.h>

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_HandleRemap_RoundTrip_Test,
    "Ck.Snapshot.DynamicFragment.HandleRemap.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_HandleRemap_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto OwnerGuid   = FGuid(0x0A0A0A0A, 0x0B0B0B0B, 0x0C0C0C0C, 0x0D0D0D0D);
    const auto TargetAGuid  = FGuid(0x1A1A1A1A, 0x2B2B2B2B, 0x3C3C3C3C, 0x4D4D4D4D);
    const auto TargetBGuid  = FGuid(0x5E5E5E5E, 0x6F6F6F6F, 0x70707070, 0x81818181);
    constexpr auto KnownMarker = int32{4242};

    // ---- Arrange: a private ECS world with an Owner entity that holds a dynamic fragment pointing at a Target -----
    auto EcsWorld = ck::FEcsWorld{};

    auto* RawRegistry = ck::registry_table::TryResolve(EcsWorld.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("Resolved raw entt registry from FEcsWorld"), RawRegistry))
    { return false; }

    auto OwnerEntity   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto TargetEntityA = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    auto TargetEntityB = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(EcsWorld.Get_Registry());
    if (NOT TestTrue(TEXT("Owner + both Target entities are valid"),
            ck::IsValid(OwnerEntity) && ck::IsValid(TargetEntityA) && ck::IsValid(TargetEntityB)))
    { return false; }

    // SaveKeys make each entity re-findable after the restore wipes the registry and reassigns ids.
    OwnerEntity.Add<FFragment_SaveKey>(OwnerGuid);
    TargetEntityA.Add<FFragment_SaveKey>(TargetAGuid);
    TargetEntityB.Add<FFragment_SaveKey>(TargetBGuid);

    // Compose the dynamic fragment on Owner: a single handle to A, plus an array [A, B] (the QuickUseSelector shape).
    auto Fixture = FCk_Test_DynFrag_WithHandle{};
    Fixture.Marker       = KnownMarker;
    Fixture.TargetHandle = TargetEntityA;
    Fixture.TargetArray  = { TargetEntityA, TargetEntityB };
    UCk_Utils_DynamicFragment_UE::Add_Fragment(
        OwnerEntity, FInstancedStruct::Make(Fixture), ECk_Replication::DoesNotReplicate);

    if (NOT TestTrue(TEXT("Pre-capture: Owner has the dynamic fragment"),
            UCk_Utils_DynamicFragment_UE::Has_Fragment(OwnerEntity, FCk_Test_DynFrag_WithHandle::StaticStruct())))
    { return false; }

    const auto SavedTargetAId = TargetEntityA.Get_Entity().Get_ID();

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

    // ---- Re-find restored Owner + Target by their SaveKeys (pre-restore handles are stale) ----------------------
    auto RestoredOwner   = TOptional<entt::entity>{};
    auto RestoredTargetA = TOptional<entt::entity>{};
    auto RestoredTargetB = TOptional<entt::entity>{};
    for (const auto Entity : RawRegistry->view<FFragment_SaveKey>())
    {
        const auto& Key = RawRegistry->get<FFragment_SaveKey>(Entity).Get_Key();
        if (Key == OwnerGuid)   { RestoredOwner   = Entity; }
        if (Key == TargetAGuid) { RestoredTargetA = Entity; }
        if (Key == TargetBGuid) { RestoredTargetB = Entity; }
    }
    if (NOT TestTrue(TEXT("Re-found restored Owner + both Targets by SaveKey"),
            RestoredOwner.IsSet() && RestoredTargetA.IsSet() && RestoredTargetB.IsSet()))
    { return false; }

    // ---- ASSERTION 1: the dynamic fragment SURVIVED (its named per-type storage was captured) ------------------
    const auto StorageId = UCk_Utils_DynamicFragment_UE::Get_StorageId(FCk_Test_DynFrag_WithHandle::StaticStruct());
    auto& DynStorage = RawRegistry->storage<ck::FFragment_DynamicFragment_Data>(StorageId);

    if (NOT TestTrue(TEXT("Restored Owner still carries the dynamic fragment (named storage was captured)"),
            DynStorage.contains(RestoredOwner.GetValue())))
    { return false; } // bail: the remaining assertions all read the (missing) fragment.

    const auto& RestoredInst = DynStorage.get(RestoredOwner.GetValue()).Get_StructData();
    if (NOT TestTrue(TEXT("Restored dynamic fragment holds the fixture struct type"),
            RestoredInst.GetScriptStruct() == FCk_Test_DynFrag_WithHandle::StaticStruct()))
    { return false; }

    const auto& RestoredFixture = RestoredInst.Get<FCk_Test_DynFrag_WithHandle>();

    // ---- ASSERTION 2: the scalar payload round-tripped ----------------------------------------------------------
    TestEqual(TEXT("Marker scalar survived the round-trip"), RestoredFixture.Marker, KnownMarker);

    // ---- ASSERTION 3: the single handle was REMAPPED to the restored Target A ----------------------------------
    const auto RemappedTargetAId = RestoredFixture.TargetHandle.Get_Entity().Get_ID();
    TestTrue(TEXT("Single dynamic-fragment handle was remapped to the restored Target A"),
        RemappedTargetAId == RestoredTargetA.GetValue());

    // ---- ASSERTION 4: the ARRAY of handles round-tripped + each element remapped (QuickUseSelector shape) ------
    if (TestEqual(TEXT("Restored handle array has both elements"), RestoredFixture.TargetArray.Num(), 2))
    {
        TestTrue(TEXT("Array handle [0] was remapped to the restored Target A"),
            RestoredFixture.TargetArray[0].Get_Entity().Get_ID() == RestoredTargetA.GetValue());
        TestTrue(TEXT("Array handle [1] was remapped to the restored Target B"),
            RestoredFixture.TargetArray[1].Get_Entity().Get_ID() == RestoredTargetB.GetValue());
    }

    AddInfo(FString::Printf(TEXT("Target A id: saved [%u] -> restored [%u]; single handle resolved to [%u]"),
        static_cast<uint32>(SavedTargetAId),
        static_cast<uint32>(RestoredTargetA.GetValue()),
        static_cast<uint32>(RemappedTargetAId)));

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
