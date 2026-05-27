#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_InventoryEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Variant of UCk_AutoTest_NetSubject_EntityScript_UE that creates a replicated bounded DataOnly
// inventory child entity (capacity 5) on the subject's entity during Construct, and writes
// the resulting handle to the parent actor's `_TestInventory` field. Both worlds run this
// Construct via the entity-script lifecycle's replication path. Item-content mutations made by
// the server flow to the client via the FCk_RepData_Inventory_DataOnly_Items handler.
//
// Inventory tag: `Inventory.AutoTest_Net` (registered ad-hoc via FGameplayTag::RequestGameplayTag
// rather than a project-side tag config — keeps the test self-contained).
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_InventoryEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
