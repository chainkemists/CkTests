#pragma once

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Handle/CkHandle.h"

#include "CkTest_RebuiltListener.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Support type for the CkNavigation NavSurface rebuild-signal tests. Test-only - never used at runtime.
//
// It exists because FCk_Delegate_NavSurface_OnSurfaceRebuilt is a DYNAMIC delegate, and a dynamic
// delegate binds only to a UFUNCTION on a UObject.
//
// It records every box it was handed, in order, rather than a count and a last value: the contract is
// one broadcast per publish carrying THAT publish's region, and only the whole sequence can show that a
// pair of publishes was neither collapsed nor reordered.
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class UCk_Test_NavSurfaceRebuiltListener_UE : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void OnSurfaceRebuilt(FCk_Handle InWorldEntity, FBox InChangedBounds)
    {
        _ObservedBounds.Emplace(InChangedBounds);
    }

public:
    TArray<FBox> _ObservedBounds;
};

// --------------------------------------------------------------------------------------------------------------------
