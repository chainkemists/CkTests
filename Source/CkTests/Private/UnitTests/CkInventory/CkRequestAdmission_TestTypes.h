#pragma once

#include "CkEcs/Request/CkRequest_Completion.h"

#include "CkInventory/Inventory/CkInventory_Fragment_Data.h"

#include "CkRequestAdmission_TestTypes.generated.h"

// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class UCk_RequestAdmissionTest_Listener_UE : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void OnRemoveCompleted(
        FCk_Handle_Inventory InInventory,
        FCk_Handle_Item InItem,
        ECk_Inventory_OperationResult_Remove InResult)
    {
        ++_RemoveCompletionCount;
        _LastRemoveResult = InResult;
    }

    UFUNCTION()
    void OnRequestCompleted(FCk_Handle InOwner, ECk_Request_OperationResult InResult)
    {
        ++_RequestCompletionCount;
        _LastRequestResult = InResult;
    }

public:
    int32 _RemoveCompletionCount = 0;
    int32 _RequestCompletionCount = 0;
    ECk_Inventory_OperationResult_Remove _LastRemoveResult = ECk_Inventory_OperationResult_Remove::Success;
    ECk_Request_OperationResult _LastRequestResult = ECk_Request_OperationResult::Succeeded;
};

// --------------------------------------------------------------------------------------------------------------------
