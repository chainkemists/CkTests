#pragma once

#include "CoreMinimal.h"

#include "CkEcs/EntityScript/CkEntityScript.h"
#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Tag/CkTag.h"

#include "CkAutoTest_Snapshot_NoHandlerPayload.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// A saved payload whose type has NO load path, reached through a real save/load.
//
// The registry is symmetric by construction — a handler cannot register a Produce without a HydrationApply, and a
// type registered in this process at save time is still registered at load time — so the scenario has to be built
// the way it actually occurs in the field: a handler that EMITS a struct type other than the one it registered.
// The capture stamps the row with the registered type path but serializes the produced struct, and FInstancedStruct
// carries its own type, so the load resolves the EMITTED type, finds no HydrationApply, and drops the entry. That
// is exactly "the save recorded state this build cannot apply", and it is an authoring mistake that can ship.
// --------------------------------------------------------------------------------------------------------------------

namespace ck
{
    CK_DEFINE_ECS_TAG(FTag_AutoTest_NoHandlerPayload_Probe);
}

// --------------------------------------------------------------------------------------------------------------------

// Registered (Produce + HydrationApply), so it joins the save set.
USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_NoHandler_Registered
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_NoHandler_Registered);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

// Registered NOWHERE — what the handler above actually emits, and therefore what the load tries to resolve.
USTRUCT()
struct CKTESTS_API FCk_SaveData_AutoTest_NoHandler_Orphan
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(FCk_SaveData_AutoTest_NoHandler_Orphan);

private:
    UPROPERTY()
    int32 _Value = 0;

public:
    CK_PROPERTY(_Value);
};

// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE final : public UCk_EntityScript_UE
{
    GENERATED_BODY()

public:
    UCk_AutoTest_Snapshot_NoHandlerPayloadProbe_EntityScript_UE();

public:
    auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    auto
    Get_IsSnapshotRespawnable() const -> bool override;
};

// --------------------------------------------------------------------------------------------------------------------
