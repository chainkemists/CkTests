#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe_Replicated.h"

#include "CkTests/Net/CkAutoTest_NetSubject_M2bProbe.h" // UCk_AutoTest_NetSubject_M2bProbe_EntityScript_UE

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_M2bProbe_Replicated::
    ACk_AutoTest_NetSubject_M2bProbe_Replicated()
{
    // M2b-2a: replicated. The restored entity re-adds the EntityReplicationDriver during respawn; that driver
    // create now runs inside the ECS scheduler tick (FProcessor_ActorRespawn), NOT the FTSTicker, so it is safe.
    bReplicates = true;
    _EntityScriptClass = UCk_AutoTest_NetSubject_M2bProbe_EntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------
