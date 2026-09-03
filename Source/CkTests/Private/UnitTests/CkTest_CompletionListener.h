#pragma once

#include "CkCore/Macros/CkMacros.h"

#include "CkEcs/Handle/CkHandle.h"
#include "CkEcs/Request/CkRequest_Completion.h"

#include "CkTest_CompletionListener.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Support type for any test that observes a deferred request's completion. Test-only — never used at
// runtime.
//
// It exists because FCk_Delegate_Request_OnCompleted is a DYNAMIC delegate, and a dynamic delegate
// binds only to a UFUNCTION on a UObject. Counting fires rather than setting a flag is deliberate:
// the request-completion contract promises EXACTLY one fire, and a count is the only way to catch a
// second.
//
// Feature-neutral on purpose. The completion contract belongs to the framework rather than to any one
// feature, so a listener for it carries no feature's payload types — a per-feature listener would
// make every borrower depend on the module it happened to be written for.
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class UCk_Test_CompletionListener_UE : public UObject
{
    GENERATED_BODY()

public:
    UFUNCTION()
    void OnRequestCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        ++_TimesRequestCompleted;
        _LastRequestResult = InResult;
    }

public:
    int32 _TimesRequestCompleted = 0;
    ECk_Request_OperationResult _LastRequestResult = ECk_Request_OperationResult::Failed;
};

// --------------------------------------------------------------------------------------------------------------------
