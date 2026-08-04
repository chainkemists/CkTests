#pragma once

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Request/CkRequest_Completion.h"

#include "CkVoxelNav/Volume/CkVoxelNavVolume_Fragment_Data.h"

#include "CkVoxelNavBake_TestTypes.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Support type for the Ck.VoxelNav.Bake PIE test. Test-only — never used at runtime.
//
// It exists because both channels a bake reports through are DYNAMIC delegates, and a dynamic delegate can
// only bind to a UFUNCTION on a UObject. Counting fires rather than setting a flag is deliberate: the
// request-completion contract promises EXACTLY one fire, and a count is the only way to catch a second.

UCLASS()
class UCk_VoxelNavBakeTest_Listener_UE : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void OnBuildRequestCompleted(FCk_Handle InVolume, ECk_Request_OperationResult InResult)
    {
        ++_TimesRequestCompleted;
        _LastRequestResult = InResult;
    }

    UFUNCTION()
    void OnBuildComplete(FCk_Handle_VoxelNavVolume InVolume, ECk_SucceededFailed InResult,
        FCk_VoxelNav_BuildStats InStats)
    {
        ++_TimesBuildCompleteFired;
        _LastSignalResult = InResult;
        _LastStats = InStats;
    }

public:
    int32 _TimesRequestCompleted = 0;
    int32 _TimesBuildCompleteFired = 0;
    ECk_Request_OperationResult _LastRequestResult = ECk_Request_OperationResult::Failed;
    ECk_SucceededFailed _LastSignalResult = ECk_SucceededFailed::Failed;
    FCk_VoxelNav_BuildStats _LastStats;
};

// --------------------------------------------------------------------------------------------------------------------
