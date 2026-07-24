#include "CkTestBridge_Subsystem.h"

#include "CkTestsBridge_Log.h"
#include "CkTestsBridge/Settings/CkTestBridge_UserSettings.h"

#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include "AssetRegistry/AssetRegistryModule.h"

#include <CoreGlobals.h>
#include <Dom/JsonObject.h>
#include <Editor.h>
#include <Engine/World.h>
#include <HAL/FileManager.h>
#include <HAL/PlatformProcess.h>
#include <HAL/PlatformTime.h>
#include <Misc/App.h>
#include <Misc/CommandLine.h>
#include <Misc/FileHelper.h>
#include <Misc/Optional.h>
#include <Misc/Parse.h>
#include <Serialization/JsonReader.h>
#include <Serialization/JsonSerializer.h>
#include <UObject/Package.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_bridge_subsystem
{
    constexpr auto PollSeconds        = float{0.5f};
    constexpr auto IdleTimeoutSeconds = double{15.0 * 60.0};
    constexpr auto MaxRuntimeSeconds  = double{2.0 * 60.0 * 60.0};

    static auto
    Read_ServerPid(
        const FString& InServerStatusPath)
        -> TOptional<uint32>
    {
        auto JsonString = FString{};
        if (NOT FFileHelper::LoadFileToString(JsonString, *InServerStatusPath))
        { return {}; }

        auto Status = TSharedPtr<FJsonObject>{};
        const auto Reader = TJsonReaderFactory<>::Create(JsonString);
        if (NOT FJsonSerializer::Deserialize(Reader, Status) || NOT Status.IsValid())
        { return {}; }

        auto Pid = uint32{0};
        if (NOT Status->TryGetNumberField(TEXT("pid"), Pid))
        { return {}; }

        return Pid;
    }

    static auto
    Get_CurrentEditorMapName()
        -> FString
    {
        if (GEditor == nullptr)
        { return {}; }

        const auto& WorldContext = GEditor->GetEditorWorldContext();
        auto* World = WorldContext.World();
        if (World == nullptr)
        { return {}; }

        return World->GetOutermost()->GetName();
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    Initialize(
        FSubsystemCollectionBase& InCollection)
    -> void
{
    using namespace ck_test_bridge_subsystem;

    Super::Initialize(InCollection);

    _IsServeModeProcess = FParse::Param(FCommandLine::Get(), TEXT("CkTestBridgeServe"));

    if (NOT Do_ShouldArm())
    {
        ck::tests_bridge::Verbose(
            TEXT("[Bridge] dormant (unattended / commandlet test boot without -CkTestBridgeServe)"));
        return;
    }

    _StartSeconds        = FPlatformTime::Seconds();
    _LastActivitySeconds = _StartSeconds;

    _TickerHandle = FTSTicker::GetCoreTicker().AddTicker(
        FTickerDelegate::CreateUObject(this, &UCkTestBridge_Subsystem::OnTick), PollSeconds);

    ck::tests_bridge::Display(
        TEXT("[Bridge] armed ({}) — polling for test requests every 500ms"),
        _IsServeModeProcess ? TEXT("warm server") : TEXT("live editor"));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    Deinitialize()
    -> void
{
    if (_TickerHandle.IsValid())
    {
        FTSTicker::GetCoreTicker().RemoveTicker(_TickerHandle);
        _TickerHandle.Reset();
    }

    if (_IsServing)
    {
        _Processor.Shutdown();
        _IsServing = false;
    }

    Super::Deinitialize();
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    OnTick(
        float InDeltaTime)
    -> bool
{
    if (NOT _IsServing)
    { DoTryClaimServing(); }

    if (_IsServing)
    {
        const auto PollResult = _Processor.ProcessPending(InDeltaTime);
        if (PollResult.QuitRequested)
        { DoReleaseServing(); }
        else if (_IsServeModeProcess)
        { DoServeModeWatchdogs(PollResult.AnyProcessed); }
    }

    constexpr auto KeepTicking = true;
    return KeepTicking;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    Do_ShouldArm() const
    -> bool
{
    // The warm server serves DESPITE being unattended — that is its entire purpose.
    if (_IsServeModeProcess)
    { return true; }

    // An ordinary toolbox-spawned test boot is unattended (and one-shot export runs are commandlets) — they must
    // NEVER claim, or the bridge would deadlock the driver's own fresh-boot fallback against its own spawn.
    if (IsRunningCommandlet() || FApp::IsUnattended())
    { return false; }

    // Interactive editor — the live bridge.
    return true;
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    Do_ShouldServe() const
    -> bool
{
    using namespace ck_test_bridge_subsystem;

    const auto* Settings = GetDefault<UCk_TestBridge_UserSettings>();
    const auto ServeMode = Settings != nullptr ? Settings->Get_ServeMode() : ECk_TestBridge_ServeMode::Off;

    switch (ServeMode)
    {
        case ECk_TestBridge_ServeMode::Off:
            return false;

        case ECk_TestBridge_ServeMode::CleanEditorBorrow:
            return true;

        case ECk_TestBridge_ServeMode::AutoTestsMapOnly:
        default:
        {
            // The warm server boots headless directly onto the AutoTests map — always eligible.
            if (_IsServeModeProcess)
            { return true; }

            // [VERIFY] host-agnostic proxy for "the editor is on the AutoTests map": package name contains
            // "AutoTests" (BB's map is AutoTests_BB_MAP).
            return Get_CurrentEditorMapName().Contains(TEXT("AutoTests"));
        }
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    DoTryClaimServing()
    -> void
{
    using namespace ck_test_bridge_subsystem;

    if (NOT Do_ShouldServe())
    { return; }

    // After a quit handoff, stay released until a new request actually arrives.
    if (_AwaitingRequestToReclaim && NOT _Processor.Has_PendingRequests())
    { return; }

    // The registry must be fully scanned before serving — Startup's WaitForCompletion would otherwise BLOCK the
    // game thread (freezing the UI during the post-boot scan). Defer until the scan is done.
    const auto* AssetRegistryModule = FModuleManager::GetModulePtr<FAssetRegistryModule>(TEXT("AssetRegistry"));
    if (AssetRegistryModule == nullptr || AssetRegistryModule->Get().IsLoadingAssets())
    { return; }

    auto& FileManager = IFileManager::Get();
    const auto& ServerStatusPath = _Processor.Get_ServerStatusPath();

    if (FileManager.FileExists(*ServerStatusPath))
    {
        const auto OurPid   = FPlatformProcess::GetCurrentProcessId();
        const auto OwnerPid = Read_ServerPid(ServerStatusPath);

        const auto IsOwnedByLiveOther =
            OwnerPid.IsSet() &&
            OwnerPid.GetValue() != OurPid &&
            FPlatformProcess::IsApplicationRunning(OwnerPid.GetValue());

        if (IsOwnedByLiveOther)
        {
            // Defer to a live owner that looks like an editor/commandlet, or whose name we cannot read
            // (conservative: never risk two servers writing the same Results). Reclaim ONLY when the live owner is
            // demonstrably an unrelated process that inherited the recorded pid.
            const auto OwnerName    = FPlatformProcess::GetApplicationName(OwnerPid.GetValue());
            const auto DeferToOwner = OwnerName.IsEmpty() || OwnerName.Contains(TEXT("Editor"));

            if (DeferToOwner)
            { return; }

            ck::tests_bridge::Display(
                TEXT("[Bridge] server.json pid {} is a live non-editor process [{}] — reclaiming (stale pid reuse)"),
                OwnerPid.GetValue(), OwnerName);
        }
        // Otherwise: dead owner, unreadable pid, our own leftover, or reclaimable pid reuse — fall through and
        // (re)claim. Startup rewrites server.json, so the stale file needs no explicit delete.
    }

    // PreserveExisting: the bridge must never discard queued work, and a re-claim is TRIGGERED by a pending request.
    if (NOT _Processor.Startup(ECk_TestBridge_StaleRequestPolicy::PreserveExisting))
    {
        ck::tests_bridge::Warning(TEXT("[Bridge] could not start serving (protocol dirs unavailable) — will retry"));
        return;
    }

    _IsServing = true;
    _AwaitingRequestToReclaim = false;
    _LastActivitySeconds = FPlatformTime::Seconds();
    ck::tests_bridge::Display(TEXT("[Bridge] serving test requests (pid {})"), FPlatformProcess::GetCurrentProcessId());
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    DoReleaseServing()
    -> void
{
    _Processor.Shutdown();
    _IsServing = false;
    _AwaitingRequestToReclaim = true;

    ck::tests_bridge::Display(
        TEXT("[Bridge] quit handled — released serving (will re-claim when new requests arrive)"));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    UCkTestBridge_Subsystem::
    DoServeModeWatchdogs(
        bool InAnyProcessed)
    -> void
{
    using namespace ck_test_bridge_subsystem;

    const auto Now = FPlatformTime::Seconds();

    // A run in flight, or a request consumed this pass, counts as activity — never idle-quit mid-run.
    if (InAnyProcessed || _Processor.Get_IsBusy())
    { _LastActivitySeconds = Now; }

    if (NOT _Processor.Get_IsBusy() && Now - _LastActivitySeconds >= IdleTimeoutSeconds)
    {
        ck::tests_bridge::Display(
            TEXT("[Bridge] warm server idle {} min with no requests — quitting editor"), IdleTimeoutSeconds / 60.0);
        RequestEngineExit(TEXT("CkTestBridge idle self-quit"));
        return;
    }

    if (Now - _StartSeconds >= MaxRuntimeSeconds)
    {
        ck::tests_bridge::Display(
            TEXT("[Bridge] warm server {}h wall-clock cap reached — quitting editor"), MaxRuntimeSeconds / 3600.0);
        RequestEngineExit(TEXT("CkTestBridge wall-clock cap"));
    }
}

// --------------------------------------------------------------------------------------------------------------------
