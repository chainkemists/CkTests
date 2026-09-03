#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Serialization/MemoryWriter.h"
#include "Serialization/ObjectAndNameAsStringProxyArchive.h"
#include "StructUtils/InstancedStruct.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Fragment.h"
#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/Persistence/CkPersistenceHandlerRegistry.h"
#include "CkEcs/Snapshot/CkSnapshot_RestoreMarker.h"
#include "CkEcs/World/CkEcsWorld.h"
#include "CkAttribute/ByteAttribute/CkByteAttribute_Fragment.h"
#include "CkAttribute/ByteAttribute/CkByteAttribute_Utils.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Fragment.h"
#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
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


// --------------------------------------------------------------------------------------------------------------------
// FCk_Fragment_*Attribute_ParamsData::_PersistValue - the attribute family's instance-level save opt-out. The
// registration declares ONE posture (Durable) for the whole payload type, which is right for a stat and wrong for an
// instance that holds a single frame of volatile state (a player input intent). Disable stamps the snapshot
// reconstruct-only marker, so capture omits the entity and the SHARED HydrationApply refuses a payload from a save
// written before the declaration. Produce/HydrationApply are shared templates across Byte/Float/Integer/Vector/
// Rotator, so Byte proves the mechanism and Float proves it is the shared one rather than a per-family copy.
//
// The third assertion is the one that matters most: Produce MUST still emit for an opted-out attribute, because
// Produce is also the WIRE projection (TProcessor_Attribute_Replicate publishes through
// UCk_Utils_Net_UE::TryProduce, which resolves this same handler). Gating it there stops replicating every
// opted-out attribute, silently.

UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_Test_V3_PersistValueAttribute, "ByteAttribute.Test.V3.PersistValue");

namespace
{
    auto AddByteAttributeForProduce(
        ck::FEcsWorld& InWorld,
        const ECk_EnableDisable InPersistValue,
        const uint8 InBaseValue) -> FCk_Handle_ByteAttribute
    {
        auto Owner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InWorld.Get_Registry());
        auto Params = FCk_Fragment_ByteAttribute_ParamsData{TAG_Test_V3_PersistValueAttribute, InBaseValue};
        Params.Set_PersistValue(InPersistValue);
        return UCk_Utils_ByteAttribute_UE::Add(Owner, Params, ECk_Replication::DoesNotReplicate);
    }

    // The payload an older save carries for this attribute: the shape Produce emitted before the opt-out existed.
    auto Make_LegacyByteAttributePayload(const uint8 InValue) -> FInstancedStruct
    {
        auto Data = FCk_RepData_ByteAttributes{};
        Data.Attributes.Emplace(FCk_Fragment_ByteAttribute_BaseFinal{
            TAG_Test_V3_PersistValueAttribute, InValue, InValue, ECk_MinMaxCurrent::Current});
        return FInstancedStruct::Make(MoveTemp(Data));
    }

    // A hydration that actually applied leaves modifier ENTITIES behind: ApplyReplicated*Entry adds an Override
    // and a revocable Final modifier, and each is a lifetime child of the attribute. Counting children rather than
    // naming a modifier tag keeps this test off CkAttribute internals that are not DLL-exported.
    auto Get_ModifierChildCount(const FCk_Handle& InAttribute) -> int32
    {
        return InAttribute.Has<ck::FFragment_LifetimeDependents>()
            ? InAttribute.Get<ck::FFragment_LifetimeDependents>().Get_Entities().Num()
            : 0;
    }
}

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkSnapshot_V3_Attribute_PersistValue,
    "Ck.Snapshot.V3.Attribute.PersistValue",
    EAutomationTestFlags::EditorContext | EAutomationTestFlags::EngineFilter)

bool FCkSnapshot_V3_Attribute_PersistValue::RunTest(const FString& Parameters)
{
    const auto* Handler = FCk_PersistenceHandlerRegistry::Find(FCk_RepData_ByteAttributes::StaticStruct());
    if (NOT TestNotNull(TEXT("byte attribute save handler registered"), Handler)
        || NOT TestTrue(TEXT("byte attribute handler exposes Produce"),
            Handler != nullptr && static_cast<bool>(Handler->Produce))
        || NOT TestTrue(TEXT("byte attribute handler exposes HydrationApply"),
            Handler != nullptr && static_cast<bool>(Handler->HydrationApply)))
    { return false; }

    // ---- default Enable keeps the family's Durable behavior -----------------------------------------------------
    auto DefaultWorld = ck::FEcsWorld{};
    auto DefaultAttribute = AddByteAttributeForProduce(DefaultWorld, ECk_EnableDisable::Enable, 7);
    auto DefaultEntity = FCk_Handle{DefaultAttribute};

    TestFalse(TEXT("default-on byte attribute is not marked reconstruct-only"),
        DefaultEntity.Has<ck::FTag_Snapshot_ReconstructOnly>());

    const auto DefaultPayload = Handler->Produce(DefaultEntity);
    if (NOT TestTrue(TEXT("default-on byte attribute produces a payload"), DefaultPayload.IsSet()))
    { return false; }

    const auto& DefaultEntries = DefaultPayload->Get<FCk_RepData_ByteAttributes>().Attributes;
    if (NOT TestEqual(TEXT("default-on byte attribute payload carries its Current component"),
            DefaultEntries.Num(), 1))
    { return false; }
    TestEqual(TEXT("default-on byte attribute payload preserves its base value"),
        static_cast<int32>(DefaultEntries[0].Get_Base()), 7);

    // POSITIVE CONTROL: the legacy payload MUST reach the default-on attribute, or the opted-out assertion below
    // would pass against a handler that simply never applies anything.
    TestEqual(TEXT("default-on byte attribute has no modifiers before hydration"),
        Get_ModifierChildCount(DefaultEntity), 0);
    const auto DefaultApply = Handler->HydrationApply(DefaultEntity, Make_LegacyByteAttributePayload(1), {});
    TestEqual(TEXT("default-on byte attribute applies a save payload"),
        DefaultApply, ECk_Persistence_ApplyResult::Applied);
    TestTrue(TEXT("default-on byte attribute gains modifiers from hydration"),
        Get_ModifierChildCount(DefaultEntity) > 0);

    // ---- Disable declares the instance reconstruct-only and ignores a legacy payload ------------------------------
    auto OptOutWorld = ck::FEcsWorld{};
    auto OptOutAttribute = AddByteAttributeForProduce(OptOutWorld, ECk_EnableDisable::Disable, 0);
    auto OptOutEntity = FCk_Handle{OptOutAttribute};

    // Capture's own honouring of this marker (no entity row, no payload, no subtractive reconcile) is pinned by
    // Ck.Snapshot.V3.Capture; what this asserts is that the params flag is what stamps it.
    TestTrue(TEXT("opted-out byte attribute is marked reconstruct-only"),
        OptOutEntity.Has<ck::FTag_Snapshot_ReconstructOnly>());

    const auto OptOutApply = Handler->HydrationApply(OptOutEntity, Make_LegacyByteAttributePayload(1), {});
    TestEqual(TEXT("opted-out byte attribute consumes a legacy save payload as Applied"),
        OptOutApply, ECk_Persistence_ApplyResult::Applied);
    TestEqual(TEXT("opted-out byte attribute gains no modifiers from a legacy payload"),
        Get_ModifierChildCount(OptOutEntity), 0);
    TestEqual(TEXT("opted-out byte attribute keeps its constructed base value"),
        static_cast<int32>(UCk_Utils_ByteAttribute_UE::Get_BaseValue(OptOutAttribute, ECk_MinMaxCurrent::Current)), 0);

    // ---- THE REGRESSION GUARD: the opt-out is save transport only ---------------------------------------------
    // Produce is the one projection the WIRE publishes through (TProcessor_Attribute_Replicate ->
    // UCk_Utils_Net_UE::TryProduce -> this same handler). If this ever goes unset, every opted-out attribute
    // silently stops replicating and nothing else in the suite would say so.
    const auto OptOutProduced = Handler->Produce(OptOutEntity);
    TestTrue(TEXT("opted-out byte attribute STILL produces for the wire (the opt-out is save transport only)"),
        OptOutProduced.IsSet());

    // ---- the gate is the SHARED template, not a per-family copy --------------------------------------------------
    const auto* FloatHandler = FCk_PersistenceHandlerRegistry::Find(FCk_RepData_FloatAttributes::StaticStruct());
    if (NOT TestNotNull(TEXT("float attribute save handler registered"), FloatHandler))
    { return true; }

    auto FloatWorld = ck::FEcsWorld{};
    auto FloatOwner = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(FloatWorld.Get_Registry());
    auto FloatParams = FCk_Fragment_FloatAttribute_ParamsData{TAG_Test_V3_PersistValueAttribute, 3.0f};
    FloatParams.Set_PersistValue(ECk_EnableDisable::Disable);
    auto FloatAttribute = FCk_Handle{UCk_Utils_FloatAttribute_UE::Add(
        FloatOwner, FloatParams, ECk_Replication::DoesNotReplicate)};

    TestTrue(TEXT("opted-out float attribute is marked reconstruct-only"),
        FloatAttribute.Has<ck::FTag_Snapshot_ReconstructOnly>());
    TestTrue(TEXT("opted-out float attribute STILL produces for the wire"),
        FloatHandler->Produce(FloatAttribute).IsSet());
    // A NON-EMPTY payload, deliberately: an empty Attributes array returns Applied with or without the
    // gate, so the empty form would pass vacuously and prove nothing about the float family.
    auto FloatLegacy = FCk_RepData_FloatAttributes{};
    FloatLegacy.Attributes.Emplace(FCk_Fragment_FloatAttribute_BaseFinal{
        TAG_Test_V3_PersistValueAttribute, 9.0f, 9.0f, ECk_MinMaxCurrent::Current});

    TestEqual(TEXT("opted-out float attribute consumes a legacy save payload as Applied"),
        FloatHandler->HydrationApply(FloatAttribute, FInstancedStruct::Make(FloatLegacy), {}),
        ECk_Persistence_ApplyResult::Applied);
    TestEqual(TEXT("opted-out float attribute gains no modifiers from a legacy payload"),
        Get_ModifierChildCount(FloatAttribute), 0);
    return true;
}

#endif // WITH_DEV_AUTOMATION_TESTS
