#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineEntityScript.h"

#include "CkEcs/EntityScript/CkEntityScript_Utils.h"
#include "CkEcs/Subsystem/CkEcsWorld_Subsystem.h"
#include "CkEcsExt/EntityScript/CkEntityScript_WithActor_Data.h"

#include "Components/SceneComponent.h"
#include "Engine/World.h"

#include <StructUtils/InstancedStruct.h>

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn::
    ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn()
{
    bReplicates = true;
    bAlwaysRelevant = true;
    bReplicateUsingRegisteredSubObjectList = true;
    PrimaryActorTick.bCanEverTick = false;

    // Movable USceneComponent root — required for UCk_EntityScript_WithActor_UE::Construct to add
    // the Transform fragment (it guards on GetRootComponent()), same as ACk_AutoTest_NetSubject.
    auto* Root = CreateDefaultSubobject<USceneComponent>(TEXT("DefaultSceneRoot"));
    Root->SetMobility(EComponentMobility::Movable);
    RootComponent = Root;

    _EntityScriptClass = UCk_AutoTest_NetSubject_StateMachineOwningClientEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn::
    BeginPlay()
    -> void
{
    Super::BeginPlay();

    if (NOT HasAuthority())
    { return; }

    if (ck::Is_NOT_Valid(_EntityScriptClass))
    { return; }

    // Mirror of ACk_AutoTest_NetSubject::BeginPlay — spawn a WithActor entity bridged to this pawn.
    // The SM is OwningClientAuthoritative, but the entity-script (which creates the SM) still spawns
    // on authority and replicates to the client; authority for *transitions* is the owning client,
    // resolved lazily per NetContext call once this pawn is possessed by that client's PC.
    auto TransientEntity = UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity(GetWorld());
    auto SpawnParams = FInstancedStruct::Make<FCk_EntityScript_WithActor_SpawnParams>(this);
    UCk_Utils_EntityScript_UE::Request_SpawnEntity(
        TransientEntity, _EntityScriptClass, SpawnParams);
}

// --------------------------------------------------------------------------------------------------------------------
