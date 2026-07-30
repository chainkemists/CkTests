#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/EntityScript/CkEntityScript_Fragment_Data.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Processor/CkProcessor.h"
#include "CkEcs/Scheduler/CkProcessorGroups.h"
#include "CkEcs/Tag/CkTag.h"

#include "CkAutoTest_Snapshot_StagedConstruction.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Staged-construction snapshot fixture: the smallest framework-pure reproduction of the deep-hierarchy shape that
// orphaned on a real load (a parent script defer-spawns labeled children whose construction is COMPLETED BY A GAME
// PROCESSOR, i.e. one the load kernel cannot run):
//
//   parent (RuntimeSpawned, respawnable, transient-owned)
//     └─ N children (ConstructSpawned): Construct composes a FloatAttribute then returns `Continue`; a
//        default-LoadPolicy (GatedDuringLoad) processor finishes the construction; the parent stamps each child's
//        slot GameplayLabel — the loader's adopt key — in the OnConstructed promise callback
//          ├─ FloatAttribute child entity (ConstructSpawned, labeled by attribute name) carrying the payload
//          ├─ IntegerAttribute meter child (ConstructSpawned, labeled Meter)
//          └─ the meter's refill child — a FLOAT attribute sibling labeled with the SAME Meter name, so the save
//             holds two ConstructSpawned rows under one (owner, label) adopt key; only the adoption scan's
//             claimed-child exclusion can bind the pair apart (the tourist shop-cost incident, 2026-07-29)
//
// Every stage is deliberate: the gated setup processor makes the children UNFINISHABLE under the load kernel, and
// the promise-stamped label makes their adopt key arrive only once construction finishes — so a load of this
// hierarchy can only succeed if the rebuild escalates to full-scope ticks instead of orphaning at kernel stall.
// --------------------------------------------------------------------------------------------------------------------

class UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE;

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_AutoTest_StagedConstruction_NeedsSetup);
    CK_DEFINE_ECS_TAG(FTag_AutoTest_StagedConstruction_KeeperOwner);
    CK_DEFINE_ECS_TAG(FTag_AutoTest_StagedConstruction_KeeperSpawnLatched);
}

namespace ck_autotest_staged_construction
{
    constexpr int32 NumSlots = 3;

    auto Get_SlotLabel(int32 InSlotIndex) -> FGameplayTag;
    auto Get_ValueAttributeName() -> FGameplayTag;
    auto Get_MeterAttributeName() -> FGameplayTag; // shared by the meter AND its refill child — the collision key

    // Children of InParent whose script is the population keeper. bRequireBegunPlay = the LYING census — the
    // shape real population drivers use (they scan READY entities): mid-load, the loader's respawned keeper
    // exists but has not begun play, so this reads zero while the truth is one.
    auto Get_KeeperChildCount(const FCk_Handle& InParent, bool bRequireBegunPlay = false) -> int32;
}

namespace ck
{
    // Deliberately DEFAULT LoadPolicy (GatedDuringLoad) — the fixture exists to prove the loader can finish
    // constructions that depend on processors outside the load kernel. Do NOT mark this RunsDuringLoad; that
    // would silently turn the whole gate vacuous.
    class CKTESTS_API FProcessor_AutoTest_StagedConstruction_Setup : public TProcessor<
        FProcessor_AutoTest_StagedConstruction_Setup,
        FTag_AutoTest_StagedConstruction_NeedsSetup,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;
        using MarkedDirtyBy = FTag_AutoTest_StagedConstruction_NeedsSetup;

    public:
        using TProcessor::TProcessor;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };

    // The smallest honest mimic of a population driver (NpcPopulation, restock): an every-tick, default-
    // LoadPolicy policy processor that tops the world up when its census reads low. Under an ESCALATED load
    // it RUNS and its census reads a lie (the loader has not respawned the saved keeper yet) — the load-gate
    // spawn suppression is the only thing standing between it and a doubled population. The fixture's gate
    // asserts exactly one keeper survives every cycle and the save's row count never inflates.
    class CKTESTS_API FProcessor_AutoTest_PopulationKeeper : public TProcessor<
        FProcessor_AutoTest_PopulationKeeper,
        FTag_AutoTest_StagedConstruction_KeeperOwner,
        CK_IGNORE_PENDING_KILL>
    {
    public:
        using Group = FGroup_Gameplay_Script;

    public:
        using TProcessor::TProcessor;

    public:
        static auto
        ForEachEntity(
            TimeType InDeltaT,
            HandleType InHandle) -> void;
    };
}

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_StagedChild_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

    auto
    FinishStagedConstruction() -> void;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_PopulationKeeper_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_PopulationKeeper_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_StagedParent_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

    auto
    BeginPlay() -> void override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;

private:
    UFUNCTION()
    void
    OnChildConstructed(
        FCk_Handle_EntityScript InEntityScriptHandle);

private:
    TMap<FCk_Handle, int32> _PendingSlots;
    int32 _RemainingChildren = 0;
};
