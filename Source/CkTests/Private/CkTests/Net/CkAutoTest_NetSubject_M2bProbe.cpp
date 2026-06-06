#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_M2bProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_M2bProbe::
    ACk_AutoTest_NetSubject_M2bProbe()
{
    // M2b-1 is single-player (Standalone). Non-replicated: the restored entity is DoesNotReplicate, so the
    // respawn's Request_RebindActor -> OwningActor::Add does NOT re-add the EntityReplicationDriver (which
    // Request_CreateEntity's a driver entity mid-FTSTicker -> EntityJustCreated processor null-deref crash).
    // Re-establishing replication on restored entities is M2b-2 (multiplayer) scope.
    bReplicates = false;
    _EntityScriptClass = UCk_AutoTest_NetSubject_M2bProbe_EntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------
