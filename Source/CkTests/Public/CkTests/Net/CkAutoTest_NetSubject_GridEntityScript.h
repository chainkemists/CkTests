#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_GridEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Variant of UCk_AutoTest_NetSubject_EntityScript_UE that creates an occupancy-capable grid + a
// GridObject occupant during Construct, then writes the resulting handles to the parent actor's
// `_TestGrid` / `_TestOccupant` fields. Both worlds run this Construct via the entity-script
// lifecycle's replication path — the structural setup is SYMMETRIC (mandatory for the container
// replication pattern: each world builds the same grid/occupant locally, and only the placement
// record's contents flow server->client).
//
// SETUP (per world, no authority gating):
//   - Grid: a child entity of the subject's bridged entity, with a `Replicates` Transform, then
//     a 10x10 occupancy-capable grid (default cells enabled). The grid's placement record
//     replicates via FCk_RepData_2dGridPlacements once a placement is added on the authority. The
//     container fragment is auto-added by the first Request_Place; it replicates because the grid
//     entity's ownership chain reaches the replicated NetSubject actor.
//   - Occupant: a separate child entity, with a `Replicates` Transform (to establish it as a
//     replicated entity), then a 1x1 GridObject feature.
//
// We do NOT place anything here — the net test drives Request_Place on the server.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_GridEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
