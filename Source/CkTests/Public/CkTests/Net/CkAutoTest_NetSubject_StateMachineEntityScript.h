#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkStateMachine/StateMachine/CkStateMachine_Fragment_Data.h"

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

protected:
    // Overridable so cross-product variants (NoHistory, OwningClientAuth) reuse the same Construct
    // body and only change the params. Base = ServerAuthoritative / WithHistory.
    virtual auto Get_AuthorityModel() const -> ECk_Sm_AuthorityModel { return ECk_Sm_AuthorityModel::ServerAuthoritative; }
    virtual auto Get_ReplicationModel() const -> ECk_Sm_ReplicationModel { return ECk_Sm_ReplicationModel::WithHistory; }
};

// --------------------------------------------------------------------------------------------------------------------
//
// WithoutHistory variant — same setup but _ReplicationModel = WithoutHistory. Drives the
// "snap-to-final-state" replication contract: rapid server transitions A→B→C deliver only the
// latest state to the client (no intermediate replay). Used by
// Ck.StateMachine.Net.ServerAuth_NoHistory_SnapsToFinalState.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_StateMachineNoHistoryEntityScript_UE : public UCk_AutoTest_NetSubject_StateMachineEntityScript_UE
{
    GENERATED_BODY()

protected:
    virtual auto Get_ReplicationModel() const -> ECk_Sm_ReplicationModel override { return ECk_Sm_ReplicationModel::WithoutHistory; }
};
