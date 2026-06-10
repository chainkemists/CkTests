#pragma once

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkRenderTarget/RenderTarget/CkRenderTarget_Fragment_Data.h"

#include "CkAutoTest_NetSubject_RenderTarget.generated.h"

// --------------------------------------------------------------------------------------------------------------------

// Variant of ACk_AutoTest_NetSubject that bridges to the RenderTarget-flavoured entity-script
// (UCk_AutoTest_NetSubject_RenderTargetEntityScript_UE). The entity-script's Construct composes a
// Replicates / InstructionsOnly RenderTarget sync child on the bridged entity, on both worlds
// (symmetric setup — required by the rep handler's Apply/NotReady contract: the client handler
// returns NotReady until TryGet by sync name resolves).
//
// `_TestRenderTarget` is a transient, local-only field — NOT replicated. Each world's
// entity-script independently populates its own world's actor. Instruction batches replicate via
// the FCk_RepData_RenderTarget container on the bridged entity.

UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_RenderTarget_UE : public ACk_AutoTest_NetSubject
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_RenderTarget_UE();

public:
    UPROPERTY(Transient, BlueprintReadOnly, Category = "Ck|AutoTest")
    FCk_Handle_RenderTarget _TestRenderTarget;
};

// --------------------------------------------------------------------------------------------------------------------

// Client-authoring variant — bridges to the ClientAuth entity-script (_ClientAuthoring=Allowed).
UCLASS()
class CKTESTS_API ACk_AutoTest_NetSubject_RenderTargetClientAuth_UE : public ACk_AutoTest_NetSubject_RenderTarget_UE
{
    GENERATED_BODY()

public:
    ACk_AutoTest_NetSubject_RenderTargetClientAuth_UE();
};

// --------------------------------------------------------------------------------------------------------------------
