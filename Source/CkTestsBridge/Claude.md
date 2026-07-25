# CkTestsBridge

**Editor-only (`UncookedOnly`) module.** A live-editor **test** bridge: an external driver (the
UnrealToolbox) drops a JSON request file and an already-running editor runs a set of automation
tests and streams results back — the run-tests analogue of CkAssetExporter's export file-drop
bridge. Amortizes the editor-boot cost across many test batches.

**Depends on:** `CkCore`, `CkEcs`, `CkLog`, `CkTests` (+ engine `AutomationController`,
`AutomationWorker`, `AutomationTest`, `FunctionalTesting`, `UnrealEd`, `EditorSubsystem`, `Json`).

> **Status: built, run, and verified end-to-end (2026-07-25).** Serves real automation runs both from a headless
> warm server and from an interactive editor. Verified: warm server armed in ~50s and ran 37/37 with zero boot,
> reused across runs, and picked up a `.as` edit (broke an assertion ⇒ it returned the new failure); an interactive
> editor served 37/37 when focused, aborted cleanly at the ready-wait when unfocused (driver falls back), and a
> plain `--test` declines to route into it at all. The `// [VERIFY]` tags below are now runtime-semantic notes
> rather than compile risks.
>
> **Verified in a live interactive session (2026-07-25):** the `ServeMode` default flip to `Off` (the editor no
> longer claims the bridge until opted in), the window-title indicator (`[CkTestBridge: SERVING]` when armed,
> `[CkTestBridge: RUNNING TESTS]` during a run, cleared afterwards — read back off the live window title), and the
> per-frame pump fix (a real-RHI serve-mode editor, minimized, passed the gate at 38.68 FPS in 5s and ran 37/37).
> The throttle suppression is correct-but-inert on this project (`bThrottleCPUWhenNotForeground` is already `False`
> in `Config/DefaultEditorSettings.ini`), so its restore path and ini-safety remain unexercised here — they matter
> only for a host that leaves the setting enabled.

---

## On-disk protocol

`<ProjectSaved>/CkTestBridge/` (all absolute paths, published in `server.json`):

| Path | Role |
|---|---|
| `Requests/<id>.json` | one request from the driver (`op = runTests \| quit`) |
| `Results/<id>.json`  | the verdict — written BEFORE the request is deleted |
| `Progress/<id>.jsonl`| append-only, one JSON object per line, flushed per line |
| `server.json`        | `pid / startedAt / project / protocolVersion:1 / busy / currentRequestId / lastActivityAt` (heartbeat) |

**Request:** `{ "op":"runTests", "requestId":"<guid>", "submitterPid":<int>,
"tests":["<full.dotted.path>", ...], "options":{ "allowDirtyWorld":false,
"perTestStallSeconds":300, "wallClockCapSeconds":3600 } }`

**Result:** `{ "ok":bool, "refused":bool, "refusalReason":null|"pieActive|asPendingFullReload|
asCompileError|dirtyWorld|busy|staleRequest|submitterGone|protocolVersion",
"env":{"live":true,"editorPid":N,"asPendingFullReload":bool,"asCompileErrors":bool,
"dirtyPackages":[...]}, "perTest":[{"path":..,"result":"Success|Failed|Skipped|NotRun",
"durationSec":N,"entries":[{"type":"Error|Warning","message":..}]}], "notFound":[..] }`

**Progress events:** `{"event":"accepted","testCount":N}`, `{"event":"testStarted","path":..}`,
`{"event":"testCompleted","path":..,"result":..,"durationSec":N}`, `{"event":"runCompleted"}`.

---

## Key files

| File | Role |
|---|---|
| `Server/CkTestBridge_RequestProcessor.{h,cpp}` | protocol core (dirs, server.json, one-at-a-time claim, settle guard, **async**: kicks a run and finalizes on a later poll, result-before-request-delete) |
| `Server/CkTestBridge_RunController.{h,cpp}` | the `FAutomationExecCmd` mirror around `IAutomationControllerManager`; ticked by the subsystem (NOT its own ticker/thread); exact `SetEnabledTests`, per-test stall + wall-clock watchdogs, report harvest |
| `Server/CkTestBridge_Preconditions.{h,cpp}` | refusal gate: `pieActive` / `asPendingFullReload` / `asCompileError` / `dirtyWorld` / `busy`; fills the result `env` |
| `Bridge/CkTestBridge_Subsystem.{h,cpp}` | `UEditorSubsystem` ticker that claims `server.json`, defers to a live owner, and drives the processor. IS the warm server under `-CkTestBridgeServe`. |
| `Settings/CkTestBridge_UserSettings.{h,cpp}` | `UDeveloperSettings` (EditorPerProjectUserSettings) `ECk_TestBridge_ServeMode { Off, Allow }` — **default `Off`** |
| `Bridge/CkTestBridge_EditorPresence.{h,cpp}` | the two ways serving REACHES INTO an interactive session: background-throttle suppression (only while a run is in flight, with a crash-recovery marker) and the window-title indicator. No-ops in a headless warm server. |

There is **no** blocking `-ExportServer`-style commandlet. Test runs are asynchronous and the
automation controller must be pumped on the editor game thread, so a `Sleep`-loop would starve it.
The **warm server is the same subsystem** kept alive in a `-unattended` editor by `-CkTestBridgeServe`,
carrying the idle self-quit + wall-clock watchdogs. (CkAssetExporter's synchronous export work made a
blocking loop correct there; it is not here — noted as the deliberate deviation from that template.)

---

## Warm-server launch contract (toolbox-owned)

```
<Editor>.exe <Project>.uproject <AutoTestsMap> -unattended -CkTestBridgeServe -CkAsDeclineRegenOwnership
```

- `-CkTestBridgeServe` — keeps the subsystem serving despite `-unattended` (the inverted guard) and
  arms the idle (~15 min) / wall-clock (~2 h) self-quits. Without it, an unattended/commandlet editor
  is dormant — an ordinary toolbox-spawned test boot must never claim, or it would deadlock the
  driver's own fresh-boot fallback against its own spawn.
- `-CkAsDeclineRegenOwnership` — honored by `CkAngelscriptGenerator`; the warm server declines AS-regen
  ownership so a concurrently-spawned test editor stays PRIMARY for codegen. (This module does not
  implement the flag; the launcher must pass it.)

The interactive live bridge has **no** watchdog (the editor's lifetime is the user's) and serves only when
`Get_ServeMode() == Allow` — an explicit opt-in, **off by default**.

### Why serving from an interactive editor is opt-in and discouraged (measured 2026-07-25)

- **The readiness gate measures OUR poll rate — poll it every frame.** `FWaitForInteractiveFrameRate` (reached via
  `IsReadyForTests()`) samples `TimeNow - LastTickTime` **between successive calls to itself**
  (`AutomationCommon.cpp`), so a 0.5s ticker reports a flat "2 FPS" against its 10 FPS bar however fast the editor is
  really running, and the gate can never open on merit. The subsystem therefore ticks **every frame** while a run is
  active (idle work stays rate-limited to ~0.5s), matching the engine's own `FAutomationExecCmd`.
  Verified in a real-RHI serve-mode editor, **minimized**: `Hit 38.68 FPS for 5 seconds after 5 seconds of waiting`,
  37/37, where the identical setup previously logged `Current FPS=2` for 600s.
  - **Correction to an earlier claim in this file:** "it only works while the editor is FOCUSED" was WRONG. Focus was
    never the variable. The one apparently-focused success was the gate's own 600s `MaxWaitTime` expiring — it logs
    `Game did not reach 10.00 FPS ... Giving up.` and **returns true**, so tests proceed regardless. The wait object
    also accumulates elapsed time across separate requests (it is only cleared on success), which is why logs read
    "Waited 412 seconds" despite each of our runs aborting at 90s. Don't read that as one run's duration.
  - `CkTestBridge_EditorPresence` still suppresses `bThrottleCPUWhenNotForeground` for the duration of a run
    (mirroring `AutomationEditorCommon.cpp:1273`, but restoring afterwards with a crash marker). That is a real lever
    for hosts which leave the setting enabled — **this project already disables it** in
    `Config/DefaultEditorSettings.ini`, so it no-ops here. It cannot rescue a MINIMIZED editor either, since the
    engine throttles via `AreAllWindowsHidden()` regardless of the setting — though the per-frame fix above made
    minimized work anyway.
- **It replaces the user's open level, and nothing restores it.** Automation calls `AutomationLoadMap` per test.
  There is no "provably free" map-scoped mode any more: a project can have several maps named `*AutoTests*` (here
  CkTests' and BusterBlock's), and one `--test-pattern Timer` run spanned **both** — so "already on the AutoTests
  map" never implied "no map operation".
- **The warm server dominates it** on every axis except RAM: no focus dependency (`-nullrhi` ⇒
  `CanEverRender()==false` ⇒ the gate short-circuits), no map hijack, no PIE in the user's window, and it picks up
  `.as` hot-reloads just the same (verified: break an assertion ⇒ the warm server returns the new failure).

---

## `// [VERIFY]` list (could not build/run — verify against 5.7 fork source + a live run)

1. **AngelScript staleness members** (`CkTestBridge_Preconditions.cpp`). Uses the public
   `FAngelscriptManager` members `FileChangesDetectedForReload` / `FileDeletionsDetectedForReload`
   (=> `asPendingFullReload`) and `bDidInitialCompileSucceed` (=> `asCompileError`), guarded by
   `#if WITH_ANGELSCRIPT_CK`. These are public on the 5.7.4 fork (`AngelscriptManager.h:343-347`) but
   the *semantics* (does a non-empty change list truly mean "not yet hot-reloaded"?) are inferred, not
   runtime-confirmed. The truer per-module `bCompileError` / private `QueuedFullReloadFiles` were not
   reachable publicly.
2. **`IAutomationControllerManager` flag set** (`CkTestBridge_RunController.cpp`). `SetRequestedTestFlags`
   is set to `Smoke|Engine|Product|Perf` — the commandline "Standard" mask
   (`AutomationCommandline.cpp:99`). BB functional tests carry `ProductFilter` (covered), but this is
   hardcoded rather than read from the engine's `FilterMaps`.
3. **`SetEnabledTests` matching** (`CkTestBridge_RunController.cpp`). Assumes exact full-dotted-path
   matching against the post-refresh report tree without a prior `SetFilter`. `notFound` is computed
   from `GetEnabledTestNames` after enabling. Group-node (prefix) semantics untested.
4. **Dirty-world heuristic** (`Preconditions.cpp`). The host-agnostic proxy for "the only unsaved work IS the
   AutoTests map automation would open" is a package-name `Contains("AutoTests")`. A host with a differently-named
   automation map must widen this. **RESOLVED for `Subsystem.cpp`:** the serve gate no longer uses this heuristic at
   all — the map-scoped ServeMode was removed (2026-07-25) once it was measured that a project can hold several
   `*AutoTests*` maps and a single run spans them, so being "on the AutoTests map" guaranteed nothing.
5. **Controller tick cadence.** The subsystem ticks at 0.5 s, so the RunController state machine + result
   collection poll at 0.5 s. Test *execution* runs every frame via the local automation worker, so only
   between-test transitions incur up to 0.5 s latency — believed correct but unverified at scale.
6. **`uplugin` platform key.** The new module entry uses `WhitelistPlatforms` to match the two existing
   sibling entries verbatim (the prompt's literal spelling was `PlatformAllowList`, the modern alias);
   both are honored by UBT.

---

## Anti-patterns

- Don't invoke from game runtime — editor-only.
- Don't force-kill a `busy` server (`server.json`) — a run is in flight; killing loses it.
- Don't run more than one request at a time — the processor is deliberately single-flight.
- Don't give the warm server a `Sleep`-loop — it must pump the automation controller on the game thread.
