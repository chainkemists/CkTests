#include "CkTestBridge_RunController.h"

#include "CkTestsBridge_Log.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include "IAutomationControllerManager.h"
#include "IAutomationControllerModule.h"
#include "IAutomationReport.h"
#include "AutomationState.h"

#include <Misc/App.h>
#include <Misc/AutomationEvent.h>
#include <Modules/ModuleManager.h>
#include <HAL/PlatformTime.h>
#include <UObject/UObjectGlobals.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_bridge_runcontroller
{
    // The commandline's "Standard" filter (AutomationCommandline.cpp:99 on the 5.7 fork). BB functional-test rows
    // carry ProductFilter, which this mask includes. [VERIFY] hardcoded rather than read from FilterMaps.
    constexpr auto StandardTestFlags =
        EAutomationTestFlags::SmokeFilter |
        EAutomationTestFlags::EngineFilter |
        EAutomationTestFlags::ProductFilter |
        EAutomationTestFlags::PerfFilter;

    // A live editor already has its worker up, so the find-workers dance is near-instant; keep the delay short but
    // preserve the retry/timeout structure of FAutomationExecCmd.
    constexpr auto FindWorkersDelaySeconds   = float{1.0f};
    constexpr auto FindWorkersTimeoutSeconds = float{15.0f};
    constexpr auto MaxFindWorkerAttempts     = int32{4};

    // Bound the Initializing wait on IsReadyForTests(). In the editor that gate includes an
    // interactive-frame-rate check (FWaitForInteractiveFrameRate, AutomationControllerManager.cpp),
    // so a busy / low-FPS editor (e.g. one flooding the log with per-frame errors) never becomes
    // "ready" and the run would otherwise hang forever. On timeout we abort with a clear diagnostic
    // instead — a robustness improvement over FAutomationExecCmd, which has no bound here.
    constexpr auto ReadyForTestsTimeoutSeconds = double{90.0};

    constexpr auto MaxEntriesPerTest = int32{50};

    // ClusterIndex/PassIndex — a live single-editor run has exactly one local cluster and one pass.
    constexpr auto ClusterIndex = int32{0};
    constexpr auto PassIndex    = int32{0};

    static auto
    Map_State(
        EAutomationState InState,
        bool InForcedStop)
        -> ECk_TestBridge_TestResult
    {
        switch (InState)
        {
            case EAutomationState::Success: return ECk_TestBridge_TestResult::Success;
            case EAutomationState::Fail:    return ECk_TestBridge_TestResult::Failed;
            case EAutomationState::Skipped: return ECk_TestBridge_TestResult::Skipped;
            case EAutomationState::NotRun:
            case EAutomationState::InProcess:
            default:
                return InForcedStop ? ECk_TestBridge_TestResult::Failed : ECk_TestBridge_TestResult::NotRun;
        }
    }

    static auto
    Is_TerminalState(
        EAutomationState InState)
        -> bool
    {
        return InState == EAutomationState::Success
            || InState == EAutomationState::Fail
            || InState == EAutomationState::Skipped;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
ToString(
    ECk_TestBridge_TestResult InResult)
    -> const TCHAR*
{
    switch (InResult)
    {
        case ECk_TestBridge_TestResult::Success: return TEXT("Success");
        case ECk_TestBridge_TestResult::Failed:  return TEXT("Failed");
        case ECk_TestBridge_TestResult::Skipped: return TEXT("Skipped");
        case ECk_TestBridge_TestResult::NotRun:  return TEXT("NotRun");
        default:                                 return TEXT("NotRun");
    }
}

// --------------------------------------------------------------------------------------------------------------------

FCk_TestBridge_RunController::
    ~FCk_TestBridge_RunController()
{
    Reset();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RunController::
    Begin(
        const FCk_TestBridge_RunRequest& InRequest,
        const FCk_TestBridge_RunCallbacks& InCallbacks)
    -> void
{
    using namespace ck_test_bridge_runcontroller;

    Reset();

    _Request   = InRequest;
    _Callbacks = InCallbacks;

    auto* ControllerModule = FModuleManager::LoadModulePtr<IAutomationControllerModule>(TEXT("AutomationController"));
    const auto ModuleIsValid = ControllerModule != nullptr;
    CK_ENSURE_IF_NOT(ModuleIsValid, TEXT("[RunController] AutomationController module unavailable"))
    {}
    if (NOT ModuleIsValid)
    {
        Do_TransitionToComplete(false);
        return;
    }

    _Controller = ControllerModule->GetAutomationController();
    const auto ControllerIsValid = _Controller.IsValid();
    CK_ENSURE_IF_NOT(ControllerIsValid, TEXT("[RunController] AutomationController manager is null"))
    {}
    if (NOT ControllerIsValid)
    {
        Do_TransitionToComplete(false);
        return;
    }

    _Controller->Init();
    _Controller->SetRequestedTestFlags(StandardTestFlags);

    _TestsRefreshedHandle = _Controller->OnTestsRefreshed().AddRaw(this, &FCk_TestBridge_RunController::OnTestsRefreshed);

    _FindWorkersDelay   = FindWorkersDelaySeconds;
    _FindWorkersTimeout = FindWorkersTimeoutSeconds;
    _FindWorkerAttempts = 0;
    _BeginSeconds       = FPlatformTime::Seconds();
    _State = EState::Initializing;

    if (_Callbacks.OnAccepted)
    { _Callbacks.OnAccepted(_Request.Tests.Num()); }

    ck::tests_bridge::Display(TEXT("[RunController] armed for {} test(s)"), _Request.Tests.Num());
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RunController::
    Tick(
        float InDeltaTime)
    -> void
{
    using namespace ck_test_bridge_runcontroller;

    if (_State == EState::Idle || _State == EState::Complete)
    { return; }

    if (NOT _Controller.IsValid())
    {
        Do_TransitionToComplete(false);
        return;
    }

    // Keep the controller pumping — this is the tick FAutomationExecCmd runs off its own FTSTicker.
    _Controller->Tick();

    switch (_State)
    {
        case EState::Initializing:
        {
            if (_Controller->IsReadyForTests())
            {
                _State = EState::FindWorkers;
            }
            else if (FPlatformTime::Seconds() - _BeginSeconds >= ReadyForTestsTimeoutSeconds)
            {
                // The editor never reported ready — almost always its interactive-frame-rate gate not passing
                // because the editor is busy / low-FPS (e.g. flooding the log with per-frame errors). Abort with
                // a diagnostic and mark every requested test NotFound so the request completes and frees the bridge.
                ck::tests_bridge::Error(
                    TEXT("[RunController] editor did not become ready for tests within {}s. IsReadyForTests() gates "
                         "on an interactive editor frame rate — is the editor busy, minimized, or spamming per-frame "
                         "errors? Try serving from the (clean) AutoTests map. Aborting."),
                    ReadyForTestsTimeoutSeconds);
                _Result.NotFound = _Request.Tests;
                Do_TransitionToComplete(true);
            }
            break;
        }
        case EState::FindWorkers:
        {
            _FindWorkersDelay -= InDeltaTime;
            if (_FindWorkersDelay <= 0.0f)
            {
                _Controller->RequestAvailableWorkers(FApp::GetSessionId());
                _FindWorkersTimeout = FindWorkersTimeoutSeconds;
                ++_FindWorkerAttempts;
                _State = EState::RequestTests;
            }
            break;
        }
        case EState::RequestTests:
        {
            // OnTestsRefreshed advances us out of this state. If the workers never answer, retry a bounded number
            // of times then give up with everything marked NotFound.
            _FindWorkersTimeout -= InDeltaTime;
            if (_FindWorkersTimeout <= 0.0f)
            {
                if (_FindWorkerAttempts >= MaxFindWorkerAttempts)
                {
                    ck::tests_bridge::Error(TEXT("[RunController] no automation workers after {} attempts — giving up"), _FindWorkerAttempts);
                    _Result.NotFound = _Request.Tests;
                    Do_TransitionToComplete(false);
                }
                else
                {
                    ck::tests_bridge::Warning(TEXT("[RunController] no workers yet — retrying"));
                    _FindWorkersDelay = FindWorkersDelaySeconds;
                    _State = EState::FindWorkers;
                }
            }
            break;
        }
        case EState::Running:
        {
            MonitorTests(InDeltaTime);
            break;
        }
        default:
            break;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RunController::
    OnTestsRefreshed()
    -> void
{
    using namespace ck_test_bridge_runcontroller;

    // Mirror FAutomationExecCmd::HandleRefreshTestCallback's guard — ignore refreshes outside the wait window or
    // before a device cluster exists.
    if (_State != EState::RequestTests || NOT _Controller.IsValid() || _Controller->GetNumDeviceClusters() == 0)
    { return; }

    // Enable EXACTLY the requested full-dotted paths. [VERIFY] SetEnabledTests matches on full path and does not
    // require a prior SetFilter for the report tree to be enumerable post-refresh (5.7 fork).
    _Controller->SetEnabledTests(_Request.Tests);

    auto EnabledNames = TArray<FString>{};
    _Controller->GetEnabledTestNames(EnabledNames);

    const auto EnabledSet = TSet<FString>{EnabledNames};
    for (const auto& Requested : _Request.Tests)
    {
        if (NOT EnabledSet.Contains(Requested))
        { _Result.NotFound.Add(Requested); }
    }

    if (EnabledNames.Num() == 0)
    {
        ck::tests_bridge::Warning(TEXT("[RunController] none of the {} requested test(s) matched an available test"), _Request.Tests.Num());
        Do_TransitionToComplete(false);
        return;
    }

    // Stop re-firing while we run (the controller re-broadcasts on session-frontend refreshes).
    _Controller->OnTestsRefreshed().Remove(_TestsRefreshedHandle);
    _TestsRefreshedHandle.Reset();

    _Controller->StopTests();
    _Controller->SetEnabledTests(_Request.Tests);

    constexpr auto IsLocalSession = true;
    _Controller->RunTests(IsLocalSession);

    _RunStartSeconds     = FPlatformTime::Seconds();
    _LastProgressSeconds = _RunStartSeconds;
    _State = EState::Running;

    ck::tests_bridge::Display(
        TEXT("[RunController] running {} enabled test(s) ({} not found)"), EnabledNames.Num(), _Result.NotFound.Num());
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RunController::
    MonitorTests(
        float /*InDeltaTime*/)
    -> void
{
    using namespace ck_test_bridge_runcontroller;

    const auto Reports = _Controller->GetEnabledReports();
    const auto Now = FPlatformTime::Seconds();

    for (const auto& Report : Reports)
    {
        if (NOT Report.IsValid())
        { continue; }

        const auto Path  = Report->GetFullTestPath();
        const auto State = Report->GetState(ClusterIndex, PassIndex);

        const auto IsInProgress = State == EAutomationState::InProcess;
        const auto IsTerminal   = Is_TerminalState(State);

        if ((IsInProgress || IsTerminal) && NOT _Started.Contains(Path))
        {
            _Started.Add(Path);
            _LastProgressSeconds = Now;
            if (_Callbacks.OnTestStarted)
            { _Callbacks.OnTestStarted(Path); }
        }

        if (IsTerminal && NOT _Completed.Contains(Path))
        {
            _Completed.Add(Path);
            _LastProgressSeconds = Now;

            const auto& Results = Report->GetResults(ClusterIndex, PassIndex);
            const auto Result   = Map_State(State, false);
            if (_Callbacks.OnTestCompleted)
            { _Callbacks.OnTestCompleted(Path, Result, static_cast<double>(Results.Duration)); }
        }
    }

    // Most reliable completion signal: every enabled test has reached a terminal state. Robust to the controller
    // flipping Running->done between two 0.5s polls (which the GetTestState check below could otherwise miss).
    const auto EnabledCount = _Request.Tests.Num() - _Result.NotFound.Num();
    if (EnabledCount > 0 && _Completed.Num() >= EnabledCount)
    {
        Do_TransitionToComplete(false);
        return;
    }

    // Fallback: the controller is no longer running — but only once we have actually seen it Running, so the first
    // pass (which can land the same tick as RunTests, before the controller flips to Running) does not complete
    // with zero results.
    if (_Controller->GetTestState() == EAutomationControllerModuleState::Running)
    { _HasObservedRunning = true; }
    else if (_HasObservedRunning)
    {
        Do_TransitionToComplete(false);
        return;
    }

    // Per-test stall watchdog — no started/completed transition for the whole window.
    if (Now - _LastProgressSeconds >= static_cast<double>(_Request.PerTestStallSeconds))
    {
        ck::tests_bridge::Error(
            TEXT("[RunController] no test progress for {}s — stopping (stall watchdog)"), _Request.PerTestStallSeconds);
        _Controller->StopTests();
        Do_TransitionToComplete(true);
        return;
    }

    // Wall-clock cap.
    if (Now - _RunStartSeconds >= static_cast<double>(_Request.WallClockCapSeconds))
    {
        ck::tests_bridge::Error(
            TEXT("[RunController] wall-clock cap {}s reached — stopping"), _Request.WallClockCapSeconds);
        _Controller->StopTests();
        Do_TransitionToComplete(true);
        return;
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RunController::
    Do_HarvestResults(
        bool InForcedStop)
    -> void
{
    using namespace ck_test_bridge_runcontroller;

    if (NOT _Controller.IsValid())
    { return; }

    // Map full path -> report so per-request lookup is O(1).
    auto ReportByPath = TMap<FString, TSharedPtr<IAutomationReport>>{};
    for (const auto& Report : _Controller->GetEnabledReports())
    {
        if (Report.IsValid())
        { ReportByPath.Add(Report->GetFullTestPath(), Report); }
    }

    const auto NotFoundSet = TSet<FString>{_Result.NotFound};

    for (const auto& RequestedPath : _Request.Tests)
    {
        if (NotFoundSet.Contains(RequestedPath))
        { continue; }

        auto PerTest = FCk_TestBridge_PerTest{};
        PerTest.Path = RequestedPath;

        const auto* ReportPtr = ReportByPath.Find(RequestedPath);
        if (ReportPtr == nullptr || NOT ReportPtr->IsValid())
        {
            PerTest.Result = InForcedStop ? ECk_TestBridge_TestResult::Failed : ECk_TestBridge_TestResult::NotRun;
            _Result.PerTest.Add(MoveTemp(PerTest));
            continue;
        }

        const auto& Report  = *ReportPtr;
        const auto  State   = Report->GetState(ClusterIndex, PassIndex);
        const auto& Results = Report->GetResults(ClusterIndex, PassIndex);

        PerTest.Result      = Map_State(State, InForcedStop);
        PerTest.DurationSec = static_cast<double>(Results.Duration);

        for (const auto& Entry : Results.GetEntries())
        {
            if (PerTest.Entries.Num() >= MaxEntriesPerTest)
            { break; }

            const auto Type = Entry.Event.Type;
            if (Type != EAutomationEventType::Error && Type != EAutomationEventType::Warning)
            { continue; }

            auto LogEntry = FCk_TestBridge_LogEntry{};
            LogEntry.Type    = Type == EAutomationEventType::Error ? TEXT("Error") : TEXT("Warning");
            LogEntry.Message = Entry.Event.Message;
            PerTest.Entries.Add(MoveTemp(LogEntry));
        }

        _Result.PerTest.Add(MoveTemp(PerTest));
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RunController::
    Do_TransitionToComplete(
        bool InForcedStop)
    -> void
{
    Do_HarvestResults(InForcedStop);

    if (_Controller.IsValid())
    {
        if (_TestsRefreshedHandle.IsValid())
        {
            _Controller->OnTestsRefreshed().Remove(_TestsRefreshedHandle);
            _TestsRefreshedHandle.Reset();
        }
        _Controller->ClearAutomationReports();
    }

    _State = EState::Complete;

    CollectGarbage(RF_NoFlags);

    ck::tests_bridge::Display(
        TEXT("[RunController] complete — {} result(s), {} not found{}"),
        _Result.PerTest.Num(), _Result.NotFound.Num(), InForcedStop ? TEXT(" (forced stop)") : TEXT(""));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RunController::
    Reset()
    -> void
{
    if (_Controller.IsValid() && _TestsRefreshedHandle.IsValid())
    { _Controller->OnTestsRefreshed().Remove(_TestsRefreshedHandle); }

    _TestsRefreshedHandle.Reset();
    _TestsCompleteHandle.Reset();
    _Controller.Reset();

    _State   = EState::Idle;
    _Request = FCk_TestBridge_RunRequest{};
    _Callbacks = FCk_TestBridge_RunCallbacks{};
    _Result  = FCk_TestBridge_RunResult{};

    _FindWorkersDelay    = 0.0f;
    _FindWorkersTimeout  = 0.0f;
    _FindWorkerAttempts  = 0;
    _RunStartSeconds     = 0.0;
    _LastProgressSeconds = 0.0;
    _BeginSeconds        = 0.0;
    _HasObservedRunning  = false;

    _Started.Empty();
    _Completed.Empty();
}

// --------------------------------------------------------------------------------------------------------------------
