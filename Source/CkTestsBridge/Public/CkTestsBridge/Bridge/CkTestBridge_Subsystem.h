#pragma once

#include "CkTestsBridge/Server/CkTestBridge_RequestProcessor.h"

#include "CkCore/Macros/CkMacros.h"

#include "Containers/Ticker.h"

#include <CoreMinimal.h>
#include <EditorSubsystem.h>

#include "CkTestBridge_Subsystem.generated.h"

// --------------------------------------------------------------------------------------------------------------------
// Editor-subsystem bridge letting an editor serve the CkTestBridge Requests -> Results protocol — the SAME machinery
// serves both the interactive-editor "live bridge" and the headless "-CkTestBridgeServe" warm server (the warm server
// is NOT a blocking commandlet: the automation controller must be pumped on the editor game thread, so a Sleep-loop
// would starve it — the bridge subsystem staying alive in a -unattended editor IS the warm server, and the RunController
// is ticked from THIS subsystem's ticker).
//
// A 0.5s ticker lazily CLAIMS serving (writes server.json), defers to a live owner, reclaims a demonstrably-stale
// slot, and while claimed drains + pumps requests each tick. TWO gates beyond CkAssetExporter's bridge:
//
//   (a) SERVE-MODE opt-in — UCk_TestBridge_UserSettings::Get_ServeMode(). Off never claims; AutoTestsMapOnly claims
//       only when the current editor map is the AutoTests map (or this is the warm server); CleanEditorBorrow claims
//       from any editor state. (Per-request PIE/AS/dirty preconditions still gate every actual run.)
//
//   (b) INVERTED unattended guard — CkAssetExporter's bridge goes dormant under commandlets; here the WARM server IS
//       an unattended headless editor and MUST serve. So: skip claiming when IsRunningCommandlet() ||
//       FApp::IsUnattended() UNLESS the process was launched with -CkTestBridgeServe. Rationale: an ordinary
//       toolbox-spawned test boot (no flag) must NEVER claim, or it would deadlock the toolbox's own fresh-boot
//       fallback against its own spawn.
//
// LAUNCH CONTRACT for the warm server (toolbox-owned):
//   <Editor>.exe <Project>.uproject <AutoTestsMap> -unattended -CkTestBridgeServe -CkAsDeclineRegenOwnership
//   -CkTestBridgeServe        keeps THIS subsystem serving despite -unattended, and arms the idle / wall-clock quits.
//   -CkAsDeclineRegenOwnership (honored by CkAngelscriptGenerator) makes the warm server decline AS-regen ownership
//                             so a concurrently-spawned test editor stays PRIMARY for codegen.
// --------------------------------------------------------------------------------------------------------------------

UCLASS()
class CKTESTSBRIDGE_API UCkTestBridge_Subsystem : public UEditorSubsystem
{
    GENERATED_BODY()

public:
    CK_GENERATED_BODY(UCkTestBridge_Subsystem);

public:
    auto
    Initialize(
        FSubsystemCollectionBase& InCollection) -> void override;

    auto
    Deinitialize() -> void override;

private:
    auto
    OnTick(
        float InDeltaTime) -> bool;

    // True when THIS process should arm the ticker at all (interactive editor, or the -CkTestBridgeServe warm
    // server; never an ordinary unattended/commandlet test boot).
    auto
    Do_ShouldArm() const -> bool;

    // True when the current serve-mode setting + editor state permit claiming. Coarse opt-in; per-request
    // preconditions are the fine gate.
    auto
    Do_ShouldServe() const -> bool;

    auto
    DoTryClaimServing() -> void;

    auto
    DoReleaseServing() -> void;

    // Only armed for the -CkTestBridgeServe warm server: quit the editor on an idle window or a wall-clock cap.
    auto
    DoServeModeWatchdogs(
        bool InAnyProcessed) -> void;

private:
    FCk_TestBridge_RequestProcessor _Processor;
    FTSTicker::FDelegateHandle       _TickerHandle;

    bool _IsServing = false;

    // After a quit op releases the claim, only re-claim once Requests/ is non-empty — a clean handoff.
    bool _AwaitingRequestToReclaim = false;

    // Set from -CkTestBridgeServe on the command line: this is the resident warm server (serve despite unattended,
    // and self-quit on idle / wall cap).
    bool _IsServeModeProcess = false;

    // Edge-detect the processor's busy flag so the editor-presence effects (background-throttle suppression, the
    // stronger title suffix) fire once per run rather than on every tick.
    bool _WasBusy = false;

    // The ticker fires every frame (an active run must pump the automation controller at frame rate); this throttles
    // the IDLE work — claim attempts, request scans, server.json heartbeat — back to the ~0.5s cadence.
    float _IdleAccumulatorSeconds = 0.0f;

    double _StartSeconds        = 0.0;
    double _LastActivitySeconds = 0.0;
};

// --------------------------------------------------------------------------------------------------------------------
