#include "CkTests/Net/CkAutoTest_NetSubject_InventoryEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Inventory.h"
#include "CkTests/CkTests_Fragment_Data.h"

#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Utils.h"
#include "CkInventory/Inventory/Spatial/CkInventory_Spatial_Utils.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "GameplayTagContainer.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::netsubject_inventory
{
    constexpr auto InventoryCapacity = int32{5};
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_InventoryEntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

auto
    UCk_AutoTest_NetSubject_InventoryEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    using namespace ck::auto_test::netsubject_inventory;

    // Use the registered native tag — an unregistered name resolves to empty/None → the inventory gets an
    // unnamed label → the v3 snapshot capture won't persist it → its items can't round-trip (mirrors the
    // Spatial tag below). See TAG_Inventory_AutoTest_Net in CkTests_Fragment_Data.
    const auto InventoryTag = TAG_Inventory_AutoTest_Net.GetTag();

    auto Params = UCk_Utils_Inventory_DataOnly_UE::Make_Params_Bounded(
        InventoryTag,
        InventoryCapacity,
        FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic{},
        FCk_Delegate_Inventory_CustomCanStackItems_Dynamic{});

    auto Inventory = UCk_Utils_Inventory_DataOnly_UE::Add(InHandle, Params, ECk_Replication::Replicates);

    // Replicated Spatial (grid) inventory alongside the DataOnly one. The CkInventory Spatial net
    // test adds an item here on the server and polls the replicated item count on the client via
    // the FCk_RepData_Inventory_Spatial_Items handler.
    // Registered native tag (see CkTests_Fragment_Data) — a distinct, valid name so the client can
    // disambiguate the Spatial inventory from the DataOnly one on the same owner during replication.
    const auto SpatialInventoryTag = TAG_Inventory_AutoTest_Net_Spatial.GetTag();

    auto SpatialParams = UCk_Utils_Inventory_Spatial_UE::Make_Params(
        SpatialInventoryTag,
        FIntPoint{5, 5},
        FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic{},
        FCk_Delegate_Inventory_CustomCanStackItems_Dynamic{});

    auto SpatialInventory = UCk_Utils_Inventory_Spatial_UE::Add(InHandle, SpatialParams, ECk_Replication::Replicates);

    // Stash the handle on this world's actor so the AS test body can find it without needing
    // an inventory-side ownership-chain helper (which CkInventory doesn't expose).
    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    if (auto* InventoryActor = Cast<ACk_AutoTest_NetSubject_Inventory_UE>(OwningActor))
    {
        InventoryActor->_TestInventory = Inventory;
        InventoryActor->_TestInventory_Spatial = SpatialInventory;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
