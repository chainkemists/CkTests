// Coverage suite that bulletproofs the dynamic-fragment snapshot path beyond the basic single-fragment round-trip
// (Test_Snapshot_DynamicFragment_HandleRemap_RoundTrip.cpp). Targets the riskiest new code -- the per-type
// named-storage enumeration in capture/restore and the recursive FCk_Handle walk in the dynamic wrapper's
// SerializeSnapshot -- plus save/load edge cases:
//
//   1. MultipleTypesOnOneEntity  -- two distinct dynamic-fragment types on one entity (two named storages) both survive.
//   2. MultipleEntitiesSameType  -- one named storage with several entity entries round-trips every entry.
//   3. PureDataNoHandles         -- a handle-free dynamic fragment round-trips its scalar + string data.
//   4. EmptyArrayAndInvalidHandle-- an empty TArray<handle> + a default (invalid) handle round-trip without desync.
//   5. NestedHandleRemaps        -- a handle one struct level deep is reached by the recursive walk and remapped.
//   6. SelfReferentialHandle     -- a handle pointing at its OWN entity remaps to the restored self.
//   7. DoubleRoundTrip           -- save -> restore -> save -> restore leaves the fragment + handle intact.

#include "Test_Snapshot_DynamicFragment_Fixtures.h"

#include "CkSnapshot/Snapshot/CkSnapshot_Capture.h"
#include "CkSnapshot/Snapshot/CkSnapshot_Restore.h"
#include "CkSnapshot/SaveKey/CkSnapshot_SaveKey_Fragment.h"
#include "CkSnapshot/SaveGame/CkSnapshot_Header.h"
#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"

#include "CkDynamic/CkDynamic_Fragment.h"
#include "CkDynamic/CkDynamic_Utils.h"

#include "CkEcs/World/CkEcsWorld.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Snapshot/CkSnapshot_Context.h" // ck::SnapshotRegistryType
#include "CkEcs/Registry/CkRegistry_SlotTable.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"

#include "CkCore/Macros/CkMacros.h"

#include <StructUtils/InstancedStruct.h>

#include "Serialization/BufferArchive.h"
#include "Serialization/MemoryReader.h"

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------

namespace ck_dynfrag_cov
{
    // Capture the whole registry then restore it in place (wipe + rebuild). Returns true on round-trip success.
    static auto
        CaptureRestore(ck::SnapshotRegistryType& InReg) -> bool
    {
        auto Buffer = FBufferArchive{};
        auto Header = FCk_Snapshot_Header{};
        if (ck::snapshot::Run_Capture_Registry(InReg, Buffer, Header) != ECk_SnapshotResult::Success)
        { return false; }

        auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
        return ck::snapshot::Run_Restore_Registry(InReg, Reader, Header).Get_Result() == ECk_SnapshotResult::Success;
    }

    // Re-find a restored entity by the SaveKey GUID stamped on it pre-capture (handles are stale post-wipe).
    static auto
        FindBySaveKey(ck::SnapshotRegistryType& InReg, const FGuid& InKey) -> TOptional<entt::entity>
    {
        for (const auto Entity : InReg.view<FFragment_SaveKey>())
        {
            if (InReg.get<FFragment_SaveKey>(Entity).Get_Key() == InKey)
            { return Entity; }
        }
        return {};
    }

    // Read a restored dynamic fragment of type T off an entity (from its named storage), or nullptr if absent.
    template <typename T>
    static auto
        GetDynFrag(ck::SnapshotRegistryType& InReg, entt::entity InEntity) -> const T*
    {
        const auto StorageId = UCk_Utils_DynamicFragment_UE::Get_StorageId(T::StaticStruct());
        auto& Storage = InReg.storage<ck::FFragment_DynamicFragment_Data>(StorageId);
        if (NOT Storage.contains(InEntity))
        { return nullptr; }

        const auto& Inst = Storage.get(InEntity).Get_StructData();
        if (Inst.GetScriptStruct() != T::StaticStruct())
        { return nullptr; }

        return &Inst.Get<T>();
    }

    template <typename T>
    static auto
        AddDynFrag(FCk_Handle& InOwner, const T& InValue) -> void
    {
        UCk_Utils_DynamicFragment_UE::Add_Fragment(
            InOwner, FInstancedStruct::Make(InValue), ECk_Replication::DoesNotReplicate);
    }
}

// --------------------------------------------------------------------------------------------------------------------
// 1. Two distinct dynamic-fragment types on ONE entity -- both named storages must round-trip + remap.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_MultipleTypesOnOneEntity_Test,
    "Ck.Snapshot.DynamicFragment.MultipleTypesOnOneEntity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_MultipleTypesOnOneEntity_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto OwnerGuid = FGuid(0x10, 0x11, 0x12, 0x13);
    const auto AGuid     = FGuid(0x14, 0x15, 0x16, 0x17);
    const auto BGuid     = FGuid(0x18, 0x19, 0x1A, 0x1B);

    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto TgtA  = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto TgtB  = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    Owner.Add<FFragment_SaveKey>(OwnerGuid);
    TgtA.Add<FFragment_SaveKey>(AGuid);
    TgtB.Add<FFragment_SaveKey>(BGuid);

    auto F1 = FCk_Test_DynFrag_WithHandle{};   F1.Marker = 7; F1.TargetHandle = TgtA;
    auto F2 = FCk_Test_DynFrag_OtherHandle{};  F2.OtherTarget = TgtB;
    AddDynFrag(Owner, F1);
    AddDynFrag(Owner, F2);

    if (NOT TestTrue(TEXT("round-trip succeeds"), CaptureRestore(*Reg))) { return false; }

    const auto RO = FindBySaveKey(*Reg, OwnerGuid);
    const auto RA = FindBySaveKey(*Reg, AGuid);
    const auto RB = FindBySaveKey(*Reg, BGuid);
    if (NOT TestTrue(TEXT("re-found all three"), RO.IsSet() && RA.IsSet() && RB.IsSet())) { return false; }

    const auto* G1 = GetDynFrag<FCk_Test_DynFrag_WithHandle>(*Reg, RO.GetValue());
    const auto* G2 = GetDynFrag<FCk_Test_DynFrag_OtherHandle>(*Reg, RO.GetValue());
    if (NOT TestTrue(TEXT("both dynamic-fragment types survived on the entity"), G1 != nullptr && G2 != nullptr))
    { return false; }

    TestEqual(TEXT("type-1 scalar intact"), G1->Marker, 7);
    TestTrue(TEXT("type-1 handle remapped to Target A"), G1->TargetHandle.Get_Entity().Get_ID() == RA.GetValue());
    TestTrue(TEXT("type-2 handle remapped to Target B"), G2->OtherTarget.Get_Entity().Get_ID() == RB.GetValue());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 2. Same dynamic-fragment type on MULTIPLE entities -- one named storage with several entries.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_MultipleEntitiesSameType_Test,
    "Ck.Snapshot.DynamicFragment.MultipleEntitiesSameType",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_MultipleEntitiesSameType_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto O1Guid = FGuid(0x20, 0x21, 0x22, 0x23);
    const auto O2Guid = FGuid(0x24, 0x25, 0x26, 0x27);
    const auto TGuid  = FGuid(0x28, 0x29, 0x2A, 0x2B);

    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto O1 = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto O2 = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Tgt = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    O1.Add<FFragment_SaveKey>(O1Guid);
    O2.Add<FFragment_SaveKey>(O2Guid);
    Tgt.Add<FFragment_SaveKey>(TGuid);

    auto FA = FCk_Test_DynFrag_WithHandle{}; FA.Marker = 1; FA.TargetHandle = Tgt;
    auto FB = FCk_Test_DynFrag_WithHandle{}; FB.Marker = 2; FB.TargetHandle = Tgt;
    AddDynFrag(O1, FA);
    AddDynFrag(O2, FB);

    if (NOT TestTrue(TEXT("round-trip succeeds"), CaptureRestore(*Reg))) { return false; }

    const auto R1 = FindBySaveKey(*Reg, O1Guid);
    const auto R2 = FindBySaveKey(*Reg, O2Guid);
    const auto RT = FindBySaveKey(*Reg, TGuid);
    if (NOT TestTrue(TEXT("re-found all three"), R1.IsSet() && R2.IsSet() && RT.IsSet())) { return false; }

    const auto* G1 = GetDynFrag<FCk_Test_DynFrag_WithHandle>(*Reg, R1.GetValue());
    const auto* G2 = GetDynFrag<FCk_Test_DynFrag_WithHandle>(*Reg, R2.GetValue());
    if (NOT TestTrue(TEXT("both owners kept the fragment"), G1 != nullptr && G2 != nullptr)) { return false; }

    TestEqual(TEXT("owner-1 scalar intact"), G1->Marker, 1);
    TestEqual(TEXT("owner-2 scalar intact"), G2->Marker, 2);
    TestTrue(TEXT("owner-1 handle remapped to Target"), G1->TargetHandle.Get_Entity().Get_ID() == RT.GetValue());
    TestTrue(TEXT("owner-2 handle remapped to Target"), G2->TargetHandle.Get_Entity().Get_ID() == RT.GetValue());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 3. Handle-free dynamic fragment -- isolates the data round-trip.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_PureDataNoHandles_Test,
    "Ck.Snapshot.DynamicFragment.PureDataNoHandles",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_PureDataNoHandles_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto Guid = FGuid(0x30, 0x31, 0x32, 0x33);

    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    Owner.Add<FFragment_SaveKey>(Guid);

    auto F = FCk_Test_DynFrag_PureData{}; F.Count = 99; F.Label = TEXT("persisted");
    AddDynFrag(Owner, F);

    if (NOT TestTrue(TEXT("round-trip succeeds"), CaptureRestore(*Reg))) { return false; }

    const auto RO = FindBySaveKey(*Reg, Guid);
    if (NOT TestTrue(TEXT("re-found owner"), RO.IsSet())) { return false; }

    const auto* G = GetDynFrag<FCk_Test_DynFrag_PureData>(*Reg, RO.GetValue());
    if (NOT TestTrue(TEXT("pure-data fragment survived"), G != nullptr)) { return false; }

    TestEqual(TEXT("int data intact"), G->Count, 99);
    TestEqual(TEXT("string data intact"), G->Label, FString(TEXT("persisted")));
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 4. Empty handle array + default (invalid) handle -- length-0 container + null handle must not desync or crash.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_EmptyArrayAndInvalidHandle_Test,
    "Ck.Snapshot.DynamicFragment.EmptyArrayAndInvalidHandle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_EmptyArrayAndInvalidHandle_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto Guid = FGuid(0x40, 0x41, 0x42, 0x43);

    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    Owner.Add<FFragment_SaveKey>(Guid);

    // TargetHandle left default (invalid); TargetArray left empty. Marker set so we can confirm data still lands.
    auto F = FCk_Test_DynFrag_WithHandle{}; F.Marker = 5;
    AddDynFrag(Owner, F);

    if (NOT TestTrue(TEXT("round-trip succeeds"), CaptureRestore(*Reg))) { return false; }

    const auto RO = FindBySaveKey(*Reg, Guid);
    if (NOT TestTrue(TEXT("re-found owner"), RO.IsSet())) { return false; }

    const auto* G = GetDynFrag<FCk_Test_DynFrag_WithHandle>(*Reg, RO.GetValue());
    if (NOT TestTrue(TEXT("fragment survived"), G != nullptr)) { return false; }

    TestEqual(TEXT("scalar intact despite empty/invalid handle fields"), G->Marker, 5);
    TestEqual(TEXT("empty handle array round-tripped as empty"), G->TargetArray.Num(), 0);
    TestTrue(TEXT("default handle stays null after restore (no spurious remap)"),
        G->TargetHandle.Get_Entity().Get_ID() == entt::null);
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 5. Handle nested one struct level deep -- the recursive walk must reach + remap it.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_NestedHandleRemaps_Test,
    "Ck.Snapshot.DynamicFragment.NestedHandleRemaps",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_NestedHandleRemaps_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto OGuid = FGuid(0x50, 0x51, 0x52, 0x53);
    const auto TGuid = FGuid(0x54, 0x55, 0x56, 0x57);

    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Tgt   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    Owner.Add<FFragment_SaveKey>(OGuid);
    Tgt.Add<FFragment_SaveKey>(TGuid);

    auto F = FCk_Test_DynFrag_Nested{}; F.Tag = 11; F.Inner.InnerHandle = Tgt;
    AddDynFrag(Owner, F);

    if (NOT TestTrue(TEXT("round-trip succeeds"), CaptureRestore(*Reg))) { return false; }

    const auto RO = FindBySaveKey(*Reg, OGuid);
    const auto RT = FindBySaveKey(*Reg, TGuid);
    if (NOT TestTrue(TEXT("re-found owner + target"), RO.IsSet() && RT.IsSet())) { return false; }

    const auto* G = GetDynFrag<FCk_Test_DynFrag_Nested>(*Reg, RO.GetValue());
    if (NOT TestTrue(TEXT("nested fragment survived"), G != nullptr)) { return false; }

    TestEqual(TEXT("outer scalar intact"), G->Tag, 11);
    TestTrue(TEXT("nested handle remapped to the restored target"),
        G->Inner.InnerHandle.Get_Entity().Get_ID() == RT.GetValue());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 6. Self-referential handle -- a fragment whose handle points at its own entity must remap to the restored self.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_SelfReferentialHandle_Test,
    "Ck.Snapshot.DynamicFragment.SelfReferentialHandle",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_SelfReferentialHandle_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto Guid = FGuid(0x60, 0x61, 0x62, 0x63);

    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    Owner.Add<FFragment_SaveKey>(Guid);

    auto F = FCk_Test_DynFrag_WithHandle{}; F.Marker = 3; F.TargetHandle = Owner; // points at self
    AddDynFrag(Owner, F);

    if (NOT TestTrue(TEXT("round-trip succeeds"), CaptureRestore(*Reg))) { return false; }

    const auto RO = FindBySaveKey(*Reg, Guid);
    if (NOT TestTrue(TEXT("re-found owner"), RO.IsSet())) { return false; }

    const auto* G = GetDynFrag<FCk_Test_DynFrag_WithHandle>(*Reg, RO.GetValue());
    if (NOT TestTrue(TEXT("fragment survived"), G != nullptr)) { return false; }

    TestTrue(TEXT("self-referential handle remapped to the restored self"),
        G->TargetHandle.Get_Entity().Get_ID() == RO.GetValue());
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 7. Two round-trips back to back -- save/load must be idempotent over repeated cycles.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_DoubleRoundTrip_Test,
    "Ck.Snapshot.DynamicFragment.DoubleRoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_DoubleRoundTrip_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto OGuid = FGuid(0x70, 0x71, 0x72, 0x73);
    const auto TGuid = FGuid(0x74, 0x75, 0x76, 0x77);

    auto World = ck::FEcsWorld{};
    auto* Reg = ck::registry_table::TryResolve(World.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("registry"), Reg)) { return false; }

    auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    auto Tgt   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(World.Get_Registry());
    Owner.Add<FFragment_SaveKey>(OGuid);
    Tgt.Add<FFragment_SaveKey>(TGuid);

    auto F = FCk_Test_DynFrag_WithHandle{}; F.Marker = 42; F.TargetHandle = Tgt; F.TargetArray = { Tgt };
    AddDynFrag(Owner, F);

    if (NOT TestTrue(TEXT("first round-trip succeeds"), CaptureRestore(*Reg))) { return false; }
    if (NOT TestTrue(TEXT("second round-trip succeeds"), CaptureRestore(*Reg))) { return false; }

    const auto RO = FindBySaveKey(*Reg, OGuid);
    const auto RT = FindBySaveKey(*Reg, TGuid);
    if (NOT TestTrue(TEXT("re-found owner + target after two cycles"), RO.IsSet() && RT.IsSet())) { return false; }

    const auto* G = GetDynFrag<FCk_Test_DynFrag_WithHandle>(*Reg, RO.GetValue());
    if (NOT TestTrue(TEXT("fragment survived two cycles"), G != nullptr)) { return false; }

    TestEqual(TEXT("scalar intact after two cycles"), G->Marker, 42);
    TestTrue(TEXT("single handle still resolves to target"), G->TargetHandle.Get_Entity().Get_ID() == RT.GetValue());
    if (TestEqual(TEXT("array intact after two cycles"), G->TargetArray.Num(), 1))
    {
        TestTrue(TEXT("array handle still resolves to target"),
            G->TargetArray[0].Get_Entity().Get_ID() == RT.GetValue());
    }
    return true;
}

// --------------------------------------------------------------------------------------------------------------------
// 8. Cross-registry restore (seamless travel) -- a dynamic-fragment handle must RE-HOME onto the new registry and
//    resolve there. This is the FSnapshotContext::Snapshot_Handle re-home path, now reached via the dynamic-fragment
//    walk: capture in world A, restore into a separate world B with B's load-target handle.

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCk_Snapshot_DynamicFragment_CrossRegistryRehome_Test,
    "Ck.Snapshot.DynamicFragment.CrossRegistryRehome",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_CrossRegistryRehome_Test::
    RunTest(const FString&)
{
    using namespace ck_dynfrag_cov;
    const auto OGuid = FGuid(0x80, 0x81, 0x82, 0x83);
    const auto TGuid = FGuid(0x84, 0x85, 0x86, 0x87);

    // ---- Capture in world A (then let A die) -------------------------------------------------------------------
    auto Buffer = FBufferArchive{};
    auto Header = FCk_Snapshot_Header{};
    {
        auto WorldA = ck::FEcsWorld{};
        auto* RawA = ck::registry_table::TryResolve(WorldA.Get_Registry().Get_RegistryHandle());
        if (NOT TestNotNull(TEXT("world A registry"), RawA)) { return false; }

        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldA.Get_Registry());
        auto Tgt   = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(WorldA.Get_Registry());
        Owner.Add<FFragment_SaveKey>(OGuid);
        Tgt.Add<FFragment_SaveKey>(TGuid);

        auto F = FCk_Test_DynFrag_WithHandle{}; F.Marker = 88; F.TargetHandle = Tgt;
        AddDynFrag(Owner, F);

        if (NOT TestEqual(TEXT("capture in A succeeds"),
                static_cast<uint8>(ck::snapshot::Run_Capture_Registry(*RawA, Buffer, Header)),
                static_cast<uint8>(ECk_SnapshotResult::Success)))
        { return false; }
    }

    // ---- Restore into a SEPARATE world B WITH B's load-target registry handle -----------------------------------
    auto WorldB = ck::FEcsWorld{};
    auto* RawB = ck::registry_table::TryResolve(WorldB.Get_Registry().Get_RegistryHandle());
    if (NOT TestNotNull(TEXT("world B registry"), RawB)) { return false; }

    auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
    const auto Report = ck::snapshot::Run_Restore_Registry(
        *RawB, Reader, Header, WorldB.Get_Registry().Get_RegistryHandle());
    if (NOT TestEqual(TEXT("restore into B succeeds"),
            static_cast<uint8>(Report.Get_Result()), static_cast<uint8>(ECk_SnapshotResult::Success)))
    { return false; }

    const auto RO = FindBySaveKey(*RawB, OGuid);
    const auto RT = FindBySaveKey(*RawB, TGuid);
    if (NOT TestTrue(TEXT("re-found owner + target in world B"), RO.IsSet() && RT.IsSet())) { return false; }

    const auto* G = GetDynFrag<FCk_Test_DynFrag_WithHandle>(*RawB, RO.GetValue());
    if (NOT TestTrue(TEXT("dynamic fragment survived into world B"), G != nullptr)) { return false; }

    TestEqual(TEXT("scalar intact across worlds"), G->Marker, 88);
    TestTrue(TEXT("handle re-homed + resolves in world B"),
        ck::IsValid(G->TargetHandle, ck::IsValid_Policy_IncludePendingKill{}));
    TestTrue(TEXT("handle remapped to the restored target in B"),
        G->TargetHandle.Get_Entity().Get_ID() == RT.GetValue());
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
