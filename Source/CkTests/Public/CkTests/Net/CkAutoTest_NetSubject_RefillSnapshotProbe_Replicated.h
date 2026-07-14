#pragma once

#include "CoreMinimal.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_RefillEntityScript.h"

#include "CkAutoTest_NetSubject_RefillSnapshotProbe_Replicated.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Snapshot refill-parity probe. Reuses UCk_AutoTest_NetSubject_RefillEntityScript_UE (which composes a Float AND an
// Integer refill attribute, both StartingState = Running) and OPTS IN to snapshot respawn so the bridged entity
// survives save -> seamless ServerTravel -> load and re-Constructs on both worlds. That re-Construct resurrects the
// refill run-state to StartingState (Running); the CkAttribute refill run-state persistence handler
// (CkAttribute_RefillPersistence.h) is what restores a runtime Pause across the reload. Dedicated to
// Ck.Snapshot.Parity.AttributeRefill_MPReload so it does NOT perturb the shared M2bProbe subject the other parity gates
// use.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_NetSubject_RefillSnapshotProbe_EntityScript_UE : public UCk_AutoTest_NetSubject_RefillEntityScript_UE
{
    GENERATED_BODY()

protected:
    virtual auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_RefillSnapshotProbe_Replicated();
};

// --------------------------------------------------------------------------------------------------------------------
