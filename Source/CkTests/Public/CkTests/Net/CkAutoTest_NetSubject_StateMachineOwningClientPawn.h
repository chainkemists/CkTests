#pragma once

#include "CoreMinimal.h"

#include "GameFramework/Pawn.h"
#include "Templates/SubclassOf.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"

#include "CkAutoTest_NetSubject_StateMachineOwningClientPawn.generated.h"

class UCk_EntityScript_WithActor_UE;

// --------------------------------------------------------------------------------------------------------------------
//
// Pawn subject for OwningClientAuthoritative SM net tests. Must be an APawn (not a plain AActor)
// because OwningClientAuth authority resolves via UCk_Utils_Net_UE::Get_IsActorLocallyControlled_ByPlayer,
// which requires the owning actor to be an APawn that IsLocallyControlled() && IsPlayerControlled()
// (CkNet_Utils.cpp). The test possesses this pawn with a remote client's PlayerController on the
// server (Get_RemoteClientPlayerController), so on the client world it reports locally-controlled
// and the SM's owning client becomes the authority.
//
// Mirrors ACk_AutoTest_NetSubject's bridge pattern: on BeginPlay (authority) it spawns a WithActor
// entity-script (the OwningClientAuth SM entity-script) bridged to this pawn, on both worlds via
// the entity-script replication path. The entity-script stashes the SM handle in `_TestStateMachine`.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn : public APawn
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_StateMachineOwningClient_Pawn();

protected:
    virtual auto BeginPlay() -> void override;

public:
    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_StateMachine _TestStateMachine;

protected:
    UPROPERTY()
    TSubclassOf<UCk_EntityScript_WithActor_UE> _EntityScriptClass;
};
