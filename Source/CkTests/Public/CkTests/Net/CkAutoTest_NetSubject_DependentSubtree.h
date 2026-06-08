#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkAutoTest_NetSubject_DependentSubtree.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Forcing subject for the dead `_PendingChildEntityConstructions` queue repro
// (Ck.EntityReplicationDriver.Net.DependentChildSubtreeConstructs).
//
// The bug: `UCk_Fragment_EntityReplicationDriver_Rep::OnRep_ReplicationData_EntityScript` parks a
// child driver into `_PendingChildEntityConstructions` when its owning entity isn't constructed yet
// on the client — but nothing ever drains that array, so a child whose OnRep is processed before its
// parent is ready strands forever, and the parent's `Get_IsReplicationCompleteAllDependents` never
// becomes true.
//
// This subject maximises the chance of hitting that ordering race: a single replicated WithActor
// PARENT entity-script that, during its own Construct (while it still carries FTag_EntityJustCreated),
// spawns a *wide* fan of replicated DEPENDENT CHILD entity-scripts. Each child becomes a dependent
// replication driver of the parent (Request_Replicate sees the parent's just-created tag and sets
// _IsOwningEntityDriverDependentOnThis = true). On the client, all those child drivers race the
// parent's construction — exactly the window the dead queue mishandles.
//
// --------------------------------------------------------------------------------------------------------------------

namespace ck::auto_test::dependent_subtree
{
    // Wide fan of dependent children. Picked large enough that, across a handful of runs, at least one
    // child driver is very likely to OnRep before the parent entity resolves on the client (the park
    // branch). Bump this (or add depth) if the race proves stubborn.
    inline constexpr int32 NumDependentChildren = 16;
}

// --------------------------------------------------------------------------------------------------------------------

// A minimal replicated child entity-script. No content of its own — its only job is to exist as a
// replicated dependent of the parent so its driver exercises the parent-not-ready park branch on the
// client. Replicates by default (UCk_EntityScript_UE::_Replication defaults to Replicates).
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_DependentChild_EntityScript_UE : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};

// --------------------------------------------------------------------------------------------------------------------

// The replicated WithActor PARENT entity-script. During Construct it spawns NumDependentChildren
// replicated dependent children on its own handle.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_DependentSubtree_EntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};

// --------------------------------------------------------------------------------------------------------------------

// Subject actor that spawns the dependent-subtree parent entity-script on BeginPlay (authority side),
// via the base ACk_AutoTest_NetSubject machinery.
UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_NetSubject_DependentSubtree_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_DependentSubtree_UE();

    // Discovery helper specific to this subject subclass (the base Find returns the first
    // ACk_AutoTest_NetSubject of any subclass, which is fine when only one subject exists per world,
    // but this typed variant keeps the spec unambiguous).
    static auto
    Find(
        class UWorld* InWorld) -> ACk_AutoTest_NetSubject_DependentSubtree_UE*;
};
