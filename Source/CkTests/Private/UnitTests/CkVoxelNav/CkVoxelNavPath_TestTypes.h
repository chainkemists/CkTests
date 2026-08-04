#pragma once

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Request/CkRequest_Completion.h"

#include "CkVoxelNav/Path/CkVoxelNavPath_Fragment_Data.h"

#include "CkVoxelNavPath_TestTypes.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Support type for the Ck.VoxelNav.Path tests. Test-only — never used at runtime.
//
// It exists because every channel a path request reports through is a DYNAMIC delegate, and a dynamic
// delegate can only bind to a UFUNCTION on a UObject. Counting fires rather than setting a flag is
// deliberate: the request-completion contract promises EXACTLY one fire, and a count is the only way to
// catch a second.

UCLASS()
class UCk_VoxelNavPathTest_Listener_UE : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void OnFindPathCompleted(FCk_Handle InPath, ECk_Request_OperationResult InResult)
    {
        ++_TimesRequestCompleted;
        _LastRequestResult = InResult;
    }

    UFUNCTION()
    void OnPathReady(FCk_Handle_VoxelNavPath InPath)
    {
        ++_TimesPathReadyFired;
    }

    UFUNCTION()
    void OnPathFailed(FCk_Handle_VoxelNavPath InPath, ECk_VoxelNav_PathSearchOutcome InOutcome)
    {
        ++_TimesPathFailedFired;
        _LastFailureOutcome = InOutcome;
    }

public:
    int32 _TimesRequestCompleted = 0;
    int32 _TimesPathReadyFired = 0;
    int32 _TimesPathFailedFired = 0;
    ECk_Request_OperationResult _LastRequestResult = ECk_Request_OperationResult::Succeeded;
    ECk_VoxelNav_PathSearchOutcome _LastFailureOutcome = ECk_VoxelNav_PathSearchOutcome::Succeeded;
};

// --------------------------------------------------------------------------------------------------------------------
