#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkAutoTest_NetSubject_RefillEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Variant of UCk_AutoTest_NetSubject_EntityScript_UE that adds a Float attribute with refill
// enabled. Used by `ACk_AutoTest_NetSubject_Refill` to exercise the CkAttribute refill
// processor's per-tick value changes under multi-client replication — a qualitatively
// different scenario from the discrete Override / ModifierAdd / ModifierRemove tests, which
// only exercise one-shot mutation paths.
//
// Both worlds run this Construct via the entity-script lifecycle's replication path, so each
// world independently constructs the attribute + refill child entities. The actual per-tick
// value writes flow through the container fragment SyncReplication handler the same way
// discrete mutations do — the test asserts both worlds converge on the same non-zero value
// after a settle window.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_RefillEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;
};
