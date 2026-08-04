# CLAUDE.md — CkTests

Test infrastructure for the Ck plugin suite: the AutoTest harness (single-world PIE + multi-PIE
net), the Gauntlet AS bridge, the interactive Gym framework, and this plugin's own test corpus.
**Framework rules (style, naming, macros, non-negotiables): see
[CkFoundation/CLAUDE.md](../CkFoundation/CLAUDE.md)** — nothing from it is restated here.
Facts marked with a date were verified against code/disk on that date.

## Identity (verified 2026-07-02)

- `CkTests.uplugin` — **3 modules** (updated 2026-07-26): **CkTests** (Runtime, Default) +
  **CkTestsEditor** (UncookedOnly, Default) + **CkTestsBridge** (UncookedOnly — the live-editor test
  bridge; see its own [CLAUDE.md](Source/CkTestsBridge/CLAUDE.md)). Win64/Mac/Linux,
  `CanContainContent: true` (ships the autotest + gym levels).
- Plugin deps: CkFoundation, CommonUI, GameplayAbilities, **Gauntlet**. Module deps add
  **FunctionalTesting**, EnhancedInput, and ~44 Ck modules (`Source/CkTests/CkTests.Build.cs`).
- **Host-agnostic.** Consumed by multiple superprojects (BusterBlock and CkPlugins are both known
  hosts); ships **zero runner scripts** (no `.bat`/`.ps1`/`.sh` anywhere in the plugin). Hosts own
  invocation, CI wiring, and the maps/configs for their own tests.
- The AS wrapper/stub **generators do NOT live here** — both sit in CkFoundation at
  `Source/CkAngelscriptGenerator/AutoTests/` (`CkAutoTestWrapperGenerator.{h,cpp}`,
  `CkAutoTestNetStubGenerator.{h,cpp}`). This plugin owns the runtime harness
  (`ACk_AutoTestRunner`, result bridge, AS base classes) and the editor map populator.

## The four test pipelines (verified 2026-07-02)

| # | Pipeline | Author writes | Machinery | Automation rows |
|---|---|---|---|---|
| a | PIE AS autotests (~500) | one `UCk_AutoTest_Base` subclass per `.as` | wrapper generator → map populator | `Project.Functional Tests.<map>.<label>` |
| b | Multi-PIE net AS autotests (~34) | one `UCk_AutoTest_NetBase` subclass per `.as` | net stub generator → **C++ rebuild** | `Ck.<Feature>.Net.AS_<Scenario>` |
| c | Hand-written C++ automation (195) | `IMPLEMENT_*AUTOMATION_TEST` .cpp | none | split — see A2 below |
| d | Gauntlet (0 tests in-plugin) | AS test class in the HOST project | bridge controller + `-asgauntlet=` | process exit code |

### a. PIE AS autotests

- Author `Script/<FeatureModule>/CkAutoTest_<Feature>_<Scenario>.as` — ONE class, subclassing
  `UCk_AutoTest_Base` (`Script/Common/CkAutoTest_Base.as:30`; defaults `_TimeoutSeconds = 5.0`,
  `_NetMode = Standalone`).
- On editor startup and every AS recompile, CkFoundation's `FCkAutoTestWrapperGenerator` emits
  `A<Class>_Actor : ACk_AutoTestRunner` wrappers into `Script/Generated/CkTests_AutoTestActors.as`
  (432 wrappers at count date; runtime `FSoftClassPath` resolution so a deleted test self-heals).
  A `default _TimeoutSeconds` CDO override on the entity script propagates into the wrapper.
- `UCkAutoTestMapPopulator` (CkTestsEditor) places one wrapper actor per test into the
  `UCkAutoTestMapConfig` map — here `Content/AutoTests/AutoTests_CkTests_Level.umap` via
  `Script/Common/CkTests_AutoTestMapConfig.as` — loading the level off-disk if needed and
  auto-saving. Triggers: AS PostCompile (`CkAutoTestMapPopulator.cpp:69`), AssetRegistry
  first-load (`:81`), console `Ck.SyncAutoTestMaps` (`:42`).
- Rows appear as `Project.Functional Tests.<map>.<class-minus-_Actor>` (label strip: `:315-316`).
  Refresh Session Frontend's Automation tab to see new rows.

### b. Multi-PIE net AS autotests

- Author `Script/<FeatureModule>/CkAutoTest_Net_<Name>.as` subclassing `UCk_AutoTest_NetBase`
  (`Script/Common/CkAutoTest_NetBase.as:56`; `default _NetMode = Replicated` — server spawns an
  `ACk_AutoTest_NetSubject`, body runs on every world, branch on authority via
  `Get_SubjectEntity()`), or set `default _NetMode = ECk_AutoTest_NetMode::ServerAndClientsIndependent`
  on a plain Base subclass (no subject; per-world isolation).
- CkFoundation's `CkAutoTestNetStubGenerator` reads `_NetMode` off the CDO and emits
  `Source/CkTests/Private/Net/Generated/<Feature>_NetAutoTestStubs.spec.cpp`.
- **The stubs are C++ — a C++ REBUILD is required before a new or renamed net test shows up.**
  AS recompile alone is NOT enough (unlike pipeline a). This is the least-discoverable fact in
  the whole pipeline; when a net test "doesn't exist", check this first.
- Test names: `Ck.<Feature>.Net.AS_<Scenario>`.

### c. Hand-written C++ automation

- 195 hand-written macro tests at count date (233 `IMPLEMENT_*AUTOMATION_TEST` total in `Source/`
  minus 38 in generated net stubs on disk — 34 of those in tracked stubs, +4 from 3 untracked
  BusterBlock-authored stub files present at count date; a clean checkout reproduces 34 and the
  same 195). **Zero `DEFINE_SPEC` anywhere** — `.spec.cpp` is a naming convention only, every
  test is macro-based.
- Layout: pure unit tests `Source/CkTests/Private/UnitTests/<Module>/Test_<Subject>_<Scenario>.cpp`;
  snapshot suite `Private/CkSnapshot/`; hand-written net specs `Private/Net/`.
- Pretty-name family is SPLIT: older tests use `CkTests.UnitTests.<Module>.*`, newer roughly half
  use `Ck.<Feature>.*`. **Interim rule (final ruling pending — see
  [CkFoundation ADJUDICATIONS item A2](../CkFoundation/.claude/reports/ADJUDICATIONS.md)):** new
  tests follow the existing prefix of the feature family they join; greenfield features use
  `Ck.<Feature>.*` (the direction both generators already enforce).

### d. Gauntlet (framework only)

- This plugin ships the framework, not tests: `UCk_GauntletAsBridgeController : UGauntletTestController`
  + `UCk_GauntletAsTest_Base : UObject`. Zero gauntlet test classes exist in-plugin — hosts author
  them, along with dispatcher scripts and maps.
- Invocation contract (host-owned): `<Editor>-Cmd.exe <Project>.uproject <Map> -game -nullrhi
  -unattended -gauntlet=Ck_GauntletAsBridgeController -asgauntlet=<ASClass>`
  (`CkGauntletAsBridgeController.h:18`).
- Exit codes: 0 pass; 1 fail/timeout; 2 missing `-asgauntlet` (`.cpp:121`); 3 NewObject failed
  (`:289`); 4 AS class never registered — usually an AS compile failure (`:171`; wait window
  tunable via `-asgauntlet-waitsec=<n>`). Non-zero codes force-exit via `TerminateProcess` so
  `%ERRORLEVEL%` is trustworthy (the WM_QUIT trap and rationale: `Source/CkTests/Gauntlet_ARCHITECTURE.md`).

### Gyms (interactive stations — manual/visual, not automation)

Framework in `Script/Common/` (`ACk_Gym_Base_GameMode`/`_PlayerController`/`_Pawn`, Tab-menu
cycler + HUD, station display via BP_DemoDisplay). Station step sequences are CkStateMachine
graphs — one `UCk_Gym_StepState` subclass per step, dwell gated by `UCk_Gym_Dwell`
(`Script/Common/CkGym_StationSm.as`); the HUD highlights the SM's live current state, so the
displayed sequence cannot drift from what is running. `gym_auto`'s `AutoStep % TotalSteps`
if-else dispatch is the superseded shape, retained while stations migrate one at a time — its
`FCk_Message_Gym_AutoSet` is still the shared transport for the `Ck_Gym*_Auto` console toggle. Canonical gym list =
`Script/Common/CkTests_GymRegistry.as` — **43** `RegisterProjectGym` calls (verified 2026-07-02).
Gym scripts are co-located per feature in `Script/<FeatureModule>/` — there is **no**
`Script/CkGyms/` directory (stale spec claim). Level: `Content/TestGyms/TestGyms_CkTests_Level.umap`.
In-PIE exec commands (`Script/Common/CkGym_Base_PlayerController.as:255-287`): `Ck_Gym_Restart`,
`Ck_Gym_Next`, `Ck_Gym_Prev`, `Ck_Gym_GoTo <index>`, `Ck_Gym_List`.

## Authoring rules (plugin-specific)

- **One class per test `.as` file** — both generators key on this.
- **Scenario names state what is VERIFIED** (`IntegerBasic`, `RacingEventDrivenTransitions`,
  `Byte_ModifierAddReplicates`), never what the code does (`Test1`, `Demo`).
- **Timeout lives on the entity script**: `default _TimeoutSeconds = X.Xf;` (base default 5.0,
  `CkAutoTest_Base.as:42`); the generator propagates it to the wrapper CDO. Any doc saying
  "configure timeout on the actor wrapper" is stale — that includes the AutoTest spec §6 wording.
- **Settling**: declare the test as steps — `Add_Step` / `Add_Step_WaitUntil` / `Run_Steps`, or
  the standalone `WaitUntil(n"Predicate", n"Continue")` for branching flows. Wait on a NAMED
  CONDITION, never a fixed number of hops: how many processor passes an effect needs is a property
  of processor ordering, not elapsed time, so a hop count bakes a guess into the test and depends
  silently on frame rate. A wait that never resolves names the step and condition that were
  pending instead of dying as an anonymous engine `TimesUp`. Predicates answer through a local
  copy (`auto Res = OutResult; Res.Set(...)`) — AngelScript rejects a non-const call on a by-value
  struct param. `WaitOneFrame` is legacy (a 0.05s timer, not a frame wait), retained so unmigrated
  tests compile.
- **Don't rename test classes casually** — a rename orphans the placed wrapper actor in the .umap
  (git history: revert `604a2d4`). Let the populator sync, and prefer stable names.

### Choosing a wait — the five rules

Each came from a test that PASSED or FAILED for the wrong reason during the 2026-08 sweep. Full
rationale + the incident behind each: `Script/Common/CkAutoTest_CreationSpecification.txt` and the
`ck-tests-authoring-and-running` skill (recipe 2a). Ask these in order before converting a settle:

1. **Would my predicate still be true if the system did nothing?** If yes it is a NEGATIVE — an
   "exactly once", a "does not fire", a "survives X" — and it CANNOT become a condition. It is
   already true on arrival, so the wait returns before the event under test happens and the test
   passes vacuously. Keep the settle; what makes the silence meaningful is a POSITIVE assertion
   before it proving the machinery ran.
2. **Does my predicate name MY entities?** Every autotest shares one PIE world, so compass/minimap
   entries and global registries hold other tests' data. `Get_Entries(X).Num() >= 4` cannot tell
   "my four" from "any four". Scan for the test's own handles or a tag private to it.
3. **Which stage does my ASSERTION read?** Gate on that stage, not the first observable one. A
   cascade's early stage can be live while the value the assertion reads is still the default.
4. **Is the value monotonic in the direction I need?** A value that can decay, re-clamp, or be
   overwritten can miss its window. If it isn't monotonic, wait on the EVENT instead.
5. **Has this file already been converted, and how long is the window?** `git log` + grep for
   existing `Check_` predicates first: re-pointing a hop at an already-true predicate silently
   DELETES a settle. And `WaitOneFrame` is **0.05s of wall-clock, not one frame** (~3 passes at
   60fps, 1 at 20fps) — swapping in `WaitFrames(N)` with a small N SHORTENS it. Convert only when
   you can say what N counts; otherwise keep `WaitOneFrame` and say why in a comment.

A settle you cannot justify is not a defect to be fixed — converting it is how you delete a real
wait. When you keep one, record the reason in the file so the next pass does not "finish the
migration" and reintroduce the flake.

### The spec documents and their trust levels (audited 2026-07-02)

| Doc (`Script/Common/`) | Trust |
|---|---|
| `CkGauntlet_CreationSpecification.txt` | **Fully current** — read first for anything Gauntlet. |
| `CkAutoTest_CreationSpecification.txt` | **Core current** — §5's template is the step-sequencer shape and the wait rules are documented in full (2026-08). **Known gaps**: the net layer (pipeline b) is entirely undocumented; §6 timeout wording superseded by the `_TimeoutSeconds` CDO mechanism; `_ExpectedLogErrors` missing; §14 naming rule superseded by ADJUDICATIONS A2. |
| `CkGym_CreationSpecification.txt` | **Core verified, stale bits**: §3's `Script/CkGyms/` layout never matched reality (co-located per feature); §9's `Ck_Gym_ShowInfo`/`Ck_Gym_ValidateStations` don't exist in code — actual commands listed above. |

## Running tests (host-invoked)

This plugin defines tests; hosts run them. Generic shapes (AutoTest spec §10):

- Editor console: `Automation RunTests Project.Functional Tests[.<filter>]`
- Headless/CI (host-invoked): `<Editor>.exe <Project>.uproject -ExecCmds="Automation RunTests
  Project.Functional Tests; Quit" -unattended -nosplash -nullrhi [-ReportExportPath=<dir>]`

BusterBlock (one known host) drives builds and runs through its UnrealToolbox; other hosts wire
their own. Full runbooks, test anatomy, and evidence rules: the **`ck-tests-authoring-and-running`
skill** (this plugin's `.claude/skills/` — authored in campaign Phase 2).

### Running tests INSIDE an already-open editor (the CkTestsBridge live path)

Since 2026-07-25 a host driver can run automation **in a resident editor instead of booting a fresh
one per run** — the `CkTestsBridge` module serves a file-drop protocol under
`<ProjectSaved>/CkTestBridge/`. Two server kinds, and the choice matters:

| You want | Use | Cost |
|---|---|---|
| Gate evidence / a "done" or "no regressions" claim | **fresh boot** (BusterBlock: `--test --no-live`) | ~45-50s boot per run |
| Fast repeated runs while iterating | **warm server** — a headless `-CkTestBridgeServe` editor (`--warm-server start`, then `--test --live`) | one ~50s boot, then zero |
| Same, but you cannot spare RAM for a second editor | **your own open editor**, opt-in only | it replaces your open level and does NOT restore it |

- **A test-only run coexists with an open editor** — that is verified, not assumed. The hazard is
  editing `.as`/source mid-run (the live editor regenerates `Script/Generated/*`, the headless one
  logs `Full Reload is required`, and the error lands on whatever test was running). Freeze edits for
  the run's duration.
- **Borrowing the user's editor is off by default** (`ECk_TestBridge_ServeMode::Off`) and a plain
  `--test` deliberately DECLINES an interactive editor even when it is serving — routing into one
  requires an explicit opt-in on both sides. Verified 2026-07-27: with `ServeMode = Off` the bridge
  arms but never claims, and `--test --live` launches its own warm server rather than borrowing.
- **Measured, so nobody oversells it:** the live path's win scales *inversely* with suite size —
  ~3.5x on a 37-test pattern (34s vs 2m00s), but only ~5% on a full 1262-test suite (19m34s vs
  20m30s), because the fixed boot amortises away. It is an **iteration** feature.
- Verdict fidelity was measured, not assumed: a full suite run live and fresh-booted produced
  **identical failure names**. State does not measurably accumulate across runs — but a fresh boot
  remains the gate of record as a matter of process, not because a divergence is known.

Full protocol, refusal reasons, and the load-bearing gotchas: **[CkTestsBridge/CLAUDE.md](Source/CkTestsBridge/CLAUDE.md)**.
Host-side invocation (BusterBlock): the `build-test` skill in `CkAuto/.claude/skills/build-test/`.

## Warnings

- `Script/Progress.md`, `Script/Common/CONTINUATION_PROMPT_GymStation.md`, and
  `Script/CkIskmRenderer/CONTINUATION_PROMPT_{GymTesting,PostFixCleanup}.md` are **stale
  finished-session campaign docs** from the CkPlugins host era — do not treat as current
  instructions (recommend-deletion note lives in the campaign report).
- `Script/Generated/*` and `Source/CkTests/Private/Net/Generated/*` are **committed generated
  artifacts** — regenerate via the pipeline (AS recompile / editor startup), never hand-edit;
  expect them to churn in diffs.

## Provenance and maintenance

Written 2026-07-02 against detached HEAD `b89f110`. Re-verify volatile facts before trusting them
much later (run from the plugin root; the Grep tool is blind under `Script/` — superproject
`.ignore` — so use `rg --no-ignore`):

- Census: `rg -c 'IMPLEMENT_\w*AUTOMATION_TEST' Source/` (sums to 233; a plain `'IMPLEMENT_'`
  pattern also catches the 2 `IMPLEMENT_MODULE` lines → 235) vs the same pattern over
  `Source/CkTests/Private/Net/Generated/` (38 on disk / 34 tracked);
  wrappers `rg --no-ignore -c '^class A.*_Actor : ACk_AutoTestRunner' Script/Generated/CkTests_AutoTestActors.as`;
  gyms `rg --no-ignore -n 'RegisterProjectGym' Script/Common/CkTests_GymRegistry.as` (2 hits are comments).
- Spec filenames: `rg --no-ignore --files Script/Common | grep CreationSpecification`.
- Populator triggers: `rg -n 'SyncAutoTestMaps|PostCompile|OnFilesLoaded' Source/CkTestsEditor/Private/CkAutoTestMapPopulator.cpp`.
- Gym exec commands: `rg --no-ignore -n 'UFUNCTION\(Exec' -A 1 Script/Common/CkGym_Base_PlayerController.as`.
