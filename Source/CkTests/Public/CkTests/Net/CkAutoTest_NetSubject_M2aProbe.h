#pragma once

#include "CoreMinimal.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_EntityScript.h"

#include <atomic>

#include "CkAutoTest_NetSubject_M2aProbe.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// M2a load-orchestration gate probe. The entity-script behaves like the default net-subject script (it adds
// FloatAttribute.Health via the inherited Construct) but counts EndPlay invocations in a process-global atomic.
// That counter is the gate's proof that the M2a load TEARDOWN actually ran the EndPlay pipeline (vs M1's bare
// registry.clear(), which skips EndPlay). It also OPTS IN to snapshot respawn (Get_IsSnapshotRespawnable -> true,
// like the M2b probe) so that under the v3 rebuild+hydrate loader the actor is re-spawned after reload and its
// FloatAttribute re-composes — without the opt-in the WithActor entity is treated as non-respawnable and skipped.
// The subject subclass exists only to swap in the probe entity-script.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_NetSubject_M2aProbe_EntityScript_UE : public UCk_AutoTest_NetSubject_EntityScript_UE
{
    GENERATED_BODY()

public:
    static std::atomic<int32> GEndPlayCount;

    virtual auto
    EndPlay() -> void override;

protected:
    virtual auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_NetSubject_M2aProbe : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_M2aProbe();
};
