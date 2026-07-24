#pragma once

#include "CoreMinimal.h"

#include "CkTestsBridge/Server/CkTestBridge_Preconditions.h"
#include "CkTestsBridge/Server/CkTestBridge_RunController.h"

// --------------------------------------------------------------------------------------------------------------------
// The request-file protocol CORE shared by the -CkTestBridgeServe warm server and the interactive-editor bridge.
// Mirrors CkAssetExporter's FCk_AssetExporter_RequestProcessor, but test runs are ASYNCHRONOUS: claiming a request
// kicks a non-blocking RunController and returns; the result is written on a LATER poll once the run completes.
//
// On-disk protocol (all absolute, computed once at construction), under <ProjectSaved>/CkTestBridge/:
//   Requests/<id>.json   — one request dropped by the driver (op = runTests | quit)
//   Results/<id>.json    — the verdict, written BEFORE the request is deleted
//   Progress/<id>.jsonl  — append-only, one JSON object per line, flushed per line
//   server.json          — pid / startedAt / project / protocolVersion / busy / currentRequestId / lastActivityAt
//
// Contains NO watchdog / sleep / lifetime policy — the driving loop (subsystem ticker) owns idle + wall-clock
// timeouts. It DOES pump the in-flight RunController each poll (that is the async part).
// --------------------------------------------------------------------------------------------------------------------

// Protocol version advertised in server.json and enforced against a request's optional "protocolVersion" field.
inline constexpr auto Ck_TestBridge_ProtocolVersion = int32{1};

// --------------------------------------------------------------------------------------------------------------------

struct FCk_TestBridge_ProcessResult
{
    bool QuitRequested = false;
    bool AnyProcessed  = false;
};

// --------------------------------------------------------------------------------------------------------------------

enum class ECk_TestBridge_StaleRequestPolicy : uint8
{
    // Delete every queued request at startup. The dedicated warm server OWNS the queue at boot.
    WipeStale,

    // Leave queued requests in place. The editor bridge uses this so it never discards work someone queued and can
    // re-claim on a request that triggered the re-claim.
    PreserveExisting
};

// --------------------------------------------------------------------------------------------------------------------

class CKTESTSBRIDGE_API FCk_TestBridge_RequestProcessor
{
public:
    FCk_TestBridge_RequestProcessor();

public:
    // Create the protocol dirs, (per policy) wipe stale requests, wait once for the asset registry, publish
    // server.json. Returns false ONLY if the dirs could not be created. Re-runnable.
    auto
    Startup(
        ECk_TestBridge_StaleRequestPolicy InStaleRequestPolicy = ECk_TestBridge_StaleRequestPolicy::WipeStale) -> bool;

    // One poll pass. While a run is in flight: pump the RunController, refresh the heartbeat, and on completion
    // write the result + delete the request + un-busy. While idle: claim at most ONE settled request, validate it,
    // and either refuse-and-delete it or start a run (non-blocking). InDeltaTime pumps the in-flight run.
    auto
    ProcessPending(
        float InDeltaTime) -> FCk_TestBridge_ProcessResult;

    // Remove server.json. Safe whether or not Startup ran. Does NOT abort an in-flight run (the caller owns that).
    auto
    Shutdown() -> void;

public:
    // True when at least one *.json sits in Requests/ — the bridge's re-claim gate after a quit handoff.
    auto
    Has_PendingRequests() const -> bool;

    auto Get_RequestsDir() const -> const FString&      { return _RequestsDir; }
    auto Get_ResultsDir() const -> const FString&       { return _ResultsDir; }
    auto Get_ProgressDir() const -> const FString&      { return _ProgressDir; }
    auto Get_ServerStatusPath() const -> const FString& { return _ServerStatusPath; }

    auto Get_IsBusy() const -> bool { return _Busy; }

private:
    auto
    Do_WriteStatusFile(
        bool InBusy,
        const FString& InCurrentRequestId) -> void;

    // Parse + validate one request file. Refuses (writes a refused result + deletes) or accepts (marks busy, starts
    // the RunController). Returns true if the op asked the server to quit.
    auto
    Do_ClaimRequest(
        const FString& InRequestPath) -> bool;

    // Called each poll while _Busy: pump the runner, and on completion finalize (write result, delete request).
    auto
    Do_PumpActiveRun(
        float InDeltaTime) -> void;

    auto
    Do_AppendProgress(
        const TSharedPtr<class FJsonObject>& InEvent) -> void;

private:
    FString _Root;
    FString _RequestsDir;
    FString _ResultsDir;
    FString _ProgressDir;
    FString _ServerStatusPath;
    FString _StartedAtIso;

    bool    _Busy = false;
    FString _CurrentRequestId;
    FString _CurrentRequestPath;
    FString _CurrentResultPath;
    FString _CurrentProgressPath;

    FCk_TestBridge_Env          _CurrentEnv;
    FCk_TestBridge_RunController _Runner;
};

// --------------------------------------------------------------------------------------------------------------------
