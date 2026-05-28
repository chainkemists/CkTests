#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_EntityCollectionEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Variant of UCk_AutoTest_NetSubject_EntityScript_UE that creates a replicated EntityCollection on
// the subject's own entity during Construct, then writes the resulting handle to the parent
// actor's `_TestCollection` field. Both worlds run this Construct via the entity-script
// lifecycle's replication path. Collection contents (entries added by Request_AddEntities) flow
// to the client via the FCk_RepData_EntityCollections handler.
//
// Collection tag: `EntityCollection.AutoTest_Net` (registered ad-hoc via
// FGameplayTag::RequestGameplayTag — keeps the test self-contained, no tag-config commit).
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_EntityCollectionEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
