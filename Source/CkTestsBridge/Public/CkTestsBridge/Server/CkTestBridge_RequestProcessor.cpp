#include "CkTestBridge_RequestProcessor.h"

#include "CkTestsBridge_Log.h"

#include "CkCore/Ensure/CkEnsure.h"
#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include "AssetRegistry/AssetRegistryModule.h"

#include <Dom/JsonObject.h>
#include <Dom/JsonValue.h>
#include <HAL/FileManager.h>
#include <HAL/PlatformProcess.h>
#include <Misc/CommandLine.h>
#include <Misc/DateTime.h>
#include <Misc/FileHelper.h>
#include <Misc/Parse.h>
#include <Misc/Paths.h>
#include <Policies/CondensedJsonPrintPolicy.h>
#include <Serialization/JsonReader.h>
#include <Serialization/JsonSerializer.h>
#include <Serialization/JsonWriter.h>
#include <UObject/UObjectGlobals.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_bridge_requestprocessor
{
    // Requests older than this (by file mtime) are refused rather than run — a live test bridge must never launch a
    // PIE takeover on a request the driver has long forgotten.
    constexpr auto StaleRequestSeconds = double{5.0 * 60.0};

    static auto
    Write_Json(
        const TSharedPtr<FJsonObject>& InObject,
        const FString& InPath)
        -> void
    {
        auto JsonString = FString{};
        const auto Writer = TJsonWriterFactory<>::Create(&JsonString);
        FJsonSerializer::Serialize(InObject.ToSharedRef(), Writer);
        FFileHelper::SaveStringToFile(JsonString, *InPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
    }

    static auto
    Read_StringArray(
        const TSharedPtr<FJsonObject>& InObject,
        const FString& InField,
        TArray<FString>& OutArray)
        -> void
    {
        const TArray<TSharedPtr<FJsonValue>>* Values = nullptr;
        if (NOT InObject->TryGetArrayField(InField, Values) || Values == nullptr)
        { return; }

        for (const auto& Value : *Values)
        {
            auto Str = FString{};
            if (Value.IsValid() && Value->TryGetString(Str))
            { OutArray.Add(Str); }
        }
    }

    static auto
    Build_EnvJson(
        const FCk_TestBridge_Env& InEnv)
        -> TSharedPtr<FJsonObject>
    {
        auto Env = MakeShared<FJsonObject>();
        Env->SetBoolField(TEXT("live"), InEnv.Live);
        Env->SetNumberField(TEXT("editorPid"), static_cast<double>(InEnv.EditorPid));
        Env->SetBoolField(TEXT("asPendingFullReload"), InEnv.AsPendingFullReload);
        Env->SetBoolField(TEXT("asCompileErrors"), InEnv.AsCompileErrors);

        auto Dirty = TArray<TSharedPtr<FJsonValue>>{};
        for (const auto& Name : InEnv.DirtyPackages)
        { Dirty.Add(MakeShared<FJsonValueString>(Name)); }
        Env->SetArrayField(TEXT("dirtyPackages"), Dirty);

        return Env;
    }

    static auto
    Write_RefusedResult(
        const FString& InResultPath,
        const FString& InReason,
        const FCk_TestBridge_Env& InEnv)
        -> void
    {
        auto Result = MakeShared<FJsonObject>();
        Result->SetBoolField(TEXT("ok"), false);
        Result->SetBoolField(TEXT("refused"), true);
        Result->SetStringField(TEXT("refusalReason"), InReason);
        Result->SetObjectField(TEXT("env"), Build_EnvJson(InEnv));
        Result->SetArrayField(TEXT("perTest"), TArray<TSharedPtr<FJsonValue>>{});
        Result->SetArrayField(TEXT("notFound"), TArray<TSharedPtr<FJsonValue>>{});
        Write_Json(Result, InResultPath);
    }

    static auto
    Write_ErrorResult(
        const FString& InResultPath,
        const FString& InMessage)
        -> void
    {
        auto Result = MakeShared<FJsonObject>();
        Result->SetBoolField(TEXT("ok"), false);
        Result->SetBoolField(TEXT("refused"), false);
        Result->SetStringField(TEXT("error"), InMessage);
        Write_Json(Result, InResultPath);
    }

    static auto
    Delete_FilesIn(
        const FString& InDir,
        const TCHAR* InWildcard)
        -> void
    {
        auto& FileManager = IFileManager::Get();
        auto FoundFiles = TArray<FString>{};
        constexpr auto FindFiles = true;
        constexpr auto FindDirectories = false;
        FileManager.FindFiles(FoundFiles, *FPaths::Combine(InDir, InWildcard), FindFiles, FindDirectories);

        for (const auto& FileName : FoundFiles)
        {
            constexpr auto RequireExists = false;
            FileManager.Delete(*FPaths::Combine(InDir, FileName), RequireExists);
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

FCk_TestBridge_RequestProcessor::
    FCk_TestBridge_RequestProcessor()
    // Absolute on purpose: these paths are handed to the external driver via server.json — a relative form only
    // resolves from the editor's cwd, not the submitter's.
    : _Root{FPaths::ConvertRelativePathToFull(FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("CkTestBridge")))}
    , _RequestsDir{FPaths::Combine(_Root, TEXT("Requests"))}
    , _ResultsDir{FPaths::Combine(_Root, TEXT("Results"))}
    , _ProgressDir{FPaths::Combine(_Root, TEXT("Progress"))}
    , _ServerStatusPath{FPaths::Combine(_Root, TEXT("server.json"))}
{
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    Startup(
        ECk_TestBridge_StaleRequestPolicy InStaleRequestPolicy)
    -> bool
{
    using namespace ck_test_bridge_requestprocessor;

    auto& FileManager = IFileManager::Get();

    constexpr auto MakeTree = true;
    FileManager.MakeDirectory(*_RequestsDir, MakeTree);
    FileManager.MakeDirectory(*_ResultsDir, MakeTree);
    FileManager.MakeDirectory(*_ProgressDir, MakeTree);

    const auto DirsExist =
        FileManager.DirectoryExists(*_RequestsDir) &&
        FileManager.DirectoryExists(*_ResultsDir) &&
        FileManager.DirectoryExists(*_ProgressDir);

    CK_ENSURE_IF_NOT(DirsExist, TEXT("[Server] could not create protocol dirs under [{}]"), _Root)
    {}
    if (NOT DirsExist)
    { return false; }

    if (InStaleRequestPolicy == ECk_TestBridge_StaleRequestPolicy::WipeStale)
    { Delete_FilesIn(_RequestsDir, TEXT("*.json")); }

    {
        auto& AssetRegistry = FModuleManager::LoadModuleChecked<FAssetRegistryModule>("AssetRegistry").Get();
        AssetRegistry.WaitForCompletion();
    }

    _StartedAtIso = FDateTime::UtcNow().ToIso8601();
    Do_WriteStatusFile(false, {});

    return true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    Do_WriteStatusFile(
        bool InBusy,
        const FString& InCurrentRequestId)
    -> void
{
    using namespace ck_test_bridge_requestprocessor;

    auto Status = MakeShared<FJsonObject>();
    Status->SetNumberField(TEXT("pid"), static_cast<double>(FPlatformProcess::GetCurrentProcessId()));
    Status->SetStringField(TEXT("startedAt"), _StartedAtIso);
    Status->SetStringField(TEXT("project"), FPaths::ConvertRelativePathToFull(FPaths::GetProjectFilePath()));
    Status->SetNumberField(TEXT("protocolVersion"), static_cast<double>(Ck_TestBridge_ProtocolVersion));
    Status->SetStringField(TEXT("requestsDir"), _RequestsDir);
    Status->SetStringField(TEXT("resultsDir"), _ResultsDir);
    Status->SetStringField(TEXT("progressDir"), _ProgressDir);
    // serverKind lets the driver tell a headless WARM SERVER (launched with -CkTestBridgeServe, no window, no
    // frame-rate throttle) apart from a LIVE EDITOR (the user's own interactive session serving under
    // AutoTestsMapOnly). They behave very differently: an unfocused interactive editor throttles below the
    // automation controller's interactive-frame-rate gate and aborts the run, so a driver should only auto-route to
    // a warm server and require an explicit opt-in for an editor. Derived from the command line — a process-wide fact.
    Status->SetStringField(TEXT("serverKind"),
        FParse::Param(FCommandLine::Get(), TEXT("CkTestBridgeServe")) ? TEXT("warmServer") : TEXT("liveEditor"));
    Status->SetBoolField(TEXT("busy"), InBusy);
    if (NOT InCurrentRequestId.IsEmpty())
    { Status->SetStringField(TEXT("currentRequestId"), InCurrentRequestId); }
    // lastActivityAt is refreshed on EVERY write (including the per-tick busy heartbeat) so a foreign session can
    // tell an actively-working server from a hung one.
    Status->SetStringField(TEXT("lastActivityAt"), FDateTime::UtcNow().ToIso8601());
    Write_Json(Status, _ServerStatusPath);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    ProcessPending(
        float InDeltaTime)
    -> FCk_TestBridge_ProcessResult
{
    using namespace ck_test_bridge_requestprocessor;

    auto Outcome = FCk_TestBridge_ProcessResult{};

    // A run in flight — pump it, don't claim anything new. One request at a time.
    if (_Busy)
    {
        Do_PumpActiveRun(InDeltaTime);
        Outcome.AnyProcessed = NOT _Busy; // flipped false when the run finalized this tick
        return Outcome;
    }

    auto& FileManager = IFileManager::Get();

    auto RequestFiles = TArray<FString>{};
    constexpr auto FindFiles = true;
    constexpr auto FindDirectories = false;
    FileManager.FindFiles(RequestFiles, *FPaths::Combine(_RequestsDir, TEXT("*.json")), FindFiles, FindDirectories);
    RequestFiles.Sort();

    for (const auto& RequestFileName : RequestFiles)
    {
        const auto RequestPath = FPaths::Combine(_RequestsDir, RequestFileName);

        // Skip sub-second-old files (mid-write settle guard) — the next poll picks them up settled.
        const auto FileAge = FDateTime::UtcNow() - FileManager.GetTimeStamp(*RequestPath);
        if (FileAge < FTimespan::FromSeconds(1.0))
        { continue; }

        const auto ShouldQuit = Do_ClaimRequest(RequestPath);
        Outcome.AnyProcessed = true;
        if (ShouldQuit)
        { Outcome.QuitRequested = true; }

        // Claim at most ONE request per pass: either a run is now in flight (busy) or it was refused/handled.
        break;
    }

    return Outcome;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    Do_ClaimRequest(
        const FString& InRequestPath)
    -> bool
{
    using namespace ck_test_bridge_requestprocessor;

    auto& FileManager = IFileManager::Get();
    const auto RequestId  = FPaths::GetBaseFilename(InRequestPath);
    const auto ResultPath = FPaths::Combine(_ResultsDir, RequestId + TEXT(".json"));

    const auto DeleteRequest = [&]() -> void
    {
        constexpr auto RequireExists = false;
        FileManager.Delete(*InRequestPath, RequireExists);
    };

    auto JsonString = FString{};
    if (NOT FFileHelper::LoadFileToString(JsonString, *InRequestPath))
    {
        Write_ErrorResult(ResultPath, TEXT("Could not read request file"));
        DeleteRequest();
        return false;
    }

    auto Request = TSharedPtr<FJsonObject>{};
    const auto Reader = TJsonReaderFactory<>::Create(JsonString);
    if (NOT FJsonSerializer::Deserialize(Reader, Request) || NOT Request.IsValid())
    {
        Write_ErrorResult(ResultPath, TEXT("Malformed request json"));
        DeleteRequest();
        return false;
    }

    auto Op = FString{};
    Request->TryGetStringField(TEXT("op"), Op);

    if (Op.Equals(TEXT("quit"), ESearchCase::IgnoreCase))
    {
        auto Result = MakeShared<FJsonObject>();
        Result->SetBoolField(TEXT("ok"), true);
        Write_Json(Result, ResultPath);
        DeleteRequest();
        ck::tests_bridge::Display(TEXT("[Server] quit requested"));
        return true;
    }

    if (NOT Op.Equals(TEXT("runTests"), ESearchCase::IgnoreCase))
    {
        Write_ErrorResult(ResultPath, ck::Format_UE(TEXT("Unknown op [{}] (expected runTests | quit)"), Op));
        DeleteRequest();
        return false;
    }

    // ---- request-level refusals (do not need the editor env) ----
    auto RequestLevelRefusal = TOptional<FString>{};

    auto ProtocolVersion = int32{Ck_TestBridge_ProtocolVersion};
    if (Request->TryGetNumberField(TEXT("protocolVersion"), ProtocolVersion) && ProtocolVersion != Ck_TestBridge_ProtocolVersion)
    { RequestLevelRefusal = FString{TEXT("protocolVersion")}; }

    if (NOT RequestLevelRefusal.IsSet())
    {
        const auto FileAge = FDateTime::UtcNow() - FileManager.GetTimeStamp(*InRequestPath);
        if (FileAge.GetTotalSeconds() > StaleRequestSeconds)
        { RequestLevelRefusal = FString{TEXT("staleRequest")}; }
    }

    if (NOT RequestLevelRefusal.IsSet())
    {
        auto SubmitterPid = int32{0};
        if (Request->TryGetNumberField(TEXT("submitterPid"), SubmitterPid) &&
            SubmitterPid > 0 &&
            NOT FPlatformProcess::IsApplicationRunning(static_cast<uint32>(SubmitterPid)))
        { RequestLevelRefusal = FString{TEXT("submitterGone")}; }
    }

    // ---- options ----
    auto AllowDirtyWorld    = false;
    auto PerTestStallSeconds = double{300.0};
    auto WallClockCapSeconds = double{3600.0};

    const TSharedPtr<FJsonObject>* Options = nullptr;
    if (Request->TryGetObjectField(TEXT("options"), Options) && Options != nullptr)
    {
        (*Options)->TryGetBoolField(TEXT("allowDirtyWorld"), AllowDirtyWorld);
        (*Options)->TryGetNumberField(TEXT("perTestStallSeconds"), PerTestStallSeconds);
        (*Options)->TryGetNumberField(TEXT("wallClockCapSeconds"), WallClockCapSeconds);
    }

    // ---- precondition env (always fills OutEnv; returns the precondition-level refusal if any) ----
    auto Env = FCk_TestBridge_Env{};
    constexpr auto NotBusyForThisRequest = false;
    const auto PreconditionRefusal = FCk_TestBridge_Preconditions::Evaluate(AllowDirtyWorld, NotBusyForThisRequest, Env);

    const auto Refusal = RequestLevelRefusal.IsSet() ? RequestLevelRefusal : PreconditionRefusal;
    if (Refusal.IsSet())
    {
        Write_RefusedResult(ResultPath, Refusal.GetValue(), Env);
        DeleteRequest();
        ck::tests_bridge::Display(TEXT("[Server] refused request [{}] — {}"), RequestId, Refusal.GetValue());
        return false;
    }

    // ---- accept: mark busy and start the run (non-blocking) ----
    auto RunRequest = FCk_TestBridge_RunRequest{};
    Read_StringArray(Request, TEXT("tests"), RunRequest.Tests);
    RunRequest.PerTestStallSeconds = static_cast<float>(PerTestStallSeconds);
    RunRequest.WallClockCapSeconds = static_cast<float>(WallClockCapSeconds);

    _Busy                = true;
    _CurrentRequestId    = RequestId;
    _CurrentRequestPath  = InRequestPath;
    _CurrentResultPath   = ResultPath;
    _CurrentProgressPath = FPaths::Combine(_ProgressDir, RequestId + TEXT(".jsonl"));
    _CurrentEnv          = Env;

    auto Callbacks = FCk_TestBridge_RunCallbacks{};
    Callbacks.OnAccepted = [this](int32 InTestCount) -> void
    {
        auto Event = MakeShared<FJsonObject>();
        Event->SetStringField(TEXT("event"), TEXT("accepted"));
        Event->SetNumberField(TEXT("testCount"), static_cast<double>(InTestCount));
        Do_AppendProgress(Event);
    };
    Callbacks.OnTestStarted = [this](const FString& InPath) -> void
    {
        auto Event = MakeShared<FJsonObject>();
        Event->SetStringField(TEXT("event"), TEXT("testStarted"));
        Event->SetStringField(TEXT("path"), InPath);
        Do_AppendProgress(Event);
    };
    Callbacks.OnTestCompleted = [this](const FString& InPath, ECk_TestBridge_TestResult InResult, double InDurationSec) -> void
    {
        auto Event = MakeShared<FJsonObject>();
        Event->SetStringField(TEXT("event"), TEXT("testCompleted"));
        Event->SetStringField(TEXT("path"), InPath);
        Event->SetStringField(TEXT("result"), ToString(InResult));
        Event->SetNumberField(TEXT("durationSec"), InDurationSec);
        Do_AppendProgress(Event);
    };

    Do_WriteStatusFile(true, _CurrentRequestId);
    _Runner.Begin(RunRequest, Callbacks);

    ck::tests_bridge::Display(TEXT("[Server] accepted request [{}] — {} test(s)"), RequestId, RunRequest.Tests.Num());
    return false;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    Do_PumpActiveRun(
        float InDeltaTime)
    -> void
{
    using namespace ck_test_bridge_requestprocessor;

    _Runner.Tick(InDeltaTime);

    // Heartbeat every poll so a foreign session can distinguish a working server from a hung one.
    Do_WriteStatusFile(true, _CurrentRequestId);

    if (NOT _Runner.Is_Complete())
    { return; }

    {
        auto Event = MakeShared<FJsonObject>();
        Event->SetStringField(TEXT("event"), TEXT("runCompleted"));
        Do_AppendProgress(Event);
    }

    const auto& RunResult = _Runner.Get_Result();

    // ok = every requested test that ran passed (Success/Skipped) AND nothing was NotFound.
    auto Ok = RunResult.NotFound.Num() == 0;
    for (const auto& PerTest : RunResult.PerTest)
    {
        if (PerTest.Result != ECk_TestBridge_TestResult::Success && PerTest.Result != ECk_TestBridge_TestResult::Skipped)
        { Ok = false; }
    }

    auto Result = MakeShared<FJsonObject>();
    Result->SetBoolField(TEXT("ok"), Ok);
    Result->SetBoolField(TEXT("refused"), false);
    Result->SetField(TEXT("refusalReason"), MakeShared<FJsonValueNull>());
    Result->SetObjectField(TEXT("env"), Build_EnvJson(_CurrentEnv));

    auto PerTestArray = TArray<TSharedPtr<FJsonValue>>{};
    for (const auto& PerTest : RunResult.PerTest)
    {
        auto Obj = MakeShared<FJsonObject>();
        Obj->SetStringField(TEXT("path"), PerTest.Path);
        Obj->SetStringField(TEXT("result"), ToString(PerTest.Result));
        Obj->SetNumberField(TEXT("durationSec"), PerTest.DurationSec);

        auto Entries = TArray<TSharedPtr<FJsonValue>>{};
        for (const auto& Entry : PerTest.Entries)
        {
            auto EntryObj = MakeShared<FJsonObject>();
            EntryObj->SetStringField(TEXT("type"), Entry.Type);
            EntryObj->SetStringField(TEXT("message"), Entry.Message);
            Entries.Add(MakeShared<FJsonValueObject>(EntryObj));
        }
        Obj->SetArrayField(TEXT("entries"), Entries);

        PerTestArray.Add(MakeShared<FJsonValueObject>(Obj));
    }
    Result->SetArrayField(TEXT("perTest"), PerTestArray);

    auto NotFoundArray = TArray<TSharedPtr<FJsonValue>>{};
    for (const auto& NotFound : RunResult.NotFound)
    { NotFoundArray.Add(MakeShared<FJsonValueString>(NotFound)); }
    Result->SetArrayField(TEXT("notFound"), NotFoundArray);

    // Result BEFORE request delete so an external watcher never sees a consumed request with no result.
    Write_Json(Result, _CurrentResultPath);

    {
        auto& FileManager = IFileManager::Get();
        constexpr auto RequireExists = false;
        FileManager.Delete(*_CurrentRequestPath, RequireExists);
    }

    ck::tests_bridge::Display(
        TEXT("[Server] request [{}] complete — ok={}, {} test(s), {} not found"),
        _CurrentRequestId, Ok, RunResult.PerTest.Num(), RunResult.NotFound.Num());

    _Runner.Reset();
    _Busy = false;
    _CurrentRequestId.Empty();
    _CurrentRequestPath.Empty();
    _CurrentResultPath.Empty();
    _CurrentProgressPath.Empty();
    _CurrentEnv = FCk_TestBridge_Env{};

    Do_WriteStatusFile(false, {});
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    Do_AppendProgress(
        const TSharedPtr<FJsonObject>& InEvent)
    -> void
{
    if (_CurrentProgressPath.IsEmpty())
    { return; }

    auto Line = FString{};
    const auto Writer = TJsonWriterFactory<TCHAR, TCondensedJsonPrintPolicy<TCHAR>>::Create(&Line);
    FJsonSerializer::Serialize(InEvent.ToSharedRef(), Writer);
    Line.Append(LINE_TERMINATOR);

    // Append + flush per line so an external tailer sees each event immediately.
    constexpr auto FileWriteFlags = FILEWRITE_Append;
    FFileHelper::SaveStringToFile(
        Line, *_CurrentProgressPath, FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM, &IFileManager::Get(), FileWriteFlags);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    Shutdown()
    -> void
{
    constexpr auto RequireExists = false;
    IFileManager::Get().Delete(*_ServerStatusPath, RequireExists);
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_RequestProcessor::
    Has_PendingRequests() const
    -> bool
{
    auto& FileManager = IFileManager::Get();
    auto RequestFiles = TArray<FString>{};
    constexpr auto FindFiles = true;
    constexpr auto FindDirectories = false;
    FileManager.FindFiles(RequestFiles, *FPaths::Combine(_RequestsDir, TEXT("*.json")), FindFiles, FindDirectories);
    return RequestFiles.Num() > 0;
}

// --------------------------------------------------------------------------------------------------------------------
