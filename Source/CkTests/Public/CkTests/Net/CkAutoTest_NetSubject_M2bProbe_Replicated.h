#pragma once

#include "CoreMinimal.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkAutoTest_NetSubject_M2bProbe_Replicated.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// M2b-2a replicated level-reload gate probe. Identical to ACk_AutoTest_NetSubject_M2bProbe EXCEPT bReplicates=true.
// Reuses UCk_AutoTest_NetSubject_M2bProbe_EntityScript_UE (Get_IsSnapshotRespawnable -> true). The replicated
// restored entity's respawn re-establishes the EntityReplicationDriver via a scheduler-tick processor (M2b-2a),
// instead of M2b-1's FTSTicker path which crashes for replicated entities.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_NetSubject_M2bProbe_Replicated : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_M2bProbe_Replicated();
};

// --------------------------------------------------------------------------------------------------------------------
