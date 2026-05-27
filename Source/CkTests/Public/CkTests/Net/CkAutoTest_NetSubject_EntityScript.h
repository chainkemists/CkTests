#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_EntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Entity script that the AutoTest harness's `ACk_AutoTest_NetSubject` spawns on its bridged
// entity. Subclasses `UCk_EntityScript_WithActor_UE` and adds a Float attribute in `Construct`.
//
// Why a dedicated subclass: CkAttribute replication is *symmetric*. The `FCk_RepData_FloatAttributes`
// container fragment carries values, but the per-attribute child entity must already exist on
// each world before the rep data arrives — otherwise the handler stashes the entry as "pending"
// (`StashPendingFloatAttributeEntry`) and the client-side `TryGet` returns invalid. So both
// server and client must call `UCk_Utils_FloatAttribute_UE::Add` independently. Doing the Add
// from an entity-script `Construct` is the canonical way to ensure both runtimes execute the
// same setup: the entity-script lifecycle replicates, so Construct runs on every world.
//
// Replication of the *value* (e.g. after a server-side `Request_Override`) flows through the
// existing container-fragment SyncReplication handler — that part needs no special wiring.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_EntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
