#pragma once

#include "CoreMinimal.h"

#include "CkObjective/Objective/CkObjective_EntityScript.h"
#include "CkEcs/EntityScript/CkEntityScript.h"

#include "CkAutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript.generated.h"

// Fixture for the ObjectiveOwner default-seeding gate. The owner composes an ObjectiveOwner carrying the two
// leaf classes below as _DefaultObjectives, which FProcessor_ObjectiveOwner_Setup materializes AFTER
// construction closes — so they are RuntimeSpawned rows the loader respawns from their own recipes, while the
// owner's replayed DoConstruct re-stamps NeedsSetup. That combination is the input under test.
//
// The owner opts into snapshot respawn because its saved lifetime owner is the top-level transient entity and
// nothing else re-creates it; without that the rebuild skips it and the gate measures nothing.
//
// The two leaves are distinct classes so post-travel resolution can tell them apart without carrying handles
// across the reload, matching the OwnershipProbe family.

UCLASS(Abstract, BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_ObjectiveProbe_Leaf_EntityScript_UE : public UCk_Objective_EntityScript
{
    GENERATED_BODY()

protected:
    // _ObjectiveName is private on the framework base and has no setter; AngelScript subclasses write it as a
    // CDO default through reflection, and this does the same rather than widening the base's access for a test.
    auto DoSet_ObjectiveName(
        const FGameplayTag& InName) -> void;
};

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_ObjectiveProbe_LeafA_EntityScript_UE final
    : public UCk_AutoTest_Snapshot_ObjectiveProbe_Leaf_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_ObjectiveProbe_LeafA_EntityScript_UE();
};

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_ObjectiveProbe_LeafB_EntityScript_UE final
    : public UCk_AutoTest_Snapshot_ObjectiveProbe_Leaf_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_ObjectiveProbe_LeafB_EntityScript_UE();
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_ObjectiveOwnerProbe_EntityScript_UE();

protected:
    auto Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

    virtual auto Get_IsSnapshotRespawnable() const -> bool override;
};
