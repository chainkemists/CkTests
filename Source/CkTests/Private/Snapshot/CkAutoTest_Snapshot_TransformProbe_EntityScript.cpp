#include "CkTests/Snapshot/CkAutoTest_Snapshot_TransformProbe_EntityScript.h"

#include "CkEcsExt/Transform/CkTransform_Utils.h"

#include "CkCore/Enums/CkEnums.h" // ECk_Replication

// --------------------------------------------------------------------------------------------------------------------

UCk_AutoTest_Snapshot_TransformProbe_EntityScript_UE::
    UCk_AutoTest_Snapshot_TransformProbe_EntityScript_UE()
{
    // Authority-only (no replication) + no pooling. The transform rides the entity table and is asserted on the
    // host, so the child never needs to net-correlate to a client entity. Non-poolable keeps re-Construct across
    // teardown deterministic. Mirrors the Timer parity gate's unreplicated philosophy.
    _Replication      = ECk_Replication::DoesNotReplicate;
    _InstancingPolicy = ECk_EntityScript_InstancingPolicy::InstancedPerEntity;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_Snapshot_TransformProbe_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    // Pure-ECS Transform at the construct default (Identity). No RootComponent -> no actor bridge, so the restore's
    // DoApply_SavedTransforms treats it as a pure-ECS mover (Request_SetTransform), not an actor SetActorTransform.
    UCk_Utils_Transform_UE::Add(
        InHandle, Get_ConstructDefaultTransform(), ECk_Replication::DoesNotReplicate);

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
