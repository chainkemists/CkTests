#pragma once

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkGrid/2dGridSystem/Grid/Ck2dGridSystem_Fragment_Data.h"

#include "CkAutoTest_NetSubject_Grid.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Variant of ACk_AutoTest_NetSubject that bridges to the grid-flavoured entity-script
// (UCk_AutoTest_NetSubject_GridEntityScript_UE). The entity-script's Construct creates a small
// occupancy-capable grid + a GridObject occupant on each world (symmetric setup) and writes the
// resulting handles here. AS net-test bodies cast the SubjectActor to this class and read
// `_TestGrid` + `_TestOccupant` to drive a placement on the server and poll the replicated
// `Occupied` cell tag on the client.
//
// `_TestGrid` / `_TestOccupant` are transient, local-only fields — NOT replicated. Each world's
// entity-script independently populates its world's actor's handles to point at that world's grid
// / occupant entities. The grid's placement record (the {Occupant, Anchor, Rotation, Cells}
// entries) replicates server->client via the FCk_RepData_2dGridPlacements rep handler; the
// client-side reconcile pass stamps the `Occupied` tag on the listed cells.

UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_Grid_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_Grid_UE();

public:
    // The occupancy-capable grid created by the entity-script (per world). The net test drives
    // Request_Place on the server's grid and polls Get_IsOccupied on the client's grid.
    UPROPERTY(Transient, BlueprintReadWrite, Category = "Ck|AutoTest")
    FCk_Handle_2dGridSystem _TestGrid;

    // The GridObject occupant created by the entity-script (per world). Passed as the occupant to
    // Request_Place on the server. Created as a replicated entity so the replicated placement
    // entry's occupant handle has a chance to resolve cross-world (see entity-script docstring).
    UPROPERTY(Transient, BlueprintReadWrite, Category = "Ck|AutoTest")
    FCk_Handle _TestOccupant;
};

// --------------------------------------------------------------------------------------------------------------------
