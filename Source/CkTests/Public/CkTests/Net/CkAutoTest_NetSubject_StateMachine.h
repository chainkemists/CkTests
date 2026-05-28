#pragma once

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"

#include "CkAutoTest_NetSubject_StateMachine.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Variant of ACk_AutoTest_NetSubject that bridges to the StateMachine-flavoured entity-script
// (UCk_AutoTest_NetSubject_StateMachineEntityScript_UE). The entity-script's Construct creates a
// Replicates / ServerAuthoritative / WithHistory state machine with initial state A on the bridged
// entity, on both worlds (symmetric setup) — that's the missing piece for SM rep to flow, since
// the SM rep payload only has a target on each world if both worlds have an SM entity sharing the
// rep payload's container slot.
//
// `_TestStateMachine` is a transient, local-only field — NOT replicated. Each world's entity-script
// independently populates its own world's actor. The SM's transitions replicate via the
// FCk_RepData_StateMachine_WithHistory rep handler.

UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_StateMachine_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_StateMachine_UE();

public:
    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_StateMachine _TestStateMachine;
};

// --------------------------------------------------------------------------------------------------------------------
