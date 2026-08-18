#pragma once

#include "CoreMinimal.h"

#include "CkEcs/Handle/CkHandle.h"

#include "CkSnapshot/Snapshot/CkSnapshot_LoadReport.h"
#include "CkSnapshot/Subsystem/CkSnapshot_Signals.h" // FCk_Delegate_Snapshot_OnPreLoad / _OnLoadComplete

#include "CkAutoTest_Snapshot_PromiseListener.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// A subscriber for Promise_OnLoadComplete that OUTLIVES the load's level travel.
//
// A dynamic delegate binds a UObject and a function name, so the subscriber has to survive the travel for the
// promise to be deliverable at all — which is the point of the promise being subsystem-held. A test fixture is
// not automatically GC-safe across a travel, so the test roots this and unroots it at the end.
//
// It can also RE-ARM from inside its own callback, which is how the one-shot semantics get tested from the one
// place a sticky promise would show up: the re-arm must take the immediate no-load-in-progress path (the load has
// already cleared its flag by the time promises drain) and must not land in the list being iterated.
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_AutoTest_Snapshot_PromiseListener_UE : public UObject
{
    GENERATED_BODY()

public:
    // Arms the promise from the pre-travel world, mid-load. Bound to OnPreLoad because that signal fires from
    // inside Request_Load, after the load latches — the one moment a pre-travel bind is both possible and
    // meaningful. Arms at most once, so a two-load test still measures a single promise.
    UFUNCTION()
    void
    OnPreLoad(
        FCk_Handle InHandle);

    UFUNCTION()
    void
    OnLoadComplete(
        FCk_Handle InHandle,
        FCk_Snapshot_LoadReport InReport);

public:
    int32 _ArmCount = 0;
    int32 _FireCount = 0;
    ECk_SnapshotResult _LastResult = ECk_SnapshotResult::Failed_IO;
    bool _LastHandleWasValid = false;

    // Re-arm behaviour for the one-shot gate.
    bool _ReArmInsideCallback = false;
    int32 _ReArmFireCount = 0;
    ECk_SnapshotResult _ReArmResult = ECk_SnapshotResult::Failed_IO;
    bool _ReArmReturnedNoLoadInProgress = false;

public:
    UFUNCTION()
    void
    OnReArmedFire(
        FCk_Handle InHandle,
        FCk_Snapshot_LoadReport InReport);
};

// --------------------------------------------------------------------------------------------------------------------
