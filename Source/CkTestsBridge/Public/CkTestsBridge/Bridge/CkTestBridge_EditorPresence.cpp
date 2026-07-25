#include "CkTestBridge_EditorPresence.h"

#include "CkTestsBridge_Log.h"

#include "CkCore/Format/CkFormat.h"
#include "CkCore/Macros/CkMacros.h"

#include <Framework/Application/SlateApplication.h>
#include <Framework/Docking/TabManager.h>
#include <HAL/FileManager.h>
#include <Interfaces/IMainFrameModule.h>
#include <Misc/App.h>
#include <Misc/FileHelper.h>
#include <Misc/Paths.h>
#include <Modules/ModuleManager.h>
#include <Editor/EditorPerformanceSettings.h>

// --------------------------------------------------------------------------------------------------------------------

namespace ck_test_bridge_editor_presence
{
    // Set while WE are the reason the throttle is off, so Suppress/Restore are idempotent and a Restore that never
    // ran cannot clobber a value the user changed in the meantime.
    static bool GDidSuppress    = false;
    static bool GOriginalValue  = true;

    static auto
    Get_Settings()
        -> UEditorPerformanceSettings*
    {
        return GetMutableDefault<UEditorPerformanceSettings>();
    }

    // Only an interactive editor has a window / a throttle worth touching. A headless warm server has neither
    // (and -nullrhi already bypasses the frame-rate gate outright).
    static auto
    Is_InteractiveEditor()
        -> bool
    {
        return NOT IsRunningCommandlet() && NOT FApp::IsUnattended() && FSlateApplication::IsInitialized();
    }
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_EditorPresence::
    Get_CrashMarkerPath()
    -> FString
{
    return FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("CkTestBridge"), TEXT("throttle_restore.marker"));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_EditorPresence::
    Suppress_BackgroundThrottle()
    -> void
{
    using namespace ck_test_bridge_editor_presence;

    if (NOT Is_InteractiveEditor() || GDidSuppress)
    { return; }

    auto* Settings = Get_Settings();
    if (Settings == nullptr)
    { return; }

    GOriginalValue = Settings->bThrottleCPUWhenNotForeground;
    if (NOT GOriginalValue)
    { return; }   // already off (user's own preference) — nothing to suppress, nothing to restore

    // Marker FIRST: if we die between here and the restore, the next boot must still know what to put back.
    FFileHelper::SaveStringToFile(GOriginalValue ? TEXT("1") : TEXT("0"), *Get_CrashMarkerPath());

    Settings->bThrottleCPUWhenNotForeground = false;
    GDidSuppress = true;

    ck::tests_bridge::Display(
        TEXT("[Presence] background CPU throttle suppressed for this run (an unfocused editor would otherwise ")
        TEXT("never reach the automation frame-rate gate). Will be restored when the run finishes."));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_EditorPresence::
    Restore_BackgroundThrottle()
    -> void
{
    using namespace ck_test_bridge_editor_presence;

    if (NOT GDidSuppress)
    { return; }

    if (auto* Settings = Get_Settings();
        Settings != nullptr)
    { Settings->bThrottleCPUWhenNotForeground = GOriginalValue; }

    GDidSuppress = false;

    constexpr auto RequireExists = false;
    IFileManager::Get().Delete(*Get_CrashMarkerPath(), RequireExists);

    ck::tests_bridge::Display(TEXT("[Presence] background CPU throttle restored"));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_EditorPresence::
    Recover_BackgroundThrottleAfterCrash()
    -> void
{
    using namespace ck_test_bridge_editor_presence;

    const auto MarkerPath = Get_CrashMarkerPath();
    if (NOT IFileManager::Get().FileExists(*MarkerPath))
    { return; }

    auto Recorded = FString{};
    const auto Restore = FFileHelper::LoadFileToString(Recorded, *MarkerPath) ? Recorded.TrimStartAndEnd() != TEXT("0")
                                                                             : true;

    if (auto* Settings = Get_Settings();
        Settings != nullptr)
    {
        Settings->bThrottleCPUWhenNotForeground = Restore;
        // Unlike the normal path this DOES persist: a previous session may have been shut down (or killed) while the
        // suppressed value was live, and config can be saved on shutdown — so a stale `false` could already be in the
        // user's ini. Write the recovered value back so it cannot outlive the run that caused it.
        Settings->PostEditChange();
        Settings->SaveConfig();
    }

    constexpr auto RequireExists = false;
    IFileManager::Get().Delete(*MarkerPath, RequireExists);

    ck::tests_bridge::Warning(
        TEXT("[Presence] a previous session ended while the background CPU throttle was suppressed for a test run ")
        TEXT("— restored it to [{}]"), Restore ? TEXT("enabled") : TEXT("disabled"));
}

// --------------------------------------------------------------------------------------------------------------------

auto
    FCk_TestBridge_EditorPresence::
    Set_ServingIndicator(
        bool InIsServing,
        bool InIsRunning)
    -> void
{
    using namespace ck_test_bridge_editor_presence;

    if (NOT Is_InteractiveEditor())
    { return; }

    auto& MainFrame = FModuleManager::LoadModuleChecked<IMainFrameModule>(TEXT("MainFrame"));

    if (NOT InIsServing)
    {
        // Empty override = fall back to the editor's own computed title.
        MainFrame.SetApplicationTitleOverride(FText::GetEmpty());
        FGlobalTabmanager::Get()->SetApplicationTitle(MainFrame.GetApplicationTitle(true));
        return;
    }

    const auto Suffix = InIsRunning
        ? NSLOCTEXT("CkTestBridge", "TitleRunning", " — [CkTestBridge: RUNNING TESTS]")
        : NSLOCTEXT("CkTestBridge", "TitleArmed",   " — [CkTestBridge: SERVING]");

    // Base title WITHOUT our override, so repeated calls cannot stack suffixes.
    MainFrame.SetApplicationTitleOverride(FText::GetEmpty());
    const auto BaseTitle = MainFrame.GetApplicationTitle(true);
    const auto Decorated = FText::Format(NSLOCTEXT("CkTestBridge", "TitleFmt", "{0}{1}"), BaseTitle, Suffix);

    // Override so any later recompute keeps the suffix; SetApplicationTitle to update the LIVE window right now
    // (the override alone is only consulted when a window is created).
    MainFrame.SetApplicationTitleOverride(Decorated);
    FGlobalTabmanager::Get()->SetApplicationTitle(Decorated);
}

// --------------------------------------------------------------------------------------------------------------------
