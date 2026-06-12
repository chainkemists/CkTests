#include "CkTests/Net/CkAutoTest_NetSubject_RenderTargetEntityScript.h"

#include "CkTests/Net/CkAutoTest_NetSubject_RenderTarget.h"

#include "CkEcs/OwningActor/CkOwningActor_Utils.h"

#include "CkRenderTarget/RenderTarget/CkRenderTarget_Utils.h"

#include <NativeGameplayTags.h>

// --------------------------------------------------------------------------------------------------------------------

// Test-only child of the C++-registered "RenderTarget" category root.
UE_DEFINE_GAMEPLAY_TAG_STATIC(TAG_RenderTarget_AutoTest_Net, TEXT("RenderTarget.AutoTest.Net"));

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_RenderTargetEntityScript_UE::
    Get_IsSnapshotRespawnable() const
    -> bool
{
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCk_AutoTest_NetSubject_RenderTargetEntityScript_UE::
    Construct(
        FCk_Handle& InHandle,
        const FInstancedStruct& InSpawnParams)
    -> ECk_EntityScript_ConstructionFlow
{
    // Super::Construct sets up the WithActor bridge (OwningActor + Transform + Label) and must
    // run before we add the RenderTarget — the instruction container needs an OwningActor in the
    // chain to bind to a replicated outer Actor.
    const auto Flow = Super::Construct(InHandle, InSpawnParams);

    auto Params = FCk_Fragment_RenderTarget_ParamsData{TAG_RenderTarget_AutoTest_Net};
    Params.Set_Size(FIntPoint{64, 64});
    Params.Set_SyncMode(ECk_RenderTarget_SyncMode::InstructionsOnly);
    Params.Set_Replication(ECk_Replication::Replicates);
    Params.Set_ClientAuthoring(Get_ClientAuthoring());

    auto RenderTarget = UCk_Utils_RenderTarget_UE::Add(InHandle, Params);

    if (auto* Subject = Cast<ACk_AutoTest_NetSubject_RenderTarget_UE>(
            UCk_Utils_OwningActor_UE::Get_EntityOwningActor(InHandle)))
    {
        Subject->_TestRenderTarget = RenderTarget;
    }

    return Flow;
}

// --------------------------------------------------------------------------------------------------------------------
