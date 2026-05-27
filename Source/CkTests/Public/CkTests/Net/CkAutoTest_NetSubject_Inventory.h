#pragma once

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Fragment_Data.h"

#include "CkAutoTest_NetSubject_Inventory.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Variant of ACk_AutoTest_NetSubject that bridges to the inventory-flavoured entity-script
// (UCk_AutoTest_NetSubject_InventoryEntityScript_UE). The entity-script's Construct creates a
// `Replicates` bounded DataOnly inventory child entity on each world (symmetric setup) and
// writes the handle to `_TestInventory` here. AS net-test bodies cast the SubjectActor to this
// class and read `_TestInventory` to operate on the inventory without needing a
// `TryGet_Entity_Inventory_*_InOwnershipChain` helper (which doesn't exist on CkInventory).
//
// `_TestInventory` is a transient, local-only field — NOT replicated. Each world's entity-script
// independently populates its world's actor's `_TestInventory` to point at that world's inventory
// entity. The inventory's contents (items) replicate via the FCk_RepData_Inventory_DataOnly_Items
// rep handler.
UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_Inventory_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_Inventory_UE();

public:
    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_Inventory_DataOnly _TestInventory;
};

// --------------------------------------------------------------------------------------------------------------------
