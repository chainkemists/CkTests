#include "CkTests/Net/CkAutoTest_NetSubject_InventoryEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Inventory.h"

#include "CkInventory/Inventory/DataOnly/CkInventory_DataOnly_Utils.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "GameplayTagContainer.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::netsubject_inventory
{
    constexpr auto InventoryTagName = TEXT("Inventory.AutoTest_Net");
    constexpr auto InventoryCapacity = int32{5};
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_InventoryEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    using namespace ck::auto_test::netsubject_inventory;

    const auto InventoryTag = FGameplayTag::RequestGameplayTag(FName{InventoryTagName});

    auto Params = UCk_Utils_Inventory_DataOnly_UE::Make_Params_Bounded(
        InventoryTag,
        InventoryCapacity,
        FCk_Delegate_Inventory_CustomCanAcceptItem_Dynamic{},
        FCk_Delegate_Inventory_CustomCanStackItems_Dynamic{});

    auto Inventory = UCk_Utils_Inventory_DataOnly_UE::Add(InHandle, Params, ECk_Replication::Replicates);

    // Stash the handle on this world's actor so the AS test body can find it without needing
    // an inventory-side ownership-chain helper (which CkInventory doesn't expose).
    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    if (auto* InventoryActor = Cast<ACk_AutoTest_NetSubject_Inventory_UE>(OwningActor))
    {
        InventoryActor->_TestInventory = Inventory;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
