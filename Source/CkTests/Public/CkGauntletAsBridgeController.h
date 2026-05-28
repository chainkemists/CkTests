#pragma once

#include "CoreMinimal.h"
#include "GauntletTestController.h"

#include "CkGauntletAsBridgeController.generated.h"

class UCk_GauntletAsTest_Base;
class APlayerController;
class FCkGauntletAsLogSink;

// --------------------------------------------------------------------------------------------------------------------
//
// UCk_GauntletAsBridgeController — universal Gauntlet entry point for AS tests.
//
// Selected at the CLI as:
//   -gauntlet=Ck_GauntletAsBridgeController -asgauntlet=<ASClassName>
//
// Responsibilities:
//   1. Parse -asgauntlet=<class> from FCommandLine::Get() in OnInit.
//   2. Defer AS instance construction to first OnTick (AS module compile must
//      complete before FindObject<UClass> can find the AS-defined class).
//   3. Forward UGauntletTestController lifecycle to AS via BIE calls on
//      UCk_GauntletAsTest_Base.
//   4. Expose AS-callable UFUNCTION wrappers around the protected/static
//      base-class API: EndTest, MarkHeartbeatActive, GetFirstPlayerController,
//      GetCurrentMap, GetCurrentState, GetTimeInCurrentState.
//   5. Own a process-wide FOutputDevice log-watch sink shared across the run.
//      AS tests register substrings via Request_WatchLogSubstring(s) and
//      poll via HasObservedLogSubstring(s).
//
// Why one bridge class (not one per test) — adding a new test is a single
// .as file. No C++ recompile. No editor restart beyond the first time a new
// UClass appears in the AS module (well-documented hot-reload gotcha).
//
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTS_API UCk_GauntletAsBridgeController : public UGauntletTestController
{
    GENERATED_BODY()

public:
    UCk_GauntletAsBridgeController(const FObjectInitializer& ObjectInitializer);

protected:
    virtual void OnInit() override;
    virtual void OnTick(float TimeDelta) override;
    virtual void OnPreMapChange() override;
    virtual void OnPostMapChange(UWorld* World) override;
    virtual void OnStateChange(FName OldState, FName NewState) override;
    virtual void BeginDestroy() override;

public:
    // ----- AS-callable wrappers -----

    UFUNCTION(BlueprintCallable, Category = "Ck|Gauntlet|AS",
        meta = (DisplayName = "Request End Test"))
    void Request_EndTest(int32 ExitCode);

    UFUNCTION(BlueprintCallable, Category = "Ck|Gauntlet|AS",
        meta = (DisplayName = "Request Mark Heartbeat"))
    void Request_MarkHeartbeat(const FString& StatusMessage);

    UFUNCTION(BlueprintCallable, Category = "Ck|Gauntlet|AS",
        meta = (DisplayName = "Request Exec Console Command",
                Tooltip = "Routes through GetFirstPlayerController()->ConsoleCommand. No-op if PC is null."))
    void Request_ExecConsoleCommand(const FString& Command);

    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Ck|Gauntlet|AS")
    APlayerController* Get_FirstPlayerController() const;

    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Ck|Gauntlet|AS")
    FString Get_CurrentMap() const;

    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Ck|Gauntlet|AS")
    FName Get_CurrentState() const;

    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Ck|Gauntlet|AS")
    double Get_TimeInCurrentState() const;

    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Ck|Gauntlet|AS")
    double Get_ElapsedTimeSeconds() const;

    // ----- Log-watch API -----
    //
    // AS-side pattern:
    //   UFUNCTION(BlueprintOverride)
    //   void OnAsInit()
    //   {
    //       Controller.Request_WatchLogSubstring("[NPC SM] MoveToActor: OnGoalReached");
    //   }
    //   UFUNCTION(BlueprintOverride)
    //   void OnAsTick(float32 InDt)
    //   {
    //       if (Controller.HasObservedLogSubstring("[NPC SM] MoveToActor: OnGoalReached"))
    //       { Controller.Request_EndTest(0); }
    //   }
    //
    // The sink lives on the bridge for the bridge's lifetime; substrings can
    // be registered at any time. Matching is case-sensitive substring; the
    // sink is thread-safe (it runs on whichever thread emitted the log).

    UFUNCTION(BlueprintCallable, Category = "Ck|Gauntlet|AS",
        meta = (DisplayName = "Request Watch Log Substring"))
    void Request_WatchLogSubstring(const FString& Substring);

    UFUNCTION(BlueprintCallable, BlueprintPure, Category = "Ck|Gauntlet|AS")
    bool HasObservedLogSubstring(const FString& Substring) const;

private:
    void TryConstructAsInstance();
    void TeardownLogSink();

    // Force-exit. Gauntlet's EndTest(N) routes to
    // FPlatformMisc::RequestExitWithStatus(Force=false, N) which on Windows
    // calls PostQuitMessage(N). In `-game -nullrhi -unattended` there is no
    // message pump consuming WM_QUIT, so the exit code is silently dropped
    // and the process exits 0 via normal main-loop drain. Confirmed locally:
    // Request_EndTest(1) from an AS test → bat sees ERRORLEVEL=0. We follow
    // the soft EndTest with a TerminateProcess(N)-equivalent so the right
    // code propagates.
    void ForceExit(int32 InExitCode);

private:
    // FName because OnInit captures it once and class lookup happens later;
    // FString would also work, FName is cheaper to compare against UClass->GetFName().
    FName _AsTestClassName;

    UPROPERTY()
    TObjectPtr<UCk_GauntletAsTest_Base> _AsInstance;

    bool _AsInitFired = false;
    bool _Ended = false;
    double _StartTimeSeconds = 0.0;

    // Seconds the bridge waits for the AS UClass named in -asgauntlet to
    // register before firing EndTest(4). AS compile is either done by the
    // bridge's first OnTick or hard-failed; >5s is never a legitimate case.
    // Override at the CLI via `-asgauntlet-waitsec=<n>` for the rare test
    // that genuinely needs longer (e.g. cold-cache compile on CI).
    float _AsClassWaitTimeoutSeconds = 5.0f;

    // Shared sink. Owned by the bridge (refcounted via shared_ptr because
    // FOutputDevice is registered on GLog and we need a stable pointer).
    TSharedPtr<FCkGauntletAsLogSink> _LogSink;
};
