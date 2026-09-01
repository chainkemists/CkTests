#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_RestoreMarker.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkInventory/Inventory/CkInventory_Fragment.h"
#include "CkInventory/Inventory/CkInventory_Utils.h"
#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Fragment.h"
#include "CkInventory/Item/CkItem_Fragment.h"
#include "CkInventory/Item/CkItem_Utils.h"
#include "CkPhysics/Velocity/CkVelocity_Fragment.h"
#include "CkStateMachine/Net/CkStateMachine_RepData.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment.h"

namespace
{
    auto SerializePayload(const FInstancedStruct& InPayload) -> TArray<uint8>
    {
        auto Bytes = TArray<uint8>{};
        auto Writer = FMemoryWriter{Bytes, true};
        auto Proxy = FObjectAndNameAsStringProxyArchive{Writer, true};
        Proxy.SetIsPersistent(true);
        auto Copy = FInstancedStruct{InPayload};
        Copy.Serialize(Proxy);
        return Bytes;
    }

    auto AddStateMachineForProduce(
        ck::FEcsWorld& InWorld,
        const ECk_Sm_ReplicationModel InReplicationModel,
        const bool bSaveTransient,
        const bool bShouldPersistCurrentState = true) -> FCk_Handle
    {
        auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InWorld.Get_Registry());
        auto Params = FCk_Fragment_StateMachine_ParamsData{};
        Params.Set_ReplicationModel(InReplicationModel);
        Params.Set_ShouldPersistCurrentState(bShouldPersistCurrentState);
        Entity.Add<ck::FFragment_Sm_Params>(Params);
        Entity.Add<ck::FFragment_Sm_Current>();
        if (bSaveTransient)
        { Entity.Add<ck::FTag_Snapshot_SaveTransient>(); }
        return Entity;
    }

    struct FDataOnlyInventoryProduceFixture
    {
        FCk_Handle Inventory;
        FCk_Handle_Item Item;
    };

    auto AddDataOnlyInventoryForProduce(
        ck::FEcsWorld& InWorld,
        const ECk_EnableDisable InPersistContents,
        const bool bAddItem) -> FDataOnlyInventoryProduceFixture
    {
        auto Inventory = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InWorld.Get_Registry());
        auto Params = FCk_Fragment_Inventory_DataOnly_ParamsData{};
        Params.Set_PersistContents(InPersistContents);
        Inventory.Add<ck::FFragment_Inventory_Params>(FCk_Fragment_Inventory_ParamsData{Params});
        Inventory.Add<ck::FTag_Inventory_DataOnly>();
        Inventory.Add<ck::FFragment_RecordOfInventoryItems>();

        auto Fixture = FDataOnlyInventoryProduceFixture{};
        Fixture.Inventory = Inventory;
        if (NOT bAddItem)
        { return Fixture; }

        auto ItemEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InWorld.Get_Registry());
        ItemEntity.Add<ck::FFragment_InventoryItem>(nullptr);
        Fixture.Item = UCk_Utils_Item_UE::Cast(ItemEntity);
        UCk_Utils_Inventory_UE::RecordOfInventoryItems_Utils::Request_Connect(
            Inventory, Fixture.Item, ECk_Record_LabelRequirementPolicy::Optional);
        return Fixture;
    }

    auto AssertStateMachineProducePolicy(
        FAutomationTestBase& InTest,
        const UScriptStruct* InPayloadType,
        const ECk_Sm_ReplicationModel InReplicationModel,
        const TCHAR* InModelName) -> bool
    {
        const auto* Handler = FCk_PersistenceHandlerRegistry::Find(InPayloadType);
        if (NOT InTest.TestNotNull(FString::Printf(TEXT("%s save handler registered"), InModelName), Handler)
            || NOT InTest.TestTrue(FString::Printf(TEXT("%s handler exposes Produce"), InModelName),
                Handler != nullptr && static_cast<bool>(Handler->Produce))
            || NOT InTest.TestTrue(FString::Printf(TEXT("%s handler exposes HydrationApply"), InModelName),
                Handler != nullptr && static_cast<bool>(Handler->HydrationApply)))
        { return false; }

        auto RootWorld = ck::FEcsWorld{};
        auto Root = AddStateMachineForProduce(RootWorld, InReplicationModel, /*bSaveTransient=*/false);
        const auto RootPayload = Handler->Produce(Root);
        InTest.TestTrue(FString::Printf(TEXT("ordinary root %s state machine produces a save payload"), InModelName),
            RootPayload.IsSet());

        auto DerivedWorld = ck::FEcsWorld{};
        auto Derived = AddStateMachineForProduce(DerivedWorld, InReplicationModel, /*bSaveTransient=*/true);
        const auto DerivedPayload = Handler->Produce(Derived);
        InTest.TestFalse(FString::Printf(TEXT("save-transient %s state machine produces no save payload"), InModelName),
            DerivedPayload.IsSet());

        auto OptOutWorld = ck::FEcsWorld{};
        auto OptOut = AddStateMachineForProduce(OptOutWorld, InReplicationModel,
            /*bSaveTransient=*/false, /*bShouldPersistCurrentState=*/false);
        const auto OptOutPayload = Handler->Produce(OptOut);
        InTest.TestFalse(FString::Printf(TEXT("opted-out %s state machine produces no save payload"), InModelName),
            OptOutPayload.IsSet());

        const auto LegacyPayload = InReplicationModel == ECk_Sm_ReplicationModel::WithHistory
            ? FInstancedStruct::Make(FCk_RepData_StateMachine_WithHistory{})
            : FInstancedStruct::Make(FCk_RepData_StateMachine_NoHistory{});
        const auto ApplyResult = Handler->HydrationApply(OptOut, LegacyPayload, {});
        InTest.TestEqual(FString::Printf(TEXT("opted-out %s state machine ignores legacy save payload"), InModelName),
            ApplyResult, ECk_Persistence_ApplyResult::Applied);
        InTest.TestFalse(FString::Printf(TEXT("opted-out %s state machine creates no hydration resume"), InModelName),
            OptOut.Has<ck::FFragment_Sm_HydrationResume>());
        return true;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_ProduceSensitivity,
    "Ck.Snapshot.V3.ProduceSensitivity.Velocity",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_ProduceSensitivity::RunTest(const FString& Parameters)
{
    auto EcsWorld = ck::FEcsWorld{};
    auto& Registry = EcsWorld.Get_Registry();
    auto Entity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(Registry);

    const auto Initial = FVector{10.0, 20.0, 30.0};
    const auto Mutated = FVector{-40.0, 50.0, 60.0};
    Entity.Add<ck::FFragment_Velocity_Current>(Initial);

    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_RepData_Velocity::StaticStruct());
    if (NOT TestNotNull(TEXT("Velocity save handler registered"), Handler) ||
        NOT TestTrue(TEXT("Velocity handler exposes Produce"), Handler != nullptr && static_cast<bool>(Handler->Produce)))
    { return false; }

    const auto First = Handler->Produce(Entity);
    const auto Unchanged = Handler->Produce(Entity);
    if (NOT TestTrue(TEXT("Produce emitted both unchanged samples"), First.IsSet() && Unchanged.IsSet()))
    { return false; }

    const auto FirstBytes = SerializePayload(First.GetValue());
    const auto UnchangedBytes = SerializePayload(Unchanged.GetValue());
    TestTrue(TEXT("unchanged live state produces identical payload bytes"), FirstBytes == UnchangedBytes);

    Entity.Replace<ck::FFragment_Velocity_Current>(Mutated);
    const auto Changed = Handler->Produce(Entity);
    if (NOT TestTrue(TEXT("Produce emitted the mutated sample"), Changed.IsSet()))
    { return false; }

    const auto ChangedBytes = SerializePayload(Changed.GetValue());
    TestTrue(TEXT("mutating live state changes produced payload bytes"), FirstBytes != ChangedBytes);
    TestTrue(TEXT("mutated payload contains the new velocity"),
        Changed.GetValue().Get<FCk_RepData_Velocity>().Value.Equals(Mutated));
    return true;
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_SaveTransientStateMachine_WithHistory_Produce,
    "Ck.Snapshot.V3.SaveTransientStateMachine.WithHistory.Produce",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_SaveTransientStateMachine_WithHistory_Produce::RunTest(const FString& Parameters)
{
    return AssertStateMachineProducePolicy(*this,
        FCk_RepData_StateMachine_WithHistory::StaticStruct(),
        ECk_Sm_ReplicationModel::WithHistory,
        TEXT("WithHistory"));
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_SaveTransientStateMachine_NoHistory_Produce,
    "Ck.Snapshot.V3.SaveTransientStateMachine.NoHistory.Produce",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_SaveTransientStateMachine_NoHistory_Produce::RunTest(const FString& Parameters)
{
    return AssertStateMachineProducePolicy(*this,
        FCk_RepData_StateMachine_NoHistory::StaticStruct(),
        ECk_Sm_ReplicationModel::WithoutHistory,
        TEXT("NoHistory"));
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_DataOnlyInventory_PersistContents,
    "Ck.Snapshot.V3.DataOnlyInventory.PersistContents",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_DataOnlyInventory_PersistContents::RunTest(const FString& Parameters)
{
    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(
        FCk_RepData_Inventory_DataOnly_Items::StaticStruct());
    if (NOT TestNotNull(TEXT("DataOnly inventory save handler registered"), Handler)
        || NOT TestTrue(TEXT("DataOnly inventory handler exposes Produce"),
            Handler != nullptr && static_cast<bool>(Handler->Produce))
        || NOT TestTrue(TEXT("DataOnly inventory handler exposes HydrationApply"),
            Handler != nullptr && static_cast<bool>(Handler->HydrationApply)))
    { return false; }

    auto DefaultWorld = ck::FEcsWorld{};
    auto DefaultInventory = AddDataOnlyInventoryForProduce(
        DefaultWorld, ECk_EnableDisable::Enable, /*bAddItem=*/true);
    const auto DefaultPayload = Handler->Produce(DefaultInventory.Inventory);
    if (NOT TestTrue(TEXT("default-on DataOnly inventory produces a save payload"), DefaultPayload.IsSet()))
    { return false; }

    const auto& DefaultItems = DefaultPayload->Get<FCk_RepData_Inventory_DataOnly_Items>().Items;
    if (NOT TestEqual(TEXT("default-on DataOnly inventory payload contains its item"), DefaultItems.Num(), 1))
    { return false; }
    TestEqual(TEXT("default-on DataOnly inventory payload preserves its item handle"),
        DefaultItems[0].Get_ItemHandle(), DefaultInventory.Item);

    auto OptOutWorld = ck::FEcsWorld{};
    auto OptOutInventory = AddDataOnlyInventoryForProduce(
        OptOutWorld, ECk_EnableDisable::Disable, /*bAddItem=*/false);
    const auto OptOutPayload = Handler->Produce(OptOutInventory.Inventory);
    TestFalse(TEXT("opted-out DataOnly inventory produces no save payload"), OptOutPayload.IsSet());

    auto LegacyWorld = ck::FEcsWorld{};
    const auto LegacyItem = AddDataOnlyInventoryForProduce(
        LegacyWorld, ECk_EnableDisable::Enable, /*bAddItem=*/true).Item;
    auto LegacyData = FCk_RepData_Inventory_DataOnly_Items{};
    LegacyData.Items.Emplace(LegacyItem);
    const auto ApplyResult = Handler->HydrationApply(
        OptOutInventory.Inventory, FInstancedStruct::Make(LegacyData), {});
    TestEqual(TEXT("opted-out DataOnly inventory ignores legacy save payload"),
        ApplyResult, ECk_Persistence_ApplyResult::Applied);
    TestTrue(TEXT("opted-out DataOnly inventory remains empty after legacy hydration"),
        UCk_Utils_Inventory_UE::RecordOfInventoryItems_Utils::Get_ValidEntries(
            OptOutInventory.Inventory).IsEmpty());
    TestFalse(TEXT("opted-out DataOnly legacy hydration does not set an item parent"),
        LegacyItem.Has<ck::FFragment_Item_ParentInventory>());
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
