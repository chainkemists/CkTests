#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Tag/CkTag.h"

#include "CkAutoTest_Snapshot_Quarantine.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Hydration-quarantine fixture: an entity whose payload can NEVER apply, so a load can only end through the
// quarantine's bounded escape.
//
// The stall is a handler that always answers NotReady. On its own that does NOT reach the escape — the dispatcher
// accrues pending time and drops the entry loudly at the apply timeout, which empties the queue and lets the NORMAL
// release fire, roughly halfway to the frame cap. So the test also shortens the cap below that timeout
// (TestOnly_Set_HydrateFrameCapOverride), which makes the escape the only reachable exit and keeps the run short.
//
// The dispatcher's OTHER stall — re-stamping FTag_EntityScript_ConstructedThisFrame so the entry is skipped before
// the handler is called — does not work here: the dispatcher clears that tag after its loop and the same frame's
// pump re-dispatches the entity, so the deferral lasts one pass, not one frame.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    // Marks the probe as the one entity the stall handler produces a payload for, so the handler is inert in every
    // other test sharing this build.
    CK_DEFINE_ECS_TAG(FTag_AutoTest_Quarantine_Probe);
}

// --------------------------------------------------------------------------------------------------------------------

// Payload whose HydrationApply never succeeds. It carries a value only so the payload is not empty.
USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_QuarantineStall
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_QuarantineStall);

private:
    UPROPERTY()
    int32 _Marker = 0;

public:
    CK_PROPERTY(_Marker);
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_QuarantineProbe_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

    // Binds Promise_OnHydrated before the load could possibly have lifted, so the escape has a waiting consumer
    // to strand. Tenet 10: a terminal outcome has to reach somebody, and "the payload never applied" is still a
    // terminal outcome.
    auto
    BeginPlay() -> void override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;

private:
    UFUNCTION()
    void
    OnHydrated(
        FCk_Handle InHandle);
};

// --------------------------------------------------------------------------------------------------------------------

namespace ck_autotest_snapshot_quarantine
{
    // How many times the probe's promise was delivered. Process-wide: the bind is made in the pre-save world and
    // the delivery happens in the post-load one, so nothing entity-scoped survives to carry it.
    CKTESTS_API auto Get_OnHydratedFireCount() -> int32&;
}

// --------------------------------------------------------------------------------------------------------------------
