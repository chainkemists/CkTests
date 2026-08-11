#include "CkAutoTest_Utils.h"

#include "CkGoap/Planner/CkGoap_Planner_Fragment.h"

#include <Misc/ScopeExit.h>

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

bool
    UCk_Utils_AutoTest_UE::
    TryGet_GoapLastSearchDebugWithoutWorldStateSource_ForTesting(
        const FCk_Handle_Goap_Planner& InPlanner,
        TArray<FCk_Goap_SearchDebugRow>& OutRows)
{
    OutRows.Reset();

    const auto IsValidPlanner = ck::IsValid(InPlanner);
    if (NOT IsValidPlanner || NOT InPlanner.Has<ck::FFragment_Goap_Planner_WorldStateSource>())
    { return false; }

    auto MutablePlanner = InPlanner;
    const auto SavedWorldStateSource = MutablePlanner.Get<ck::FFragment_Goap_Planner_WorldStateSource>();
    const auto Removed = MutablePlanner.Try_Remove<ck::FFragment_Goap_Planner_WorldStateSource>();
    if (NOT Removed) { return false; }

    ON_SCOPE_EXIT
    {
        if (ck::IsValid(MutablePlanner)
            && NOT MutablePlanner.Has<ck::FFragment_Goap_Planner_WorldStateSource>())
        {
            MutablePlanner.Add<ck::FFragment_Goap_Planner_WorldStateSource>(SavedWorldStateSource);
        }
    };

    return UCk_Utils_Goap_Planner_UE::TryGet_LastSearchDebug(InPlanner, OutRows);
}
