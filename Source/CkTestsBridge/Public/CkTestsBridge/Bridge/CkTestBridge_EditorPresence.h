#pragma once

#include <CoreMinimal.h>

// --------------------------------------------------------------------------------------------------------------------
//
// The two ways serving a test run REACHES INTO the user's interactive editor. Both are no-ops in a headless warm
// server (nothing to throttle, no window to title).
//
//   1. Background-throttle suppression. `bShouldDisableRendering = !FApp::HasFocus() &&
//      bThrottleCPUWhenNotForeground` (EditorEngine.cpp:1799), so an UNFOCUSED editor drops to a few FPS and the
//      automation controller's FWaitForInteractiveFrameRate gate inside IsReadyForTests() never opens — the run
//      then aborts at the RunController's ready-wait. Measured 2026-07-25: unfocused ⇒ abort every time; focused ⇒
//      gate opened in ~20s. The engine's own automation does exactly this suppression
//      (AutomationEditorCommon.cpp:1273), the difference being that a throwaway automation process never restores
//      it and a user's long-lived session must.
//
//   2. Window-title indicator. Being borrowed is otherwise INVISIBLE: PIE starts, the level changes, and the only
//      explanation lives in the driver's log, which the person sitting at the editor is not reading.
//
// --------------------------------------------------------------------------------------------------------------------

class FCk_TestBridge_EditorPresence
{
public:
    // ---- Background-throttle suppression (only while a run is in flight) ----

    // Idempotent. Records the current value, then clears it so an unfocused editor keeps rendering.
    // Deliberately does NOT call PostEditChange/SaveConfig: the consumer reads the live CDO every tick, so a
    // transient in-memory change suffices and the user's .ini is left alone.
    static auto Suppress_BackgroundThrottle() -> void;

    // Idempotent. Restores whatever Suppress_ recorded and clears the crash marker.
    static auto Restore_BackgroundThrottle() -> void;

    // Call once at subsystem startup. If a previous session died while the throttle was suppressed (crash, kill,
    // power loss), the marker left on disk tells us what to put back — and because a shutdown MAY have persisted
    // the suppressed value, this path DOES rewrite the config so a stale `false` cannot outlive the run that
    // caused it.
    static auto Recover_BackgroundThrottleAfterCrash() -> void;

    // ---- Window-title indicator ----

    // InIsRunning: a request is executing right now (vs merely armed and waiting for one).
    static auto Set_ServingIndicator(bool InIsServing, bool InIsRunning) -> void;

private:
    static auto Get_CrashMarkerPath() -> FString;
};
