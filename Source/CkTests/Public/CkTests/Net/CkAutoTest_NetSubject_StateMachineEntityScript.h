#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_StateMachineEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Variant of UCk_AutoTest_NetSubject_EntityScript_UE that creates a Replicates / ServerAuthoritative
// / WithHistory state machine on the subject's bridged entity during Construct, initial state A
// (UCk_AutoTest_Sm_RecordingState_A), AutoStart on Setup. Both worlds run this Construct via the
// entity-script lifecycle's replication path, so both worlds end up with an SM entity sharing the
// rep payload's container slot — the precondition for SM transitions to replicate server→client.
//
// The previous WIP ServerAuthReplay test manually spawned a server-only SM on a bare entity via
// Request_CreateEntity + Net::Add + manual SM Add — which gave the client no matching SM target,
// so the rep payload had no client-side OnChange handler firing. Moving SM setup into a WithActor
// entity-script Construct is the established pattern (CkAttribute, CkInventory, CkRelationship all
// do this) and gives the client a symmetric SM entity automatically.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_StateMachineEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
