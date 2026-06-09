#include "CkTests/Net/CkAutoTest_NetSubject_Utils.h"

#include "CkTests/Net/CkAutoTest_NetSubject.h"

#include "CkAttribute/FloatAttribute/CkFloatAttribute_Utils.h"
#include "CkEcs/EntityScript/CkEntityScript_Fragment_Data.h"

// --------------------------------------------------------------------------------------------------------------------

ACk_AutoTest_NetSubject*
    UCk_Utils_AutoTest_NetSubject_UE::
    Find_NetSubject(
        const UWorld* InWorld)
{
    // Cast away const — the underlying static helper takes a non-const UWorld* because actor
    // iteration in TActorIterator is a non-const operation. The BPFL signature is `const UWorld*`
    // because Blueprint/AS callers don't have a non-const world from BlueprintPure paths.
    return ACk_AutoTest_NetSubject::Find(const_cast<UWorld*>(InWorld));
}

// --------------------------------------------------------------------------------------------------------------------

void
    UCk_AutoTest_BodyCapturer_UE::
    OnBodyConstructed(
        FCk_Handle_EntityScript InEntityScriptHandle)
{
    // FCk_Handle_EntityScript is a TypeSafe handle that wraps an FCk_Handle. Promote to the
    // generic handle for storage so the latent command's polling code can read result fragments
    // via UCk_Utils_AutoTest_UE::Has_Result / Get_Result (both take generic FCk_Handle).
    _CapturedBodies.Add(InEntityScriptHandle);
}

// --------------------------------------------------------------------------------------------------------------------

void
    UCk_AutoTest_RepCompleteCapturer_UE::
    OnReplicationComplete(
        FCk_Handle InHandle)
{
    _Fired = true;

    auto AttributeHandle = UCk_Utils_FloatAttribute_UE::TryGet(InHandle, _AttributeTag);
    if (ck::Is_NOT_Valid(AttributeHandle))
    { return; }

    _AttributeWasPresentAtFire = true;
    _FinalValueAtFire = UCk_Utils_FloatAttribute_UE::Get_FinalValue(AttributeHandle);
}

// --------------------------------------------------------------------------------------------------------------------

