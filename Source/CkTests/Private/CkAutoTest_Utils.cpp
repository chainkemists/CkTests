#include "CkAutoTest_Utils.h"

void
    UCk_Utils_AutoTest_UE::
    Set_Result(
        FCk_Handle& InHandle,
        ECk_AutoTest_Status InStatus,
        const FString& InFailureMessage,
        int32 InAssertionsRun,
        int32 InAssertionsFailed)
{
    if (ck::Is_NOT_Valid(InHandle))
    { return; }

    auto& Result = InHandle.AddOrGet<FCk_AutoTest_Result>();
    Result.Status = InStatus;
    Result.FailureMessage = InFailureMessage;
    Result.AssertionsRun = InAssertionsRun;
    Result.AssertionsFailed = InAssertionsFailed;
}

bool
    UCk_Utils_AutoTest_UE::
    Has_Result(
        const FCk_Handle& InHandle)
{
    if (ck::Is_NOT_Valid(InHandle))
    { return false; }

    return InHandle.Has<FCk_AutoTest_Result>();
}

FCk_AutoTest_Result
    UCk_Utils_AutoTest_UE::
    Get_Result(
        const FCk_Handle& InHandle)
{
    if (ck::Is_NOT_Valid(InHandle) || NOT InHandle.Has<FCk_AutoTest_Result>())
    { return {}; }

    return InHandle.Get<FCk_AutoTest_Result>();
}
