// Regression test for the typed-handle remap gap: the dynamic-fragment handle walk matched FCk_Handle by EXACT
// struct equality, so C++-native TYPED handles (FCk_Handle_Inventory, FCk_Handle_IntegerAttribute, ...) declared in
// AngelScript fragments were silently never serialized — they restored as default TOMBSTONES while the entities they
// pointed at were restored alive (the player's held-item chain dangled exactly this way). TSet/TMap fields were not
// walked at all (FBb_Fragment_GridPlacement stores TMap<FCk_Handle, ...> + TMap<FIntPoint, FCk_Handle>).
//
// Asserts, across a capture -> wipe -> restore:
//   1. a TYPED single handle remaps (IsChildOf matching);
//   2. a TArray of TYPED handles remaps element-wise;
//   3. a TSet<FCk_Handle> remaps element-wise AND the set is rehashed (Contains works post-restore);
//   4. a TMap with HANDLE KEYS remaps keys AND rehashes (Find works post-restore);
//   5. a TMap with TYPED handle VALUES remaps values.
//
// Drives the registry-level entry points directly, mirroring Test_Snapshot_DynamicFragment_HandleRemap_RoundTrip.cpp
// (which only covers BARE FCk_Handle fields and therefore never caught this).

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
    FCk_Snapshot_DynamicFragment_TypedHandleRemap_RoundTrip_Test,
    "Ck.Snapshot.DynamicFragment.TypedHandleRemap.RoundTrip",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool
    FCk_Snapshot_DynamicFragment_TypedHandleRemap_RoundTrip_Test::
    RunTest(
        const FString& /*InParameters*/)
{
    const auto OwnerGuid   = FGuid(0xA1A1A1A1, 0xB2B2B2B2, 0xC3C3C3C3, 0xD4D4D4D4);
    const auto TargetAGuid = FGuid(0xE5E5E5E5, 0xF6F6F6F6, 0x07070707, 0x18181818);
    const auto TargetBGuid = FGuid(0x29292929, 0x3A3A3A3A, 0x4B4B4B4B, 0x5C5C5C5C);
    constexpr auto KeyAMarker = int32{11};
    constexpr auto KeyBMarker = int32{22};

    // ---- Arrange: private ECS world; Owner holds the typed/container fragment pointing at Targets A + B ---------
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

    OwnerEntity.Add<FFragment_SaveKey>(OwnerGuid);
    TargetEntityA.Add<FFragment_SaveKey>(TargetAGuid);
    TargetEntityB.Add<FFragment_SaveKey>(TargetBGuid);

    auto Fixture = FCk_Test_DynFrag_TypedAndContainers{};
    Fixture.TypedSingle = ck::StaticCast<FCk_Test_TypedHandle>(TargetEntityA);
    Fixture.TypedArray  = { ck::StaticCast<FCk_Test_TypedHandle>(TargetEntityA),
                            ck::StaticCast<FCk_Test_TypedHandle>(TargetEntityB) };
    Fixture.HandleSet.Add(TargetEntityA);
    Fixture.HandleSet.Add(TargetEntityB);
    Fixture.HandleKeyMap.Add(TargetEntityA, KeyAMarker);
    Fixture.HandleKeyMap.Add(TargetEntityB, KeyBMarker);
    Fixture.TypedValueMap.Add(KeyAMarker, ck::StaticCast<FCk_Test_TypedHandle>(TargetEntityA));
    Fixture.TypedValueMap.Add(KeyBMarker, ck::StaticCast<FCk_Test_TypedHandle>(TargetEntityB));

    UCk_Utils_DynamicFragment_UE::Add_Fragment(
        OwnerEntity, FInstancedStruct::Make(Fixture), ECk_Replication::DoesNotReplicate);

    // ---- Act: capture -> wipe -> restore ------------------------------------------------------------------------
    {
        auto Buffer = FBufferArchive{};
        auto Header = FCk_Snapshot_Header{};
        if (NOT TestEqual(TEXT("capture succeeds"),
                static_cast<uint8>(ck::snapshot::Run_Capture_Registry(*RawRegistry, Buffer, Header)),
                static_cast<uint8>(ECk_SnapshotResult::Success)))
        { return false; }

        auto Reader = FMemoryReader{Buffer, /*bIsPersistent=*/true};
        if (NOT TestEqual(TEXT("restore succeeds"),
                static_cast<uint8>(ck::snapshot::Run_Restore_Registry(*RawRegistry, Reader, Header).Get_Result()),
                static_cast<uint8>(ECk_SnapshotResult::Success)))
        { return false; }
    }

    // ---- Re-find restored entities by SaveKey (pre-restore handles are stale) -----------------------------------
    auto RO = TOptional<entt::entity>{};
    auto RA = TOptional<entt::entity>{};
    auto RB = TOptional<entt::entity>{};
    for (const auto Entity : RawRegistry->view<FFragment_SaveKey>())
    {
        const auto& Key = RawRegistry->get<FFragment_SaveKey>(Entity).Get_Key();
        if (Key == OwnerGuid)   { RO = Entity; }
        if (Key == TargetAGuid) { RA = Entity; }
        if (Key == TargetBGuid) { RB = Entity; }
    }
    if (NOT TestTrue(TEXT("re-found Owner + both Targets by SaveKey"), RO.IsSet() && RA.IsSet() && RB.IsSet()))
    { return false; }

    const auto StorageId = UCk_Utils_DynamicFragment_UE::Get_StorageId(FCk_Test_DynFrag_TypedAndContainers::StaticStruct());
    auto& DynStorage = RawRegistry->storage<ck::FFragment_DynamicFragment_Data>(StorageId);
    if (NOT TestTrue(TEXT("restored Owner still carries the dynamic fragment"), DynStorage.contains(RO.GetValue())))
    { return false; }

    const auto& RestoredInst = DynStorage.get(RO.GetValue()).Get_StructData();
    if (NOT TestTrue(TEXT("restored instance holds the fixture struct type"),
            RestoredInst.GetScriptStruct() == FCk_Test_DynFrag_TypedAndContainers::StaticStruct()))
    { return false; }

    const auto& Restored = RestoredInst.Get<FCk_Test_DynFrag_TypedAndContainers>();

    const auto IdOf = [](const FCk_Handle& InHandle) { return InHandle.Get_Entity().Get_ID(); };

    // ---- 1. TYPED single handle remapped (would be a default TOMBSTONE under the exact-equality walk) ------------
    TestTrue(TEXT("TYPED single handle remapped to restored Target A"), IdOf(Restored.TypedSingle) == RA.GetValue());

    // ---- 2. TArray of TYPED handles remapped element-wise --------------------------------------------------------
    if (TestEqual(TEXT("typed array has both elements"), Restored.TypedArray.Num(), 2))
    {
        TestTrue(TEXT("typed array [0] remapped to restored Target A"), IdOf(Restored.TypedArray[0]) == RA.GetValue());
        TestTrue(TEXT("typed array [1] remapped to restored Target B"), IdOf(Restored.TypedArray[1]) == RB.GetValue());
    }

    // ---- 3. TSet elements remapped + set REHASHED (a stale hash table would make Contains miss) ------------------
    if (TestEqual(TEXT("handle set has both elements"), Restored.HandleSet.Num(), 2))
    {
        auto SetIds = TSet<uint32>{};
        for (const auto& Element : Restored.HandleSet)
        { SetIds.Add(static_cast<uint32>(IdOf(Element))); }
        TestTrue(TEXT("set contains restored Target A + B ids"),
            SetIds.Contains(static_cast<uint32>(RA.GetValue())) && SetIds.Contains(static_cast<uint32>(RB.GetValue())));

        // Rehash proof: look an element up BY HASH using a copy of one of the set's own elements. If the buckets
        // were built from the stale pre-remap ids, this hash lookup misses even though iteration sees the element.
        for (const auto& Element : Restored.HandleSet)
        {
            TestTrue(TEXT("set hash lookup works post-remap (set was rehashed)"), Restored.HandleSet.Contains(Element));
            break;
        }
    }

    // ---- 4. TMap handle KEYS remapped + map REHASHED ---------------------------------------------------------------
    if (TestEqual(TEXT("handle-key map has both pairs"), Restored.HandleKeyMap.Num(), 2))
    {
        for (const auto& Kvp : Restored.HandleKeyMap)
        {
            const auto ExpectedId = (Kvp.Value == KeyAMarker) ? RA.GetValue() : RB.GetValue();
            TestTrue(TEXT("map key remapped to the restored target its marker names"), IdOf(Kvp.Key) == ExpectedId);

            // Rehash proof, same as the set: hash-lookup with a copy of the map's own key.
            const auto KeyCopy = Kvp.Key;
            TestTrue(TEXT("map hash lookup works post-remap (map was rehashed)"),
                Restored.HandleKeyMap.Find(KeyCopy) != nullptr);
        }
    }

    // ---- 5. TMap TYPED handle VALUES remapped -----------------------------------------------------------------------
    if (TestEqual(TEXT("typed-value map has both pairs"), Restored.TypedValueMap.Num(), 2))
    {
        const auto* ValueA = Restored.TypedValueMap.Find(KeyAMarker);
        const auto* ValueB = Restored.TypedValueMap.Find(KeyBMarker);
        TestTrue(TEXT("typed map value [A] remapped"), ValueA != nullptr && IdOf(*ValueA) == RA.GetValue());
        TestTrue(TEXT("typed map value [B] remapped"), ValueB != nullptr && IdOf(*ValueB) == RB.GetValue());
    }

    AddInfo(FString::Printf(TEXT("typed single -> [%u] (A [%u]); array [%d]; set [%d]; key-map [%d]; value-map [%d]"),
        static_cast<uint32>(IdOf(Restored.TypedSingle)), static_cast<uint32>(RA.GetValue()),
        Restored.TypedArray.Num(), Restored.HandleSet.Num(), Restored.HandleKeyMap.Num(), Restored.TypedValueMap.Num()));

    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS

// --------------------------------------------------------------------------------------------------------------------
