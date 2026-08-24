#include "CkAutoTest_Utils.h"

#include "CkGoap/Planner/CkGoap_Planner_Fragment.h"

#include <HAL/IConsoleManager.h>
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

namespace ck::auto_test::cvar_scope
{
    struct FCapture
    {
        FString Value;
        EConsoleVariableFlags Priority = ECVF_SetByConstructor;
    };

    static auto Get_Captures() -> TMap<FName, FCapture>&
    {
        static TMap<FName, FCapture> Captures;
        return Captures;
    }

    static auto DoCapture(FName InName, IConsoleVariable* InCVar) -> void
    {
        auto& Captures = Get_Captures();

        // First writer wins: a second push while an override is live must not record the
        // overridden value as the "prior" — that is how a restore silently becomes a no-op.
        if (Captures.Contains(InName))
        { return; }

        auto& Capture = Captures.Add(InName);
        Capture.Value = InCVar->GetString();
        Capture.Priority = static_cast<EConsoleVariableFlags>(InCVar->GetFlags() & ECVF_SetByMask);
    }
}

bool
    UCk_Utils_AutoTest_UE::
    Get_CVarExists(
        FName InName)
{
    return IConsoleManager::Get().FindConsoleVariable(*InName.ToString()) != nullptr;
}

void
    UCk_Utils_AutoTest_UE::
    Request_PushCVarOverride(
        FName InName,
        const FString& InValue)
{
    auto* CVar = IConsoleManager::Get().FindConsoleVariable(*InName.ToString());

    if (CVar == nullptr)
    { return; }

    ck::auto_test::cvar_scope::DoCapture(InName, CVar);

    CVar->Set(*InValue, ECVF_SetByConsole);
}

void
    UCk_Utils_AutoTest_UE::
    Request_PushCVarSnapshot(
        FName InName)
{
    auto* CVar = IConsoleManager::Get().FindConsoleVariable(*InName.ToString());

    if (CVar == nullptr)
    { return; }

    ck::auto_test::cvar_scope::DoCapture(InName, CVar);
}

void
    UCk_Utils_AutoTest_UE::
    Request_PopCVarOverride(
        FName InName)
{
    auto& Captures = ck::auto_test::cvar_scope::Get_Captures();
    const auto* Capture = Captures.Find(InName);

    if (Capture == nullptr)
    { return; }

    auto* CVar = IConsoleManager::Get().FindConsoleVariable(*InName.ToString());

    if (CVar != nullptr)
    {
        // Set at the priority the variable currently holds, otherwise a write "down" the priority
        // ladder is rejected outright; then rewrite the SetBy bits back to what they were, so the
        // variable ends up indistinguishable from never having been touched. Same two-step the
        // pixel-art renderer's CVar leases use.
        const auto CurrentPriority = static_cast<EConsoleVariableFlags>(CVar->GetFlags() & ECVF_SetByMask);

        CVar->Set(*Capture->Value, CurrentPriority);
        CVar->SetFlags(static_cast<EConsoleVariableFlags>(
            (CVar->GetFlags() & ~ECVF_SetByMask) | Capture->Priority));
    }

    Captures.Remove(InName);
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
