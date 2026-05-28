#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_StateMachine.h"
#include "CkTests/Net/CkAutoTest_NetSubject_StateMachineOwningClientPawn.h"
#include "CkTests/Net/CkAutoTest_Sm_RecordingState.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Utils.h"
#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

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

    auto Params = FCk_Fragment_StateMachine_ParamsData{UCk_AutoTest_Sm_RecordingState_A::StaticClass()};
    Params.Set_Replication(ECk_Replication::Replicates);
    Params.Set_AuthorityModel(Get_AuthorityModel());
    Params.Set_ReplicationModel(Get_ReplicationModel());
    Params.Set_AutoStart(Get_AutoStart());

    auto SM = UCk_Utils_StateMachine_UE::Add_WithParams(InHandle, Params);

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
