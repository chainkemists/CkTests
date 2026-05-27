#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_RelationshipEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Variant of UCk_AutoTest_NetSubject_EntityScript_UE that adds Player + Team child entities
// via UCk_Utils_Player_UE::Add and UCk_Utils_Team_UE::Add. Both worlds run this Construct via
// the entity-script lifecycle's replication path, so each world independently builds the
// child entities. Player ID + Team ID values propagate via the FCk_RepData_Player /
// FCk_RepData_Team SyncReplication handlers when the server calls Request_SetPlayerID /
// Request_SetTeamID.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_RelationshipEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
