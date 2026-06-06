#pragma once

#include "CoreMinimal.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"
#include "CkTests/Net/CkAutoTest_NetSubject_EntityScript.h"

#include "CkAutoTest_NetSubject_M2bProbe.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// M2b-1 level-reload gate probe. The entity-script behaves like the default net-subject script (adds
// FloatAttribute.Health) but OPTS IN to snapshot respawn (Get_IsSnapshotRespawnable -> true) so that after
// save -> OpenLevel reload -> load, the restored entity re-spawns an actor of the probe class and re-bridges it.
// Framework infrastructure actors (relays) do NOT opt in, so they are not entity-respawned.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_NetSubject_M2bProbe_EntityScript_UE : public UCk_AutoTest_NetSubject_EntityScript_UE
{
    GENERATED_BODY()

protected:
    virtual auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API ACk_AutoTest_NetSubject_M2bProbe : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_M2bProbe();
};

// --------------------------------------------------------------------------------------------------------------------
