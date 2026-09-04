#pragma once

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Request/CkRequest_Completion.h"

#include "CkTest_LinkTraversalListener.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Support type for the CkNavigation link-traversal handshake tests. Test-only - never used at runtime.
//
// It exists because the two traversal signals carry DYNAMIC delegates, and a dynamic delegate binds
// only to a UFUNCTION on a UObject.
//
// It records every payload it was handed, in order, rather than a count and a last value: the contract
// is one broadcast per crossing, and only the whole sequence shows that a repeated Begin fired nothing
// and that an end reported the right outcome for the right correlator.
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class UCk_Test_NavSurfaceLinkTraversalListener_UE : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void OnLinkTraversalBegun(FCk_Handle InTraverser, int32 InLinkId, int32 InCorrelatorId)
    {
        _BegunLinkIds.Emplace(InLinkId);
        _BegunCorrelatorIds.Emplace(InCorrelatorId);
    }

    UFUNCTION()
    void OnLinkTraversalCompleted(
        FCk_Handle InTraverser,
        int32 InLinkId,
        int32 InCorrelatorId,
        ECk_Request_OperationResult InResult)
    {
        _CompletedLinkIds.Emplace(InLinkId);
        _CompletedCorrelatorIds.Emplace(InCorrelatorId);
        _CompletedResults.Emplace(InResult);
    }

public:
    TArray<int32> _BegunLinkIds;
    TArray<int32> _BegunCorrelatorIds;
    TArray<int32> _CompletedLinkIds;
    TArray<int32> _CompletedCorrelatorIds;
    TArray<ECk_Request_OperationResult> _CompletedResults;
};

// --------------------------------------------------------------------------------------------------------------------
