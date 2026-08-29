# Gym Switchboard — PROGRESS.md (living log)

## Current state  <!-- supersedes everything below; update at EVERY gate and session end -->
**As of 2026-08-29 (CkTests branch `feature/gym-switchboard`, base = origin/dev @ d18b1ca0):**
P0 in progress — three read-only research agents in flight (gym data flow, input-layer AS recipes,
Slate substrate). Campaign docs authored.
**Baseline being diffed against (captured 2026-08-29, fresh boot, 4 lanes, 5m13s):**
Total 1289 / Passed 1270 / **Failed 19** / Contaminated 0. Failing names (all pre-existing;
crowd+queue reds match the sibling crowd campaign's known in-flight state):
Crowd_Grounding_OffMeshWalkerHolds, Crowd_Grounding_StationaryAgentReGrounds,
Crowd_NarrowGap_NoRouteFailsClean, Queue_CrowdAdapterFacesOrigin,
PathNetworkFollower_DesiredNavmeshClearanceMovesInward, Queue_ClaimFirstTransformProximityReconciles,
QueueCoordinator_CapacityFallbackAndTenQueueDeterminism, Queue_CrowdAdapterMovesAndResumes,
Queue_ReserveDistanceRefreshPerf, QueueCoordinator_ExistingMembershipIsStickyAndInvalidQueuePruned,
SceneNodeTween_{Depth0,Depth1,Depth4}_LeafMatchesExpected, SceneNodeTween_RotationTween_OrientsLeafCorrectly,
SceneNodeTween_NonUniformScalePropagatesToLeaf, SceneNodeTween_TweenLoopYoyo_LeafTracksBoth,
SceneNodeTween_TweenCompletes_LeafLandsAtTarget, SceneNodeTween_RootDestroyDuringTween_ChildrenCleanedUp
(log: Saved/Logs/Test-Baseline-GymSwitchboard.log)
**Next action:** USER-TEST CHECKPOINT — Gate_03's [EDITOR-VERIFY] list in PIE; P4 starts only
after verdicts. P1 ✅ P2 ✅ P2.5 ✅ P3 code ✅ (all 2026-08-29).
**Blocked on:** user PIE verification.
**P3 gate evidence:** full suite 1293 total / 1276 passed / 17 failed — a strict SUBSET of the
19-name baseline (NarrowGap + BunchUp flakes passed this round); zero new failures; all 4 new
tests green (BuildTest-P3b.log). En-route AS fixes: VfxExamples HUD needed 10 member declarations
its clone had been inheriting from the deleted menu; Request_Open/Close needed UFUNCTION for AS
visibility.

## Decision log
| Date | Decision | Why | Revisit when |
|---|---|---|---|
| 2026-08-29 | All four layouts ship, per-user setting, Group Rail default | User decision | never |
| 2026-08-29 | All interaction via CkInput layer stack; pawn + control panel migrate too | User directive; Ck Consume can't mask UE-delivered input | never |
| 2026-08-29 | Widget is visual-only, never takes keyboard focus | Slate writer's direct-viewport-focus gate would starve the pipeline | if CkInput's focus gate ever changes |
| 2026-08-29 | User-test checkpoint = end of P3 (goal hook) | First moment something is PIE-testable end-to-end | — |

## Dated entries (append-only, newest first)

### 2026-08-29 — P2/P2.5 implementation notes (audit of all 7 pawn subclasses)
- Axis-through-layer PROVEN: new `CkAutoTest_InputLayer_AxisEventsReachCapture` green (7/7
  InputLayer battery) — value fidelity both signs, no press-owner recording, no latching.
- P2 C++ landed: `UCkGym_Switchboard_Subsystem` (console `Ck.Gym.Switchboard`, menu layer prio
  1000, catch-all Consume open/close, HitTestInvisible shell w/ CkStyle) + Build.cs deps
  (Slate/SlateCore/InputCore/CkEditorTools).
- P2.5: base pawn keeps ADefaultPawn but `default bAddDefaultMovementBindings = false;` (the b
  prefix STAYS — AS binds this ReadOnly flag as default-assignable under its C++ name; the
  stripped spelling was 'not declared'. CkCameraGym_Pawn:34 was the in-repo precedent all along).
  Pawn layer prio 100: WASD/E/Q/Space/C Consume + MouseX/Y PassThrough (event-driven look).
  Control panel layer prio 500 with per-frame DIFF-synced captures; `Get_PressedRow` polling
  helper deleted (zero callers incl. BusterBlock — verified by grep of both repos).
- Pawn subclass audit (all 7):
  - Probe, Replication, Minimap, Compass: no PAWN Tick override → inherit layer movement
    automatically. (First read mis-attributed Minimap/Compass PLAYERCONTROLLER Ticks to their
    pawns and "fixed" them — reverted; the lesson: check which class in a multi-class .as file
    owns a method before editing it. Cost: two red smoke runs — the 'Namespace Super doesn't
    exist' / 'No matching signatures' errors were both symptoms of calling a pawn method from a
    PC.) The base exposes Tick_StandardMovement() for future subclasses that override Tick and
    still want standard movement.
  - Camera, PixelArt, Playground: bespoke polled movement by design (each already sets
    bAddDefaultMovementBindings=false itself or polls) — they keep their PRE-EXISTING unmaskable
    polling. FOLLOW-UP (not this campaign): migrate each onto its own layer.
- VfxExamples gym HUD keeps its cloned Canvas menu → same follow-up bucket.

### 2026-08-29 — P1 LANDED: registry moved to C++, categories + recents in
- New C++: `FCkGym_Entry` + `UCkGym_Registry_Subsystem` (UGameInstanceSubsystem) in
  CkGym_Registry.{h,cpp}; `UCk_Utils_GymRegistry_UE` BPFL (WorldContext-resolved) in
  CkGymRegistry_Utils.{h,cpp}; `RecentGymNames` (cap 8) on UCkGym_StartupSettings +
  Get_RecentGymNames/Request_PushRecentGym on GymStartup utils; travel pushes recents.
- AS: CkGym_Cycler.as is now a thin facade (RegisterProjectGym gained trailing Category param);
  CkGym_CyclerSubsystem.as DELETED; read sites migrated (Base_GameMode, MenuHUD x3,
  ControlPanelHUD, VfxExamplesGym_HUD); all 81 registrations categorized in CkTests_GymRegistry.as.
- Confirmed (evidence):
  - Build + targeted: 2/2 C++ unit tests (WrappedIndex, RecentsFold) green — BuildTest.log.
  - Facade→BPFL→WorldContext→subsystem round-trip proven at runtime by NEW AutoTest
    `Ck_AutoTest_GymRegistry_FacadeRegisterRoundTrip` (3/3 green incl. dedupe + category
    round-trip) — Test-Editor.log. This was the one silent-failure risk in the design.
  - Full suite: 1292 total (baseline 1289 + our 3) / 1272 passed / 20 failed — Test-P1-Full.log.
    Delta vs baseline: NarrowGap_NoRouteFailsClean flipped green, Crowd_BunchUp_SettlesAtSharedGoal
    flipped red; BunchUp then passed 1/1 in an isolated re-run (Test-BunchUp-Recheck.log) →
    flake in the known crowd cluster, not a regression. Zero failures in anything P1 touched.
- Inferred (unconfirmed): PIE behavior of the old Canvas menu on the new store (Tab open, travel,
  suppress flow) — deferred to the P3 [EDITOR-VERIFY] checkpoint by design.
- One build fix en route: CkTests_Log.h include is `"CkTests/CkTests_Log.h"` (module root path).
- Fix included: the two build-machine-invisible gaps stay for P6 (spec-doc mention of the deleted
  subsystem in CkGym_CreationSpecification.txt:989).

### 2026-08-29 — P0 research report 1/3 (gym data flow) — VERIFIED findings
- **Registry:** `FCkGym_Entry` is AS-declared (`CkGym_Cycler.as:3-26`: DisplayName, GameModeClass,
  LevelName); stored on `UCkGym_CyclerSubsystem : UScriptGameInstanceSubsystem` (per-GameInstance —
  survives ServerTravel, NOT shared across PIE clients). Registration happens at GameMode
  **BeginPlay** (`CkTests_Gyms::RegisterAll()` then `Super::BeginPlay()` — order is load-bearing,
  documented 3x), so a C++ store is timing-safe; **it must be a UGameInstanceSubsystem, not a
  module static** (a static would collapse multi-client PIE instances).
- **81 CkTests + 77 BusterBlock callsites.** BB passes LevelName positionally on nearly every call
  → **Category param must be APPENDED after InLevelName**, never inserted before it.
- **Travel:** `System::ExecuteConsoleCommand(f"ServerTravel {Level}?game={Entry.GameModeClass.Get().GetPathName()}")`
  (`CkGym_Cycler.as:100-102`). Index wraps modulo registry size. LastGymName write =
  `UCk_Utils_GymStartup_UE::Request_Set_LastGymName` at `:98` — **the recents write site**.
- **AS↔C++ settings boundary proven:** `UCk_Utils_GymStartup_UE` BPFL statics over
  `GetDefault/GetMutableDefault<UCkGym_StartupSettings>()` + `SaveConfig()`; AS calls them with
  zero binding work. Template for MenuLayout + recents.
- **Startup quirks to preserve:** travel deferred via `System::SetTimer(0.01)` (PIE bootstrap
  drops BeginPlay travel); suppress-flag decision must land synchronously in BeginPlay;
  `SuppressHUDDuringStartup` is a 3-HUD read protocol (MenuHUD, ControlPanelHUD, VfxExamples HUD).
- **HUD chain:** `ACkGym_MenuHUD` (710-line Canvas menu) ← `ACkGym_ControlPanelHUD` (default
  HUDClass; calls Super::DrawHUD and reads `bMenuVisible` to yield keys) ← VfxExamples HUD (clones
  the menu's interaction model deliberately). Replacing the menu requires rebasing
  ControlPanelHUD off AHUD + giving it an "is switchboard open" query; VfxExamples HUD will
  diverge visually (follow-up, not blocking).
- **Moving FCkGym_Entry to C++** touches 9 AS read sites — most die with the menu rewrite anyway;
  keep `CkGym_Cycler` AS namespace functions as thin forwards so all 158 registration callsites
  and BB's base GameMode keep compiling.
- **Ck_Gym_GoTo** passes raw int, wraps modulo — no name/code form exists; exec extension is greenfield.
- **Two GameModes bypass the registering base** (A-Star — fully authored, NEVER registered;
  Station Showcase — registered but PIE-direct-launch yields an empty menu). Lint target confirmed.
- **Zero automated coverage of the menu** — Slate rewrite is PIE-verified only; plan AutoTests via
  synthetic input injection where feasible.

### 2026-08-29 — P0 research report 2/3 (input-layer AS recipes) — VERIFIED findings
- **Source access:** `UCk_InputSource_Subsystem::Get(PC).Get_InputSource()` — lazy, idempotent,
  invalid until LP+world+PC exist → compose retried from a tick, never one-shot
  (`CkPlaygroundGym_Shared.as:234-245, 264-295`).
- **Layer recipe:** `utils_input_layer::Create(Owner, FCk_Fragment_InputLayer_ParamsData(Source, Prio))`;
  guard priority collision with `TryGet_LayerWithPriority` first (turns the ensure into a
  one-frame wait — `CkPlaygroundGym_Pawn.as:935-944`). Pop = `Request_DestroyEntity` on the layer.
- **Delegate signature (verbatim or it silently never fires):**
  `(FCk_Handle_InputLayer, FCk_InputSource_RawEvent, FCk_InputLayer_Capture)`; bind on the LAYER.
- **Capture edits:** never readable on the calling stack; tests wait on
  `Get_NumCaptures`/`Get_HasCaptureForKey` predicates.
- **Axis events DO match Key captures** (matching ignores event type —
  `CkInputLayer_Processor.cpp:245-260`); axis Consume records no press ownership. **BUT zero
  runtime test coverage exists for axis-through-layer → P2.5 must add an AutoTest before the
  pawn's mouse-look depends on it.** Mouse-axis rows are classified DeviceClass::Keyboard (derived
  from key), MouseX/Y carry raw cursor delta, no-motion writes no row.
- **CkIntent verdict: NOT the pawn substrate.** Its held set updates from every routed event
  "regardless of delivery outcome" (`CkIntentSampler_Processor.cpp:260-296`) — i.e. a menu-layer
  Consume would NOT stop sampler-driven movement. Only matcher press edges respect masking.
  Pawn = dedicated low-priority layer, hand-tracked held set from press/release, mouse look =
  PassThrough captures on MouseX/Y reading `InEvent.Get_AnalogValue()` event-driven (never poll
  conditioned axis state — it holds the last delta forever).
- **Global actions:** `Request_AddGlobalAction(Source, {Key})`; reserved layer created
  synchronously, capture deferred; a Consume above silences it (both legs test-proven). Completion
  owner handle differs on success (layer) vs rejection (source) — don't identify by owner.
- **Injection recipe for menu AutoTests:** compose a SYNTHETIC source on the test's own entity
  (never the subsystem's real one), `Request_InjectRawEvent`; the completion firing IS the drain.
  Deliberate ensures need `Get_ExpectedLogErrors` on a hand-authored wrapper actor.
- **Focus flush contract:** losing direct viewport focus writes synthetic Releases for all
  recorded-down keys; a key still held when focus returns reads as up until re-pressed. The menu's
  held-key repeat must tolerate that (treat Release as repeat-cancel, always).

### 2026-08-29 — P0 research report 3/3 (Slate substrate) — VERIFIED findings
- **Viewport residency recipe:** `ULocalPlayerSubsystem` + `ViewportClient->AddViewportWidgetContent(Widget, ZOrder)`;
  activation from `PlayerControllerChanged` (Initialize is too early), idempotent via
  `if (_RootWidget.IsValid()) return`. Smallest complete exemplar:
  `CkInputHudOverlay/Subsystem/CkInputHud_Subsystem.cpp:184-310`. Overlay exemplar Z-order 100.
- **Visibility:** root uses attribute-bound `HitTestInvisible` (Collapsed under streamer mode via
  CkCore's `ck::diagnostic_visibility::Is_HiddenForStreamerMode()` — free for CkTests).
- **Deps:** CkEditorTools is Runtime/PreDefault, pulls only Slate/SlateCore/DeveloperSettings +
  CkSettings/CkCore. CkTests.uplugin already depends on CkFoundation → **only Build.cs lines
  needed:** `Slate, SlateCore, CkEditorTools` (+`UMG` only if world-projection is used — it isn't).
- **Do NOT depend on CkGameplayDebugger for widget primitives** — CkDebuggerCommon drags 9 Ck
  modules + a plugin dep into every CkTests host; the overlay itself hand-rolls its chips
  (`SCkDebugOverlay_FocusCard.cpp:47-69` records why). Copy the ~15-line chip idiom.
- **Brush idiom:** procedural white `FSlateRoundedBoxBrush` statics tinted at use site —
  `CkStyle::GetRoundedBrush()` 6px / `_Small()` 3px / `_Large()` 8px / `_Pill()` 99px
  (`CkStyle.cpp:169-205`). Bordered chip = nested SBorder (outer border tint, `FMargin{1}`, inner fill).
- **Hue hash exact call:** `FLinearColor::MakeFromHSV8(GetTypeHash(LeafName) % 256, 150, 205)`
  (`FocusCard.cpp:848-858`); chip ink on saturated fill `{0.04,0.07,0.10,1}`; washes via
  `CkStyle::OverlayOf(Color, 0.18f/0.75f/0.95f)`; card glass `OverlayOf(BgRoot(), 0.9f)`.
- **Type:** `CkStyle::RegularFont/BoldFont/MonoFont(Size)` (CkTests-safe; `ck::debug_axes::ScaledFont`
  is debugger-plugin-only). `FontSizeMicro()=8`, Small/Body=9, H3=10, H2=12.
- **SWrapBox trap:** must use explicit `.PreferredSize(width)`, never `UseAllottedSize` when
  recreated outside Tick (`FocusCard.cpp:419-425`). Chip spacing `FMargin{0,0,2,2}`; chip padding `{4,1}`.
- **Pitfalls adopted as constraints:** no `SupportsKeyboardFocus` on the root; if SListView is
  used, `RequestScrollIntoView` not `RequestNavigateToItem`; HitTestInvisible tree can never
  scroll — clip/paginate instead; named file-local namespaces (CkTests builds unity); rebuild-on-
  change model needs deterministic sort tie-breaks (don't copy the overlay's 60Hz full rebuild).

### 2026-08-29 — campaign start
- Created `feature/gym-switchboard` in CkTests off origin/dev (d18b1ca0); submodule was clean.
- Confirmed: `UCkGym_StartupSettings` (EditorPerProjectUserSettings) exists as the per-user
  settings home — CkGym_StartupSettings.h:31.
- Confirmed: CkEditorTools is Runtime T1 hosting CkStyle:: — CkFoundation Source/CLAUDE.md tier
  table — so no token duplication is needed.
- Confirmed: gym pawn is `ADefaultPawn` (engine input bindings) — CkGym_Base_Pawn..as:2 — the
  mechanism of the input-bleed bug.
- Launched three read-only research agents (reports to be appended here).

## Open items
| Item | Status | Next step |
|---|---|---|
| P0 research reports | in flight | append summaries here, resolve into Gate_01 |
| Baseline suite counts | not captured | capture at P1 entry via toolbox |
| Hint-code derivation scheme (stable two-letter codes) | undecided | decide at P1 with registry data in hand |
| Where the per-user recents write happens (travel site) | undecided | research report 1 names the travel site |
