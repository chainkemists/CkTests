#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"
#include "CkStateMachine/State/EntityScripts/CkSmState_EntityScript.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "UObject/SoftObjectPath.h"

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super::Construct sets up the WithActor bridge (OwningActor + Transform + Label) and must
    // run before we add the SM — the SM's replication driver needs an OwningActor in the chain
    // to bind its rep payload to a replicated outer Actor.
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    auto Params = FCk_Fragment_StateMachine_ParamsData{Get_InitialStateClass()};
    Params.Set_Replication(ECk_Replication::Replicates);
    Params.Set_AuthorityModel(Get_AuthorityModel());
    Params.Set_ReplicationModel(Get_ReplicationModel());
    Params.Set_AutoStart(Get_AutoStart());

    auto SM = UCk_Utils_StateMachine_UE::Add(InHandle, Params);

    auto* OwningActor = UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle);
    DoStashStateMachine(OwningActor, SM);

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::
    DoStashStateMachine(
        AActor* InOwningActor,
        const FCk_Handle_StateMachine& InSM)
    -> void
{
    if (auto* SmActor = Cast<ACk_AutoTest_NetSubject_StateMachine_UE>(InOwningActor))
    {
        SmActor->_TestStateMachine = InSM;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineOwningClientEntityScript_UE::
    DoStashStateMachine(
        AActor* InOwningActor,
        const FCk_Handle_StateMachine& InSM)
    -> void
{
    if (auto* PawnSubject = Cast<ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn>(InOwningActor))
    {
        PawnSubject->_TestStateMachine = InSM;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineEntityScript_UE::
    Get_InitialStateClass() const
    -> TSubclassOf<UCk_SmState_EntityScript>
{
    return UCk_AutoTest_Sm_RecordingState_A::StaticClass();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_StateMachineOwningClientSubSmEntityScript_UE::
    Get_InitialStateClass() const
    -> TSubclassOf<UCk_SmState_EntityScript>
{
    // AS state classes aren't visible to C++ at compile time. Resolve the AngelScript-authored
    // parent state by package path (leading 'U' is stripped from the AS class name in the UClass
    // FName, per the /Script/Angelscript.<Name> convention). Returns null if the AS topology failed
    // to compile — Construct's StateMachine Add then ensures on the invalid initial-state class,
    // surfacing the real cause instead of a silent no-SM.
    static const auto AsParentHoldPath = FSoftClassPath{TEXT("/Script/Angelscript.Ck_SmNetSubTest_Parent_Hold")};
    return AsParentHoldPath.TryLoadClass<UCk_SmState_EntityScript>();
}

// --------------------------------------------------------------------------------------------------------------------
