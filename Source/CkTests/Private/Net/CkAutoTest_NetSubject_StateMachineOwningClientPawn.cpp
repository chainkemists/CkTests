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

ACk_AutoTest_NetSubject_StateMachineOwningClientNoHistory_Pawn::
    ACk_AutoTest_NetSubject_StateMachineOwningClientNoHistory_Pawn()
{
    // Same actor setup as the base owning-client pawn (inherited ctor already configured replication,
    // root component, etc.); only swap the bridged entity-script to the NoHistory owning-client one.
    _EntityScriptClass = UCk_AutoTest_NetSubject_StateMachineOwningClientNoHistoryEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn::
    ACk_AutoTest_NetSubject_StateMachineOwningClientSubSm_Pawn()
{
    // Inherited owning-client actor setup; bridge to the SubSm owning-client entity-script (initial
    // state = AS UCk_SmNetSubTest_Parent_Hold, which hosts a SubStateMachine task).
    _EntityScriptClass = UCk_AutoTest_NetSubject_StateMachineOwningClientSubSmEntityScript_UE::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject_StateMachineOwningClientSubSmGated_Pawn::
    ACk_AutoTest_NetSubject_StateMachineOwningClientSubSmGated_Pawn()
{
    // Inherited owning-client actor setup; bridge to the SubSmGated entity-script (composes the byte
    // "input" + float "speed" attributes and builds the SM whose initial state is the AS
    // UCk_SmNetSubGatedTest_Parent_Hold — a byte-attr-gated sub-SM with an authority-gated task).
    _EntityScriptClass = UCk_AutoTest_NetSubject_StateMachineOwningClientSubSmGatedEntityScript_UE::StaticClass();
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
