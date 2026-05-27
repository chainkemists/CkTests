#pragma once

#include "CoreMinimal.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkAutoTest_NetSubject_Refill.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Subject-actor variant whose entity-script is the refill-enabled `UCk_AutoTest_NetSubject_RefillEntityScript_UE`.
// Used by `Ck.Attribute.Net.Float_Refill_Replicates` to exercise CkAttribute's refill processor
// under multi-client replication — a continuous per-tick value-change scenario, in contrast
// to the discrete one-shot mutations in the Override / ModifierAdd / ModifierRemove tests.
//
// All the work is in the base class. The subclass exists purely to set `_EntityScriptClass` in
// its constructor — keeping the per-test setup-config localised to one place rather than
// branching inside the shared NetSubject's BeginPlay.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_NetSubject_Refill : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_Refill();
};
