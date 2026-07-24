#pragma once

#include "CoreMinimal.h"

#include "Templates/Function.h"

// --------------------------------------------------------------------------------------------------------------------
// The FAutomationExecCmd-mirror (Engine/Source/Developer/AutomationController/Private/AutomationCommandline.cpp) around
// IAutomationControllerManager, adapted for the live test bridge:
//
//   * ASYNCHRONOUS — a single RunController drives one batch, but its state machine is pumped by the bridge
//     subsystem's ticker (Tick(DeltaTime) below), NOT by an owned FTSTicker. This is deliberate: the automation
//     framework runs on the editor game thread, so a blocking loop would starve the very controller it is waiting
//     on (why the warm server is a -CkTestBridgeServe editor, not a Sleep-loop commandlet — see the subsystem).
//   * EXACT test set — SetEnabledTests(requested full-dotted-paths) instead of the commandline's substring filters;
//     requested-minus-enabled becomes NotFound.
//   * Watchdogs — a per-test stall watchdog (no state change for PerTestStallSeconds) and a wall-clock cap; either
//     StopTests and marks the still-in-flight requested tests Failed.
//   * Progress — testStarted / testCompleted are surfaced via callbacks the processor turns into Progress/*.jsonl.
// --------------------------------------------------------------------------------------------------------------------

enum class ECk_TestBridge_TestResult : uint8
{
    Success,
    Failed,
    Skipped,
    NotRun
};

CKTESTSBRIDGE_API auto
ToString(
    ECk_TestBridge_TestResult InResult) -> const TCHAR*;

// --------------------------------------------------------------------------------------------------------------------

// One Error/Warning line harvested from a test's results (Info entries are dropped; the list is capped).
struct FCk_TestBridge_LogEntry
{
    FString Type;      // "Error" | "Warning"
    FString Message;
};

// --------------------------------------------------------------------------------------------------------------------

struct FCk_TestBridge_PerTest
{
    FString                          Path;
    ECk_TestBridge_TestResult        Result = ECk_TestBridge_TestResult::NotRun;
    double                           DurationSec = 0.0;
    TArray<FCk_TestBridge_LogEntry>  Entries;
};

// --------------------------------------------------------------------------------------------------------------------

struct FCk_TestBridge_RunRequest
{
    TArray<FString> Tests;
    float           PerTestStallSeconds  = 300.0f;
    float           WallClockCapSeconds  = 3600.0f;
};

// --------------------------------------------------------------------------------------------------------------------

struct FCk_TestBridge_RunResult
{
    TArray<FCk_TestBridge_PerTest> PerTest;
    TArray<FString>                NotFound;
};

// --------------------------------------------------------------------------------------------------------------------

// Progress hooks the processor sets so it can stream Progress/<id>.jsonl. Never null-checked internally — the
// processor always supplies them; a default RunController that is never Begun holds empty TFunctions.
struct FCk_TestBridge_RunCallbacks
{
    TFunction<void(int32 InTestCount)>                                                              OnAccepted;
    TFunction<void(const FString& InPath)>                                                          OnTestStarted;
    TFunction<void(const FString& InPath, ECk_TestBridge_TestResult InResult, double InDurationSec)> OnTestCompleted;
};

// --------------------------------------------------------------------------------------------------------------------

class CKTESTSBRIDGE_API FCk_TestBridge_RunController
{
public:
    // Detaches the OnTestsRefreshed delegate (via Reset) so a mid-run editor shutdown that destroys the owning
    // processor cannot leave the controller holding a raw pointer to freed memory.
    ~FCk_TestBridge_RunController();

    // Load + Init the AutomationController, subscribe to refresh/complete, request workers, and arm the run. The
    // batch does not actually start until a subsequent Tick advances the state machine to RunTests.
    auto
    Begin(
        const FCk_TestBridge_RunRequest& InRequest,
        const FCk_TestBridge_RunCallbacks& InCallbacks) -> void;

    // Pump one step of the state machine. Cheap no-op once complete. Call from the driving ticker every tick.
    auto
    Tick(
        float InDeltaTime) -> void;

    // True between Begin and completion (natural finish, forced stop, or a no-tests-found short-circuit).
    auto Is_Running() const -> bool { return _State != EState::Idle && _State != EState::Complete; }

    // True once results are harvested and safe to read via Get_Result.
    auto Is_Complete() const -> bool { return _State == EState::Complete; }

    auto Get_Result() const -> const FCk_TestBridge_RunResult& { return _Result; }

    // Detach delegates and clear controller reports; safe to call whether or not Begin ran. Returns the controller
    // to the pre-Begin state so the same instance can serve the next request.
    auto
    Reset() -> void;

private:
    enum class EState : uint8
    {
        Idle,           // Never begun / after Reset
        Initializing,   // Waiting for the controller to report ready
        FindWorkers,    // Delay before requesting workers
        RequestTests,   // Waiting for OnTestsRefreshed to deliver the test list
        Running,        // Tests are executing; polling reports + watchdogs
        Complete        // Results harvested
    };

private:
    // Bound to IAutomationControllerManager::OnTestsRefreshed — enables the requested tests and kicks the run.
    auto
    OnTestsRefreshed() -> void;

    // Snapshot report states, emit testStarted/testCompleted deltas, run the stall + wall-clock watchdogs.
    auto
    MonitorTests(
        float InDeltaTime) -> void;

    // Read every enabled report into _Result. In-flight tests become NotRun, or Failed when InForcedStop.
    auto
    Do_HarvestResults(
        bool InForcedStop) -> void;

    auto
    Do_TransitionToComplete(
        bool InForcedStop) -> void;

private:
    TSharedPtr<class IAutomationControllerManager> _Controller;
    FDelegateHandle                                _TestsRefreshedHandle;
    FDelegateHandle                                _TestsCompleteHandle;

    EState _State = EState::Idle;

    FCk_TestBridge_RunRequest   _Request;
    FCk_TestBridge_RunCallbacks _Callbacks;
    FCk_TestBridge_RunResult    _Result;

    // Timers (seconds). Start/last-progress are FPlatformTime::Seconds() stamps; the two countdowns mirror
    // FAutomationExecCmd's DelayTimer / FindWorkersTimeout.
    float  _FindWorkersDelay    = 0.0f;
    float  _FindWorkersTimeout  = 0.0f;
    int32  _FindWorkerAttempts  = 0;
    double _RunStartSeconds     = 0.0;
    double _LastProgressSeconds = 0.0;
    // Begin() stamp. Bounds the Initializing wait on IAutomationControllerManager::IsReadyForTests(),
    // which in the editor gates on an interactive frame rate (FWaitForInteractiveFrameRate) and can
    // therefore never pass while the editor is busy / low-FPS — without this bound the run would hang.
    double _BeginSeconds        = 0.0;

    // Set once GetTestState() reports Running, so the first MonitorTests pass (which may run the same tick RunTests
    // was called, before the controller has flipped to Running) cannot declare premature completion.
    bool _HasObservedRunning = false;

    // Progress bookkeeping so each testStarted / testCompleted fires exactly once.
    TSet<FString> _Started;
    TSet<FString> _Completed;
};

// --------------------------------------------------------------------------------------------------------------------
