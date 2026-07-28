#include "CkTests/Net/CkAutoTest_NetSubject_DependentSubtree.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"

#include "EngineUtils.h"
#include "Engine/World.h"

#include <StructUtils/InstancedStruct.h>

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_DependentChild_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Minimal — the child only needs to exist as a replicated dependent. No fragments of its own.
    return Super::Construct(InHandle, InSpawnParams);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_DependentSubtree_EntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super::Construct establishes the actor<->entity bridge (OwningActor) and must run before we
    // spawn children — the children's replication drivers walk the ownership chain looking for a
    // replicated outer Actor, which the bridge provides.
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    using namespace ck::auto_test::dependent_subtree;

    // Spawn the wide fan of dependent children on THIS handle while it still carries
    // FTag_EntityJustCreated (it does — we're inside its Construct). Each child is therefore set up as
    // a dependent replication driver of the parent on the server, and races the parent's construction
    // on the client.
    for (auto ChildIdx = 0; ChildIdx < NumDependentChildren; ++ChildIdx)
    {
        UCk_Utils_EntityScript_UE::Request_SpawnEntity(
            InHandle,
            UCk_AutoTest_NetSubject_DependentChild_EntityScript_UE::StaticClass(),
            FInstancedStruct{},
            {});
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_DependentSubtree_UE::
    ACk_AutoTest_NetSubject_DependentSubtree_UE()
{
    _EntityScriptClass = UCk_AutoTest_NetSubject_DependentSubtree_EntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTest_NetSubject_DependentSubtree_UE::
    Find(
        UWorld* InWorld)
    -> ACk_AutoTest_NetSubject_DependentSubtree_UE*
{
    if (InWorld == nullptr)
    { return nullptr; }

    for (auto It = TActorIterator<ACk_AutoTest_NetSubject_DependentSubtree_UE>(InWorld); It; ++It)
    { return *It; }

    return nullptr;
}

// --------------------------------------------------------------------------------------------------------------------
