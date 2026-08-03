---
name: ck-tests-authoring-and-running
description: "Use when authoring or running Ck tests: AS PIE or net autotests, C++ automation, gyms, or Gauntlet; also when test rows or filters misbehave. Not for build/binding failures."
---

# ck-tests-authoring-and-running

## Overview

CkTests ships four test pipelines (PIE AS autotests, multi-PIE net AS autotests, hand C++
automation, Gauntlet) plus the interactive gym framework. This skill is the authoring + running
runbook for all of them: pick the layer, follow the file-by-file checklist, run with the right
filter, and gate on real evidence. The plugin is host-agnostic — it defines tests and the harness;
host projects (BusterBlock is the labeled example throughout) own invocation scripts, CI wiring,
and their own maps/configs. Identity, census, and the spec-doc trust table live in
`Plugins/CkTests/CLAUDE.md` — read that first; this skill goes deeper, not wider.

Jargon used once: **AS** = AngelScript (Hazelight fork; language rules in CkFoundation
`Script/CLAUDE.md`); **PIE** = Play-In-Editor; **CDO** = class default object; **entity script** =
`UCk_EntityScript_UE`-derived data-driven logic unit; **wrapper** = the generated
`A<Test>_Actor : ACk_AutoTestRunner` functional-test actor placed in a map. Style/naming for any
code you write: root doctrine `Plugins/CkFoundation/CLAUDE.md`.

## When NOT to use this skill

| Symptom / task | Load instead |
|---|---|
| Build, UHT, linker, or AS-compile failure; packaged-only crash | `ck-debugging-playbook` |
| Engine/plugin setup, environment traps, toolchain | `ck-build-and-env` |
| AS can't see a C++ type/function; binding or generated-file breakage (incl. phantom-namespace recovery) | `ck-angelscript-interop` |
| Adding fragments/processors/handles the test exercises | `ck-macros-and-codegen` |
| "Has this test approach been tried and reverted?" | `ck-failure-archaeology` |

## 1. Layer choice — decision table

Decide by what the assertion needs, not by habit. Paths are relative to `Plugins/CkTests/` unless
marked HOST.

| Layer | Use when the test needs… | Cost per run | Where the file goes |
|---|---|---|---|
| **C++ automation macro test** | no world at all — pure math, formatting, parsers, data shapes | milliseconds, no PIE | `Source/CkTests/Private/UnitTests/<Module>/Test_<Subject>_<Scenario>.cpp` |
| **AS autotest (PIE)** | a ticking ECS world: processors, deferred requests, signals, entity lifecycles (~95% of feature logic) | one PIE boot amortized across the map's tests | `Script/<FeatureModule>/CkAutoTest_<Feature>_<Scenario>.as` |
| **Net AS autotest (multi-PIE)** | client–server: does the value/state replicate | multi-world PIE boot; **C++ rebuild to add a test** | `Script/<FeatureModule>/CkAutoTest_Net_<Scenario>.as` |
| **Gym** | a human's eyes — interactive/visual demo, tuning, manual QA (not automation) | manual PIE session | `Script/<FeatureModule>/` + one registry line |
| **Gauntlet** | a real process: actual boot, real GameMode/input pipeline, exit-code contract | fresh editor boot per run (~minutes) | HOST project's Script tree — this plugin ships the framework only, zero in-plugin tests |

Tests are never authored in Blueprint — anything a BP subclass could add (variant configs,
alternate timeouts) is an AS subclass with `default` overrides (AutoTest spec §11).

The three spec docs (exact filenames, all in `Script/Common/`): `CkAutoTest_CreationSpecification.txt`,
`CkGym_CreationSpecification.txt`, `CkGauntlet_CreationSpecification.txt`. Trust levels + known
stale sections: the table in `Plugins/CkTests/CLAUDE.md` — check it before believing a spec detail
this skill doesn't repeat.


## Reference files — load only what the task needs

Section numbers cited elsewhere in this skill point into these files.

| Topic | Read |
|---|---|
| Authoring recipes 2a-2e | `references/authoring-recipes.md` |
| Golden inventory | `references/golden-inventory.md` |

## 3. RUNNING — command lines by surface

| # | Surface | Command / steps |
|---|---|---|
| 1 | **Editor — Session Frontend** `[EDITOR-VERIFY]` | Tools → Test Automation → Automation tab → refresh → filter (e.g. `Project.Functional Tests` or `Ck.`) → check tests → Start Tests. Failure text from your `Assert_*` messages shows in the details panel under the test tree (drag the split up if collapsed) — this is the primary debugging surface (AutoTest spec §10b). |
| 2 | **Editor — console** | `Automation RunTests Project.Functional Tests` (all placed PIE autotests) · `Automation RunTests Project.Functional Tests.<MapName>` (one map) · `Automation RunTests Ck.<Feature>.Net` (net stubs) · `Automation RunTests CkTests.UnitTests` or `Automation RunTests Ck.<Feature>` (C++ tests, family-dependent) |
| 3 | **Headless / CI — generic (host-invoked)** | `<Editor>-Cmd.exe <Project>.uproject -ExecCmds="Automation RunTests <filter>; Quit" -unattended -nosplash -nullrhi -ReportExportPath=<dir>` — process exit code reflects pass/fail; report dir gets index.html + JSON (spec §10/§10b) |
| 4 | **Gauntlet (host-invoked)** | the §2e command line; gate on `%ERRORLEVEL%`. Every run boots a fresh editor — budget minutes, not seconds |
| 5 | **BusterBlock (labeled host example)** | BB drives builds AND automation runs through its UnrealToolbox (`<BB-root>/CkAuto/UnrealToolbox.exe --build / --test`) — superproject-specific tooling; other hosts wire their own runner around #3/#4 |
| 6 | **Resident editor — the CkTestsBridge live path** (added 2026-07-25) | Run *inside* an already-booted editor instead of paying a fresh boot per run. BB: `--warm-server start` once, then `--test --live`. See below — it changes when you'd pick #3 vs #5. |

### 6 in detail — when to use the live path instead of a fresh boot

The `CkTestsBridge` module (3rd module in this plugin) lets a driver drop a request into
`<ProjectSaved>/CkTestBridge/` and have a **resident** editor run it. Pick by what you're doing:

| Situation | Path | Why |
|---|---|---|
| Claiming "done" / "no regressions"; CI | **fresh boot** (`--test --no-live`) | gate of record — process freshness, as a matter of process |
| Iterating: same tests, repeatedly, while editing `.as` | **warm server** (`--warm-server start` → `--test --live`) | pay the ~50s boot once, then zero per run |
| Iterating but RAM-constrained | the user's open editor — **opt-in only** | costs no second editor, but replaces their open level and does not restore it |

Load-bearing facts, all measured rather than assumed:

- **A test-only run coexists with an open editor.** The hazard is not the run, it is *editing* `.as`
  or source mid-run: the live editor regenerates `Script/Generated/*`, the headless one logs
  `Full Reload is required`, and that error is attributed to whichever test was running. Freeze edits
  for the duration; grep that phrase before believing a red run.
- **The warm server hot-reloads `.as` edits and the very next run uses the NEW bytecode** — verified
  both directions (break an assertion → the run returns the new failure in ~1.8s of recompile; revert
  → green again). No stale-bytecode risk in the iteration loop.
- **Borrowing the user's editor is off by default** and a plain `--test` DECLINES an interactive
  editor even when it is serving; `--live` is required. Verified with `ServeMode = Off`: the bridge
  arms but never claims, and `--live` launches its own warm server instead of borrowing.
- **The win scales INVERSELY with suite size** — ~3.5x on a 37-test pattern (34s vs 2m00s) but only
  ~5% on a full 1262-test suite (19m34s vs 20m30s), because the fixed boot amortises away. Do not run
  a full suite live expecting it to be faster; it is an iteration feature.
- **Fidelity:** a full suite run live and fresh-booted produced **identical failure names**, and no
  measurable state accumulation across runs. That is why #3 stays the gate of record on process
  grounds, not because a divergence is known.
- **Focus is irrelevant** (49s focused vs 52s unfocused). Any older note claiming the editor must be
  foregrounded is a misdiagnosis of the driver's own poll cadence.

Protocol, refusal reasons, and the gotchas: **`Source/CkTestsBridge/CLAUDE.md`**.
BB-side invocation and flags: the `build-test` skill in `CkAuto/.claude/skills/build-test/`.

Filter cheat-sheet: PIE AS autotests are **map-based** (`Project.Functional Tests.<dotted map
path>.<Label>`); net AS autotests and C++ tests are **name-based** (`Ck.<Feature>.Net.AS_*`,
`Ck.<Feature>.*`, `CkTests.UnitTests.*`). Gyms have no automation rows. Gauntlet has no rows —
it's a process exit code.

## 4. EVIDENCE RULES — what counts as green

- **Gate on an artifact you read**, in this order of preference: the `-ReportExportPath` JSON /
  index.html; the per-test verdicts in the log (`LogAutomationController` Test Started/Completed
  lines); the process exit code. A wrapper script's "completed" chatter, or a toolbox
  notification, is a proxy — not evidence.
- **Gauntlet green = process exit code 0.** The `**** TEST COMPLETE. EXIT CODE: N ****` log line
  is emitted engine-side (zero hits for it in this plugin's Source, verified 2026-07-02) — treat
  it as a cross-check, never as the contract you grep for.
- **Stale-binary trap.** Global registrations are baked into the binary at static-init — a green
  run on a binary older than your latest C++ edit is void. Rebuild, re-run the whole gate on the
  final binary (full telling + recovery: CkFoundation's `ck-debugging-playbook`).
- **Net stubs: rebuild before trusting presence OR absence.** A `Ck.<Feature>.Net.AS_*` row only
  reflects your `.as` after the stub regenerated **and C++ rebuilt** (second statement of §2b's
  rule, on purpose). Symmetrically, a deleted net test's row lingers until the generator prunes
  the stub and you rebuild.
- **AS edits silently no-op on failed compile.** The editor keeps running the OLD compiled code.
  Before trusting any run after an `.as` edit, check the fresh log for `Angelscript: Error` /
  `Warning:` lines naming your file (Gauntlet spec §10 — applies equally to autotests and gyms).
- **Record the baseline first.** Before your change: run the target filter, note pass/fail counts
  and the names of failing tests. "No regressions" is only a claim against that recorded list —
  report the delta, and A/B (stash/re-run) any new red before blaming or absorbing it.

## 6. Common mistakes and warnings

- **Two classes in one test `.as` file** (other than the sanctioned hand-authored wrapper pair) —
  both generators key on one-class-per-file.
- **Renaming a test class casually** — orphans the placed wrapper actor in the `.umap` (git
  lesson: revert `604a2d4`). Prefer stable names; let the populator sync.
- **Hand-editing generated files** — `Script/Generated/*` and
  `Source/CkTests/Private/Net/Generated/*` are committed generator output; regenerate via the
  pipeline (AS recompile / editor startup / `Ck.SyncAutoTestMaps`), never edit. Expect them to
  churn in diffs.
- **Assuming `_TimeoutSeconds` works everywhere** — honored for PIE wrappers (CDO propagation),
  ignored by net stubs (hard 30 s, §2b.7), separate meaning in Gauntlet (bridge watchdog).
- **Trusting the stale campaign docs** — `Script/Progress.md`,
  `Script/Common/CONTINUATION_PROMPT_GymStation.md`,
  `Script/CkIskmRenderer/CONTINUATION_PROMPT_{GymTesting,PostFixCleanup}.md` are finished-session
  handoffs from the CkPlugins host era. Not instructions.
- **Reading a gym spec command that doesn't exist** — `Ck_Gym_ShowInfo` / `Ck_Gym_ValidateStations`
  appear only in the spec; the real exec set is in §2d.6.
- **Believing "test ran" proves the code compiled** — see the AS silent no-op rule in §4.

## Provenance and maintenance

Written 2026-07-02 against CkTests detached HEAD `b89f110` (BusterBlock superproject checkout;
engine = UnrealEngine-Angelscript 5.7.x per root doctrine). Every count, line number, flag, and
command above was verified first-hand on that date. Re-verify volatile facts (Git Bash, cwd
`Plugins/CkTests/` unless noted; `rg --no-ignore` is mandatory under `Script/`):

- Census: the six commands in §5.
- Spec filenames: `rg --no-ignore --files Script/Common | grep CreationSpecification`
- Base-class API + defaults: `rg --no-ignore -n '_TimeoutSeconds|_NetMode|WaitOneFrame|Assert_|Finish' Script/Common/CkAutoTest_Base.as`
- Net subject/class knobs: `rg --no-ignore -n '_NetSubjectClass|Get_SubjectEntity' Script/Common/CkAutoTest_NetBase.as`
- Net stub name + fixed timeout: `rg -n 'Ck\.\w+\.Net\.AS_|kTimeoutSeconds' Source/CkTests/Private/Net/Generated/Attribute_NetAutoTestStubs.spec.cpp` and `rg -n '30.0f' ../CkFoundation/Source/CkAngelscriptGenerator/AutoTests/CkAutoTestNetStubGenerator.cpp`
- Populator triggers + label strip: `rg -n 'SyncAutoTestMaps|GetPostCompile|OnFilesLoaded|_Actor' Source/CkTestsEditor/Private/CkAutoTestMapPopulator.cpp`
- Gym exec commands: `rg --no-ignore -n 'UFUNCTION\(Exec' -A 2 Script/Common/CkGym_Base_PlayerController.as`
- Gauntlet flags + exit codes: `rg -n 'asgauntlet|EndTest\(' Source/CkTests/Public/CkGauntletAsBridgeController.h Source/CkTests/Private/CkGauntletAsBridgeController.cpp`
- Pretty-name ruling status: CkFoundation `.claude/reports/ADJUDICATIONS.md` item A2 (interim
  rule in §2c.3 stands until ruled).
