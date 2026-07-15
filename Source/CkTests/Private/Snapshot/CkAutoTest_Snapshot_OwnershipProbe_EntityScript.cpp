#include "CkTests/Snapshot/CkAutoTest_Snapshot_OwnershipProbe_EntityScript.h"

#include "CkCore/Enums/CkEnums.h"

UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE::
    UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE()
{
    _Replication = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

auto
    UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}
