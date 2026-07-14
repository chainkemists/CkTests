#include "CkTests/Net/CkAutoTest_NetSubject_RefillSnapshotProbe_Replicated.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_RefillSnapshotProbe_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated::
    ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated()
{
    bReplicates = true;
    _EntityScriptClass = UCk_AutoTest_NetSubject_RefillSnapshotProbe_EntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------
