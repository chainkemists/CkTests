#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityScript/CkEntityScript.h"

#include "CkAutoTest_Snapshot_TransformProbe_EntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Minimal PURE-ECS (non-actor-bridged) entity script for the CkSnapshot G1 Transform-parity gate
// (Ck.Snapshot.Parity.Transform_MPReload). Spawned via Request_SpawnEntity, so it persists as a RuntimeSpawned
// entity (FFragment_SpawnRecipe is always stamped at spawn) whose _SavedWorldTransform column captures its live
// world transform.
//
// Construct adds a DoesNotReplicate Transform at IDENTITY — the deliberate "construct default". The gate MOVES the
// entity to a distinct world transform pre-save; on load, Construct re-adds the Transform at Identity and the
// snapshot's DoApply_SavedTransforms re-drives it (pure-ECS mover branch) to the saved transform. Asserting the
// restored entity ends at the MOVED transform (not Identity) proves the new _SavedWorldTransform column did the
// work, not Construct re-derivation.
//
// DoesNotReplicate + no owning actor: keeps the gate server-side (authority) only — mirrors the Timer parity gate's
// unreplicated-feature philosophy. The transform rides the entity table, so no client net-correlation is needed.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_TransformProbe_EntityScript_UE : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_TransformProbe_EntityScript_UE();

    // The construct-default transform the entity is (re-)built at. A save moves the entity away from this; the
    // restored entity must NOT read back at this value if _SavedWorldTransform did its job.
    static auto
    Get_ConstructDefaultTransform() -> FTransform { return FTransform::Identity; }

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
