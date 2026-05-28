#include "CkGauntletAsBridgeController.h"
#include "CkGauntletAsTest_Base.h"

#include "Engine/LocalPlayer.h"
#include "Engine/World.h"
#include "EnhancedInputSubsystems.h"
#include "GameFramework/PlayerController.h"
#include "HAL/PlatformMisc.h"
#include "HAL/PlatformTime.h"
#include "InputAction.h"
#include "InputMappingContext.h"
#include "Logging/LogMacros.h"
#include "Misc/CommandLine.h"
#include "Misc/OutputDevice.h"
#include "Misc/Parse.h"
#include "UObject/Class.h"
#include "UObject/UObjectGlobals.h"
#include "UObject/UObjectIterator.h"

#include <atomic>

DEFINE_LOG_CATEGORY_STATIC(LogCkGauntletAs, Log, All);

// --------------------------------------------------------------------------------------------------------------------
// FCkGauntletAsLogSink — single shared FOutputDevice owned by the bridge.
//
// AS tests register substrings via Request_WatchLogSubstring; the sink scans
// every log line and flips the matching entry's atomic bool on first hit.
// Substring set is grown under a critical section (rare — registration is
// usually a once-at-init thing), but match-checking takes only an atomic read
// since each entry's bool is independent.
// --------------------------------------------------------------------------------------------------------------------

class FCkGauntletAsLogSink : public FOutputDevice
{
public:
    void RegisterSubstring(const FString& InSubstring)
    {
        FScopeLock Lock(&_Mutex);
        for (const auto& Existing : _Entries)
        {
            if (Existing->Pattern == InSubstring)
            { return; }
        }
        auto NewEntry = MakeShared<FEntry>();
        NewEntry->Pattern = InSubstring;
        _Entries.Add(NewEntry);
    }

    bool HasObserved(const FString& InSubstring) const
    {
        FScopeLock Lock(&_Mutex);
        for (const auto& Entry : _Entries)
        {
            if (Entry->Pattern == InSubstring)
            { return Entry->Observed.load(std::memory_order_acquire); }
        }
        return false;
    }

    virtual void Serialize(const TCHAR* V, ELogVerbosity::Type Verbosity, const FName& Category) override
    {
        if (V == nullptr)
        { return; }

        // Brief: copy the shared array under the lock, scan without it. We
        // don't want to hold the lock across FCString::Strstr in case the
        // logging thread re-enters logging. Substrings are immutable once
        // registered; the entries' atomic Observed is safe to flip from any
        // thread.
        TArray<TSharedPtr<FEntry>> Snapshot;
        {
            FScopeLock Lock(&_Mutex);
            Snapshot = _Entries;
        }

        for (const auto& Entry : Snapshot)
        {
            if (Entry->Observed.load(std::memory_order_relaxed))
            { continue; }

            if (FCString::Strstr(V, *Entry->Pattern) != nullptr)
            {
                Entry->Observed.store(true, std::memory_order_release);
            }
        }
    }

private:
    struct FEntry
    {
        FString Pattern;
        std::atomic<bool> Observed{false};
    };

    mutable FCriticalSection _Mutex;
    TArray<TSharedPtr<FEntry>> _Entries;
};

// --------------------------------------------------------------------------------------------------------------------

UCk_GauntletAsBridgeController::UCk_GauntletAsBridgeController(const FObjectInitializer& ObjectInitializer)
    : Super(ObjectInitializer)
{
}

// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::OnInit()
{
    Super::OnInit();

    _StartTimeSeconds = FPlatformTime::Seconds();

    FString AsClassName;
    if (NOT FParse::Value(FCommandLine::Get(), TEXT("-asgauntlet="), AsClassName) || AsClassName.IsEmpty())
    {
        UE_LOG(LogCkGauntletAs, Error,
            TEXT("[CkGauntletAs] No -asgauntlet=<UClassName> on the command line. "
                 "The bridge controller cannot dispatch to an AS test without it. Ending with exit code 2."));
        EndTest(2);
        ForceExit(2);
        _Ended = true;
        return;
    }

    float CliWaitOverride = 0.0f;
    if (FParse::Value(FCommandLine::Get(), TEXT("-asgauntlet-waitsec="), CliWaitOverride) && CliWaitOverride >= 1.0f)
    {
        UE_LOG(LogCkGauntletAs, Display,
            TEXT("[CkGauntletAs] AS-class wait timeout overridden via CLI: %.1fs (default %.1fs)."),
            CliWaitOverride, _AsClassWaitTimeoutSeconds);
        _AsClassWaitTimeoutSeconds = CliWaitOverride;
    }

    _AsTestClassName = FName(*AsClassName);
    UE_LOG(LogCkGauntletAs, Display,
        TEXT("[CkGauntletAs] Bridge OnInit — AS test class requested: '%s' (instance construction deferred until OnTick)."),
        *AsClassName);

    // Install the log sink up front — registrations can happen before/during
    // OnAsInit, and we want them captured immediately.
    _LogSink = MakeShared<FCkGauntletAsLogSink>();
    if (GLog != nullptr)
    {
        GLog->AddOutputDevice(_LogSink.Get());
    }

    MarkHeartbeatActive(FString::Printf(TEXT("[CkGauntletAs] init for %s"), *AsClassName));
}

// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::OnTick(float TimeDelta)
{
    if (_Ended)
    { return; }

    if (_AsInstance == nullptr)
    {
        TryConstructAsInstance();
        if (_AsInstance == nullptr)
        {
            const double Elapsed = FPlatformTime::Seconds() - _StartTimeSeconds;
            if (Elapsed > _AsClassWaitTimeoutSeconds)
            {
                UE_LOG(LogCkGauntletAs, Error,
                    TEXT("[CkGauntletAs] AS test class '%s' never appeared in the UClass table after %.1fs "
                         "(limit=%.1fs). Did the AS module fail to compile? Ending with exit code 4."),
                    *_AsTestClassName.ToString(), Elapsed, _AsClassWaitTimeoutSeconds);
                EndTest(4);
                ForceExit(4);
                _Ended = true;
            }
            return;
        }
    }

    const double Elapsed = FPlatformTime::Seconds() - _AsConstructedTimeSeconds;
    if (Elapsed > _AsInstance->_TimeoutSeconds)
    {
        UE_LOG(LogCkGauntletAs, Error,
            TEXT("[CkGauntletAs] Watchdog timeout: AS test '%s' did not call Request_EndTest within %.1fs. Forcing exit 1."),
            *_AsTestClassName.ToString(), _AsInstance->_TimeoutSeconds);
        EndTest(1);
        ForceExit(1);
        _Ended = true;
        return;
    }

    if (NOT _AsInitFired)
    {
        const bool bRequirePc = _AsInstance->_RequirePlayerControllerOnInit;
        if (bRequirePc)
        {
            const APlayerController* PC = GetFirstPlayerController();
            const bool bReady = PC != nullptr && PC->GetPawn() != nullptr;
            if (NOT bReady)
            { return; }
        }

        _AsInitFired = true;
        UE_LOG(LogCkGauntletAs, Display,
            TEXT("[CkGauntletAs] Calling OnAsInit on %s"), *_AsTestClassName.ToString());
        _AsInstance->OnAsInit();

        if (_Ended)
        { return; }
    }

    _AsInstance->OnAsTick(TimeDelta);
}

// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::OnPreMapChange()
{
    Super::OnPreMapChange();
    // Intentionally no AS hook for pre-map change — AS tests don't need it
    // yet. Add a BIE on the base + forward here if a future test needs it.
}

void UCk_GauntletAsBridgeController::OnPostMapChange(UWorld* World)
{
    Super::OnPostMapChange(World);
    if (_AsInstance != nullptr && NOT _Ended)
    { _AsInstance->OnAsPostMapChange(); }
}

void UCk_GauntletAsBridgeController::OnStateChange(FName OldState, FName NewState)
{
    Super::OnStateChange(OldState, NewState);
    if (_AsInstance != nullptr && NOT _Ended)
    { _AsInstance->OnAsStateChange(OldState, NewState); }
}

// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::BeginDestroy()
{
    TeardownLogSink();
    _AsInstance = nullptr;
    Super::BeginDestroy();
}

// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::TryConstructAsInstance()
{
    if (_AsTestClassName.IsNone())
    { return; }

    UClass* FoundClass = nullptr;
    for (TObjectIterator<UClass> ClassIt; ClassIt; ++ClassIt)
    {
        UClass* Candidate = *ClassIt;
        if (Candidate == nullptr)
        { continue; }
        if (NOT Candidate->IsChildOf(UCk_GauntletAsTest_Base::StaticClass()))
        { continue; }
        // Match either "UCk_Foo" or "Ck_Foo" or "Foo" — be lenient on the
        // CLI: AS classes start with `U` like all UCLASSes but users tend to
        // pass the bare name. ClassName::FName is the prefixed form.
        const FName CandidateName = Candidate->GetFName();
        const FString CandidateStr = CandidateName.ToString();
        const FString WantedStr = _AsTestClassName.ToString();
        if (CandidateName == _AsTestClassName ||
            CandidateStr == FString::Printf(TEXT("U%s"), *WantedStr) ||
            CandidateStr.RightChop(1) == WantedStr)
        {
            FoundClass = Candidate;
            break;
        }
    }

    if (FoundClass == nullptr)
    {
        // Not yet — AS module may still be compiling. We retry every tick
        // until the watchdog (if any) fires or the class appears.
        return;
    }

    _AsInstance = NewObject<UCk_GauntletAsTest_Base>(this, FoundClass);
    if (_AsInstance == nullptr)
    {
        UE_LOG(LogCkGauntletAs, Error,
            TEXT("[CkGauntletAs] NewObject failed for class '%s'. Ending with exit code 3."),
            *_AsTestClassName.ToString());
        EndTest(3);
        ForceExit(3);
        _Ended = true;
        return;
    }

    _AsInstance->Controller = this;
    _AsConstructedTimeSeconds = FPlatformTime::Seconds();

    UE_LOG(LogCkGauntletAs, Display,
        TEXT("[CkGauntletAs] Constructed AS test instance: %s (resolved class %s)"),
        *_AsTestClassName.ToString(), *FoundClass->GetName());
}

// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::ForceExit(int32 InExitCode)
{
    // Cooperative Gauntlet::EndTest routes through RequestExitWithStatus(Force=false, N),
    // which on Windows posts WM_QUIT(N). In `-game -nullrhi -unattended` there is no
    // message pump consuming WM_QUIT, so the code is dropped and the process exits 0
    // via main-loop drain. Force=true here translates to TerminateProcess(N), which
    // propagates the code reliably. Lost: ~3s of cooperative cleanup (Pak/XGE/LogExit
    // bookkeeping). Sentry telemetry has already flushed by the time a failure path
    // reaches this point, so the practical cost is minor for headless CI runs.
    //
    // We tried a delayed FTSTicker first (2s) so cooperative cleanup could win when
    // it would have produced the right code — but FTSTicker stops ticking the moment
    // the engine enters its exit drain, so the ticker never fires. Direct call it is.
    const uint8 ClampedCode = static_cast<uint8>(FMath::Clamp(InExitCode, 0, 255));

    UE_LOG(LogCkGauntletAs, Warning,
        TEXT("[CkGauntletAs] Force-exiting with code %d (cooperative exit drops the code in -game -nullrhi)."),
        InExitCode);

    if (GLog != nullptr)
    { GLog->Flush(); }

    FPlatformMisc::RequestExitWithStatus(/*Force=*/true, ClampedCode);
}

// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::TeardownLogSink()
{
    if (_LogSink.IsValid())
    {
        if (GLog != nullptr)
        {
            GLog->RemoveOutputDevice(_LogSink.Get());
        }
        _LogSink.Reset();
    }
}

// --------------------------------------------------------------------------------------------------------------------
// AS-callable wrappers
// --------------------------------------------------------------------------------------------------------------------

void UCk_GauntletAsBridgeController::Request_EndTest(int32 ExitCode)
{
    if (_Ended)
    { return; }
    _Ended = true;
    UE_LOG(LogCkGauntletAs, Display,
        TEXT("[CkGauntletAs] Request_EndTest(%d) from AS test %s"),
        ExitCode, *_AsTestClassName.ToString());
    EndTest(ExitCode);
    if (ExitCode != 0)
    { ForceExit(ExitCode); }
}

void UCk_GauntletAsBridgeController::Request_MarkHeartbeat(const FString& StatusMessage)
{
    MarkHeartbeatActive(StatusMessage);
}

void UCk_GauntletAsBridgeController::Request_ExecConsoleCommand(const FString& Command)
{
    APlayerController* PC = GetFirstPlayerController();
    if (PC == nullptr)
    {
        UE_LOG(LogCkGauntletAs, Warning,
            TEXT("[CkGauntletAs] Request_ExecConsoleCommand('%s') — no PlayerController; ignoring."),
            *Command);
        return;
    }
    PC->ConsoleCommand(Command, /*bWriteToLog=*/true);
}

APlayerController* UCk_GauntletAsBridgeController::Get_FirstPlayerController() const
{
    return GetFirstPlayerController();
}

FString UCk_GauntletAsBridgeController::Get_CurrentMap() const
{
    return GetCurrentMap();
}

FName UCk_GauntletAsBridgeController::Get_CurrentState() const
{
    return GetCurrentState();
}

double UCk_GauntletAsBridgeController::Get_TimeInCurrentState() const
{
    return GetTimeInCurrentState();
}

double UCk_GauntletAsBridgeController::Get_ElapsedTimeSeconds() const
{
    return FPlatformTime::Seconds() - _StartTimeSeconds;
}

int32 UCk_GauntletAsBridgeController::Get_BoundImcCount() const
{
    const APlayerController* PC = GetFirstPlayerController();
    if (PC == nullptr)
    { return 0; }

    const ULocalPlayer* LocalPlayer = PC->GetLocalPlayer();
    if (LocalPlayer == nullptr)
    { return 0; }

    UEnhancedInputLocalPlayerSubsystem* Subsystem =
        LocalPlayer->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>();
    if (Subsystem == nullptr)
    { return 0; }

    // UEnhancedPlayerInput::GetAppliedInputContextData is protected. Probe by
    // iterating every loaded UInputMappingContext and asking the subsystem if
    // it's applied. Cheaper than the alternatives (friend, engine patch) and
    // accurate enough for a smoke test — the IMC set is small.
    int32 Count = 0;
    for (TObjectIterator<UInputMappingContext> It; It; ++It)
    {
        const UInputMappingContext* Imc = *It;
        if (Imc == nullptr)
        { continue; }
        if (Subsystem->HasMappingContext(Imc))
        { ++Count; }
    }
    return Count;
}

void UCk_GauntletAsBridgeController::Request_InjectInputForAction(UInputAction* Action, FVector Value)
{
    if (Action == nullptr)
    {
        UE_LOG(LogCkGauntletAs, Warning,
            TEXT("[CkGauntletAs] Request_InjectInputForAction — Action is null; ignoring."));
        return;
    }

    APlayerController* PC = GetFirstPlayerController();
    if (PC == nullptr)
    {
        UE_LOG(LogCkGauntletAs, Warning,
            TEXT("[CkGauntletAs] Request_InjectInputForAction('%s') — no PlayerController; ignoring."),
            *Action->GetName());
        return;
    }

    const ULocalPlayer* LocalPlayer = PC->GetLocalPlayer();
    UEnhancedInputLocalPlayerSubsystem* Subsystem =
        LocalPlayer != nullptr ? LocalPlayer->GetSubsystem<UEnhancedInputLocalPlayerSubsystem>() : nullptr;
    if (Subsystem == nullptr)
    {
        UE_LOG(LogCkGauntletAs, Warning,
            TEXT("[CkGauntletAs] Request_InjectInputForAction('%s') — no EnhancedInputLocalPlayerSubsystem; ignoring."),
            *Action->GetName());
        return;
    }

    Subsystem->InjectInputVectorForAction(Action, Value, /*Modifiers=*/{}, /*Triggers=*/{});
}

void UCk_GauntletAsBridgeController::Request_WatchLogSubstring(const FString& Substring)
{
    if (NOT _LogSink.IsValid())
    { return; }
    _LogSink->RegisterSubstring(Substring);
}

bool UCk_GauntletAsBridgeController::HasObservedLogSubstring(const FString& Substring) const
{
    if (NOT _LogSink.IsValid())
    { return false; }
    return _LogSink->HasObserved(Substring);
}
