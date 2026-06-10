#pragma once

#include "CoreMinimal.h"

#include "CkEcsExt/EntityScript/CkEntityScript_WithActor.h"

#include "CkRenderTarget/RenderTarget/CkRenderTarget_Fragment_Data.h"

#include "CkAutoTest_NetSubject_RenderTargetEntityScript.generated.h"

// --------------------------------------------------------------------------------------------------------------------
//
// Entity-script for the RenderTarget net subject. Construct composes a Replicates /
// InstructionsOnly RenderTarget sync child (managed 64x64, sync name
// "RenderTarget.AutoTest.Net") on the bridged entity. Runs on both server and client via the
// entity-script lifecycle's replication path — the symmetric composition the instruction-channel
// rep handler requires.
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_RenderTargetEntityScript_UE : public UCk_EntityScript_WithActor_UE
{
    GENERATED_BODY()

public:
    virtual auto
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams) -> ECk_EntityScript_ConstructionFlow override;

protected:
    // Overridable so the client-authoring variant reuses the same Construct body.
    virtual auto Get_ClientAuthoring() const -> ECk_RenderTarget_ClientAuthoring
    { return ECk_RenderTarget_ClientAuthoring::Disallowed; }
};

// --------------------------------------------------------------------------------------------------------------------

// Client-authoring variant — clients may draw (predicted + relay-pushed) and upload pixels.
UCLASS(BlueprintType)
class CKTESTS_API UCk_AutoTest_NetSubject_RenderTargetClientAuthEntityScript_UE : public UCk_AutoTest_NetSubject_RenderTargetEntityScript_UE
{
    GENERATED_BODY()

protected:
    virtual auto Get_ClientAuthoring() const -> ECk_RenderTarget_ClientAuthoring override
    { return ECk_RenderTarget_ClientAuthoring::Allowed; }
};

// --------------------------------------------------------------------------------------------------------------------
