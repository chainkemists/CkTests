#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityScript/CkEntityScript.h"

#include "CkAutoTest_Snapshot_OwnershipProbe_EntityScript.generated.h"

// Minimal pure-ECS scripts for the snapshot ownership parity gate. Each class is distinct so the
// post-travel entities can be resolved by retained spawn recipe without carrying handles across reload.
// All three opt into snapshot respawn, which is required for runtime entities whose saved owner is
// the top-level transient entity.

UCLASS(Abstract, BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE();

protected:
    virtual auto Get_IsSnapshotRespawnable() const -> bool override;
};

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OwnershipProbe_Target_EntityScript_UE final
    : public UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE
{
    GENERATED_BODY()
};
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OwnershipProbe_LifetimeOwner_EntityScript_UE final
    : public UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE
{
    GENERATED_BODY()
};

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_OwnershipProbe_ContextOwner_EntityScript_UE final
    : public UCk_AutoTest_Snapshot_OwnershipProbe_Base_EntityScript_UE
{
    GENERATED_BODY()
};
