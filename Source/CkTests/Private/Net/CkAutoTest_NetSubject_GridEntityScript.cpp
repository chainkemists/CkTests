#include "CkTests/Net/CkAutoTest_NetSubject_GridEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_Grid.h"

#include "CkGrid/2dGridSystem/Grid/Ck2dGridSystem_Utils.h"
#include "CkGrid/2dGridSystem/Object/Ck2dGridObject_Utils.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkEcs/EntityLifetime/CkEntityLifetime_Utils.h"
#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkCore/Enums/CkEnums.h"

// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::netsubject_grid
{
    // Small occupancy-capable grid with 1m cells. The net test places a 1x1 occupant at (2,2)
    // and polls that cell's Occupied tag on the client.
    const auto GridDimensions = FIntPoint{10, 10};
    const auto GridCellSize = FVector2D{100.0f, 100.0f};

    // 1x1 occupant footprint — placing it at anchor (2,2) occupies exactly cell (2,2).
    const auto OccupantFootprint = FIntPoint{1, 1};
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_GridEntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_GridEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super::Construct sets up the actor<->entity bridge (OwningActor, transform, label) and must
    // run before we build the grid / occupant — those features need an OwningActor in the chain to
    // resolve the replicated outer Actor for their replicated container fragment(s).
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    using namespace ck::auto_test::netsubject_grid;

    // ---- Grid -------------------------------------------------------------------------------
    // Add the grid DIRECTLY to InHandle (the subject's bridged entity). InHandle is the
    // net-correlated, replicating entity — its replication driver associates the server and client
    // instances — so the occupancy container fragment (added by the first authority-side
    // Request_Place) replicates to the client's correlated InHandle and the RegisterLazy handler
    // fires there. A separately-created child entity is NOT net-correlated (server and client each
    // build their own with no link), so its container has no matching client entity — that was the
    // "No matching PendingEntity" failure. Mirrors how the inventory net-subject adds its inventory
    // to InHandle. The ClientOnly SyncReplication processor filters on FCk_Handle_2dGridSystem, so
    // it runs on this same (grid-bearing) InHandle on the client.
    auto GridParams = FCk_2dGridSystem_Spec{GridDimensions, GridCellSize};
    GridParams.Set_DefaultCellState(ECk_EnableDisable::Enable);

    // InHandle already carries the Transform added by Super::Construct; grid Add needs it as a
    // FCk_Handle_Transform&.
    auto InTransform = UCk_Utils_Transform_UE::Cast(InHandle);
    auto Grid = UCk_Utils_2dGridSystem_UE::Add(InTransform, GridParams);

    // ---- Occupant ---------------------------------------------------------------------------
    // Separate child entity, also given a `Replicates` Transform so it is a replicated entity
    // (the replicated placement entry carries this occupant handle). The cells stamped on the
    // client come from the entry's replicated Cells array, so the Occupied tag flips regardless
    // of whether this handle resolves cross-world — see the AS test's risk note.
    auto OccupantEntity = UCk_Utils_EntityLifetime_UE::Request_CreateEntity(InHandle);
    UCk_Utils_Transform_UE::Add(
        OccupantEntity, FTransform::Identity, ECk_Replication::Replicates);

    UCk_Utils_2dGridObject_UE::Add(
        OccupantEntity, FCk_2dGridObject_Spec{OccupantFootprint});

    // ---- Stash on this world's actor --------------------------------------------------------
    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    if (auto* GridActor = Cast<ACk_AutoTest_NetSubject_Grid_UE>(OwningActor))
    {
        GridActor->_TestGrid = Grid;
        GridActor->_TestOccupant = OccupantEntity;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
