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

## 2a. ADD an AS autotest (PIE, single world)

Reference exemplar: `Script/CkAttribute/CkAutoTest_Attribute_IntegerBasic.as`.

1. **Create** `Script/<FeatureModule>/CkAutoTest_<Feature>_<Scenario>.as` — **ONE class per file**
   (both generators key on this). `<Scenario>` names what is *verified* (`IntegerBasic`,
   `MultiOccupant`), never what the code does (`Test1`, `Demo`).
2. **Subclass** `UCk_AutoTest_Base` (`Script/Common/CkAutoTest_Base.as:30`). Override
   `DoBeginPlay(FCk_Handle InHandle)` only — the base owns `DoConstruct` (it writes
   `Running` to the result fragment the C++ runner polls). Base defaults:
   `_TimeoutSeconds = 5.0`, `_NetMode = Standalone`, `_Replication = DoesNotReplicate`.
3. **Drive and assert** with the base API (verified `CkAutoTest_Base.as:83-177`):
   - `Assert_True(Cond, Msg)` / `Assert_Equals_Int(Actual, Expected, Msg)` /
     `Assert_Equals_String(Actual, Expected, Msg)` — these count and stash the first failure but
     do **not** finish the test.
   - Exactly one terminal call: `FinishSuccess()` (reports Failed if any assertion failed) or
     `FinishFailure(Msg)`. Guard every signal/timer callback with `if (IsFinished()) { return; }`.
   - `WaitOneFrame(n"OnSettled")` (`:165`) — first-class settle helper for deferred side-effects
     (attribute `Request_Override`, stack-count writes, …). Callback signature is
     `FCk_Delegate_Timer`: `void OnSettled(FCk_Handle_Timer, FCk_Chrono, FCk_Time)`. Chain calls
     for multi-stage settles. Don't hand-roll settle timers (spec §7 Pattern B predates this).

```angelscript
// Condensed from Script/CkAttribute/CkAutoTest_Attribute_IntegerBasic.as
class UCk_AutoTest_Attribute_IntegerBasic : UCk_AutoTest_Base
{
    private FCk_Handle_IntegerAttribute HealthAttribute;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Params = FCk_Fragment_IntegerAttribute_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"IntegerAttribute.Health"), 100);

        auto LocalHandle = InHandle;    // utils_*::Add takes a ref param — copy to a local lvalue first
        HealthAttribute = utils_integer_attribute::Add(LocalHandle, Params);

        utils_integer_attribute::BindTo_OnValueChanged(
            HealthAttribute,
            ECk_MinMaxCurrent::Current,
            FCk_Delegate_IntegerAttribute_OnValueChanged(this, n"OnHealthChanged"));

        utils_integer_attribute::Request_Override(HealthAttribute, 42);
    }

    UFUNCTION()
    private void OnHealthChanged(
        FCk_Handle InAttributeOwnerEntity,
        FCk_Payload_IntegerAttribute_OnValueChanged InPayload)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(utils_integer_attribute::Get_FinalValue(HealthAttribute), 42,
            "Health attribute after Override(42)");
        FinishSuccess();
    }
}
```

   Naming note: the on-disk exemplar's `HealthAttribute`
   (`Script/CkAttribute/CkAutoTest_Attribute_IntegerBasic.as:20`) predates the member-naming rule
   and mixes forms within one file (`_Step`, `_OverrideObserved` sit right beside it). Root naming
   applies unchanged in AS (`Script/CLAUDE.md` §20; corpus is ~90% compliant — 727 `_`-prefixed vs
   76 bare private members, 2026-07-02): write `_HealthAttribute`-style `_PascalCase` members in
   NEW tests. The snippet above stays verbatim-faithful to the committed file.

4. **Timeout (optional):** `default _TimeoutSeconds = 2.0f;` on the *entity script* — the wrapper
   generator reads the CDO and propagates it to the generated wrapper, which the runner applies to
   the engine TimeLimit. Exemplar:
   `Script/CkStateMachine/CkAutoTest_StateMachine_RacingEventDrivenTransitions.as:34`. Any doc
   saying "configure timeout on the actor wrapper" is stale.
5. **Expected warnings/errors (optional):** any `Warning`/`Error` log line during a functional
   test fails it. If your test *deliberately* triggers one, hand-author the wrapper — write
   `class A<YourTestClass>_Actor : ACk_AutoTestRunner` in the same `.as` file with
   `default _TestEntityScriptClass = U<YourTestClass>;` and override the
   `Get_ExpectedLogErrors()` BlueprintNativeEvent to return substring patterns (AS can't
   brace-init a `TArray<FString>` via `default`, hence the override). The generator sees the
   conventionally-named class and skips emission — that's the documented opt-out
   (`Plugins/CkFoundation/Source/CkAngelscriptGenerator/AutoTests/CkAutoTestWrapperGenerator.h:17-22`). Exemplar:
   `Script/CkCrowd/CkAutoTest_Crowd_Pathfinding_Failure.as:78`. Related runner knobs:
   `_DisableDefaultLogSuppressions` (`Source/CkTests/Public/CkAutoTestRunner.h:74`).
6. **Save — the machinery does the rest.** On AS PostCompile (and editor startup),
   CkFoundation's `FCkAutoTestWrapperGenerator` emits `A<Class>_Actor : ACk_AutoTestRunner` into
   `Script/Generated/CkTests_AutoTestActors.as`; then `UCkAutoTestMapPopulator` (CkTestsEditor)
   places one wrapper actor per test into the map named by the plugin's `UCkAutoTestMapConfig`
   (`Script/Common/CkTests_AutoTestMapConfig.as` → `Content/AutoTests/AutoTests_CkTests_Level.umap`),
   loading the level off-disk if needed and auto-saving. Populator triggers (all verified in
   `Source/CkTestsEditor/Private/CkAutoTestMapPopulator.cpp`): AS PostCompile (`:69`),
   AssetRegistry first-load (`:81`), console command `Ck.SyncAutoTestMaps` (`:42`).
7. **Find the row.** Automation row = `Project.Functional Tests.<dotted map path>.<Label>` where
   Label is the wrapper class name minus `_Actor` (strip logic `CkAutoTestMapPopulator.cpp:315`).
   BusterBlock-verified example of the map segment: `Project.Functional
   Tests.BusterBlock.Map.AutoTests.AutoTests_BB_MAP`. Refresh Session Frontend's Automation tab to
   see new rows.

**Silent-failure mode to know:** if you delete a test class and later re-add one with the same
name while a stale generated `*_EntitySpawnParams.as` block for it survives on disk, AS silently
fails to register the new class → no wrapper is generated → no map actor → the test **never
appears**, with zero errors. Recover by treating everything under `Script/Generated/` as one
atomic state (regenerate all, or revert all together), or rename the class. Mechanism and
recovery detail: `ck-angelscript-interop` (source doc:
`Plugins/CkFoundation/Source/CkAngelscriptGenerator/Claude.md`, "EntitySpawnParams.as is NOT
resilient to deleted entity-script classes").

**Host projects:** author under your own Script tree and declare your own
`asset <Name> of UCkAutoTestMapConfig { TargetMap = ...; }` pointing at your own `.umap` — the
populator auto-derives the class scope from the config file's location, so plugin and host tests
never cross-populate. BusterBlock example: `Script/Tests/BB_AutoTestMapConfig.as` +
`AutoTests_BB_MAP.umap`.

## 2b. ADD a net AS autotest (multi-PIE)

Reference exemplar: `Script/CkAttribute/CkAutoTest_Net_Byte_OverrideReplicates.as`.

1. **Create** `Script/<FeatureModule>/CkAutoTest_Net_<Scenario>.as`, one class:
   - Cross-world coordination (the common case): subclass `UCk_AutoTest_NetBase`
     (`Script/Common/CkAutoTest_NetBase.as:56`; `default _NetMode = Replicated`). The harness
     spawns an `ACk_AutoTest_NetSubject` actor on the server; every world resolves it via
     `Get_SubjectEntity()`.
   - Per-world isolation (no shared subject): subclass `UCk_AutoTest_Base` directly and set
     `default _NetMode = ECk_AutoTest_NetMode::ServerAndClientsIndependent;`.
2. **The body runs on EVERY PIE world** (server + each client). Branch manually:

```angelscript
// Condensed from Script/CkAttribute/CkAutoTest_Net_Byte_OverrideReplicates.as
UFUNCTION(BlueprintOverride)
void DoBeginPlay(FCk_Handle InHandle)
{
    auto Subject = Get_SubjectEntity();
    if (ck::Is_NOT_Valid(Subject))
    { FinishFailure("subject entity not found"); return; }

    auto Tag = utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Health");
    auto Attribute = utils_byte_attribute::TryGet(Subject, Tag);

    if (utils_net::Get_HasAuthority(Subject))
    {
        utils_byte_attribute::Request_Override(Attribute, 200);   // server mutates…
        FinishSuccess();
        return;
    }

    WaitOneFrame(n"OnPollValue");                                 // …client polls
}

UFUNCTION()
private void OnPollValue(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
{
    if (IsFinished()) { return; }
    auto Subject = Get_SubjectEntity();
    auto Attribute = utils_byte_attribute::TryGet(
        Subject, utils_gameplay_tag::ResolveGameplayTag(n"ByteAttribute.Health"));
    if (ck::IsValid(Attribute) && utils_byte_attribute::Get_FinalValue(Attribute) == 200)
    { FinishSuccess(); return; }
    WaitOneFrame(n"OnPollValue");                                 // keep polling until timeout
}
```

3. Need per-entity setup beyond the default subject? Author a subclass of
   `ACk_AutoTest_NetSubject` with the right entity-script Construct and point
   `default _NetSubjectClass = A<MySubject>;` at it (`CkAutoTest_NetBase.as:64-73`); the generator
   reads it off the CDO and emits the matching spawn.
4. **Recompile AS, then REBUILD C++.** CkFoundation's `FCkAutoTestNetStubGenerator` emits a C++
   orchestration stub per test into `Source/CkTests/Private/Net/Generated/
   <Feature>_NetAutoTestStubs.spec.cpp`. **The stub is a `.cpp` — a C++ rebuild is REQUIRED before
   the new (or renamed) test exists as an automation row. An AS recompile alone is NOT enough**
   (unlike pipeline 2a). When a net test "doesn't exist", check this first — it is the least
   discoverable fact in the whole pipeline.
   - Stub destination is chosen so the committed stub lands in the SAME git repo as its `.as`
     (project-authored → `<Project>/Source/<Project>/Tests/Net/Generated/`; plugin with its own
     C++ module → that plugin; everything else → CkTests). The hosting module must depend on
     `CkTests`. Rationale + exact rules: `Plugins/CkFoundation/Source/CkAngelscriptGenerator/
     AutoTests/CkAutoTestNetStubGenerator.h:16-45`.
5. **Row name:** `Ck.<Feature>.Net.AS_<Scenario>` (verified in
   `Source/CkTests/Private/Net/Generated/Attribute_NetAutoTestStubs.spec.cpp:51`); flags
   `EditorContext | ClientContext | EngineFilter`. `<Feature>` derives from the source path
   (`Script/Ck<Feature>/` or `Tests/<Feature>/`; fallback `AS`).
6. **Results aggregate per world** — failures surface prefixed `Server` / `Client[N]`
   (`Source/CkTests/Private/Net/CkNetAutomation_Common.cpp:529`).
7. **Timeout caveat:** the per-world AS-run deadline in every generated stub is a hard-coded
   `30.0f` (`CkAutoTestNetStubGenerator.cpp:266`; every stub on disk carries it, verified
   2026-07-02). `default _TimeoutSeconds` on your class is **not** propagated to net stubs —
   design your client-side polling to converge well inside 30 s.

## 2c. ADD a hand-written C++ automation test

Reference exemplar: `Source/CkTests/Private/UnitTests/Math/Test_CkValueRange_IntRange.cpp`.

1. **Create** `Source/CkTests/Private/UnitTests/<Module>/Test_<Subject>_<Scenario>.cpp`. Multiple
   test macros per file are fine. No world, no `FCk_Handle`, no ticking — if you need those, go
   back to 2a.
2. **Macro family:** `IMPLEMENT_SIMPLE_AUTOMATION_TEST` (complex variants are available but the
   corpus is simple-only). **Zero `DEFINE_SPEC`/`BEGIN_DEFINE_SPEC` anywhere in the plugin**
   (verified 2026-07-02) — `.spec.cpp` in `Private/Net/` is a naming convention, not the spec
   framework.
3. **Class + pretty name:**

```cpp
#include "Misc/AutomationTest.h"
#include "../CkUnitTest_Common.h"

using ck::tests::kCkUnitTestFlags;   // EditorContext | ClientContext | ProductFilter

IMPLEMENT_SIMPLE_AUTOMATION_TEST(
    FCkTest_IntRange_Clamping,
    "CkTests.UnitTests.Math.IntRange.Clamping",
    kCkUnitTestFlags)

bool FCkTest_IntRange_Clamping::RunTest(const FString& Parameters)
{
    const auto Range = FCk_IntRange{0, 100};
    TestEqual(TEXT("Value below min clamps to min"), Range.Get_ClampedValue(-50), 0);
    return true;
}
```

   Style note: the `bool F...::RunTest(const FString&)` definition shape is the engine
   automation-macro contract and corpus-uniform (`Test_CkValueRange_IntRange.cpp:31,51,87`) — a
   sanctioned exemption from root doctrine's trailing-return rule; don't "fix" it in style review.

   Pretty-name rule (interim, pending the A2 ruling in CkFoundation
   `.claude/reports/ADJUDICATIONS.md`): **join the existing prefix of the feature family your test
   sits next to** (`CkTests.UnitTests.<Module>.<Subject>.<Scenario>` for the older half,
   `Ck.<Feature>.*` for the newer half); **greenfield features use `Ck.<Feature>.*`** — the
   direction both generators already enforce.
4. **Flags:** reuse `ck::tests::kCkUnitTestFlags` from `Private/UnitTests/CkUnitTest_Common.h`
   (an `inline constexpr` in a named namespace — do NOT re-declare your own file-local copy; two
   anonymous-namespace constants collide under unity build, the exact incident that header
   documents). Net specs use `EngineFilter` instead of `ProductFilter`; follow your family.
5. Rebuild C++; the row appears under the pretty name. No map, no generator involvement.

## 2d. ADD a gym (interactive station — manual/visual, not automation)

Reference exemplars: `Script/CkAttribute/CkAttributeGym_BasicAttributes.as` (station entity script
with auto-mode) and any `ACk_*Gym_GameMode` in the registry. Framework spec:
`Script/Common/CkGym_CreationSpecification.txt` — but note its §3 layout (`Script/CkGyms/`) and
§9 commands (`Ck_Gym_ShowInfo`/`Ck_Gym_ValidateStations`) never matched reality; trust this
checklist.

1. **Files live co-located in `Script/<FeatureModule>/`** next to that feature's autotests (there
   is no `Script/CkGyms/` directory).
2. **GameMode:** subclass `ACkTests_Gym_Base_GameMode` (`Script/Common/CkTests_Gym_Base_GameMode.as`
   — its BeginPlay calls `CkTests_Gyms::RegisterAll()` then `Super::BeginPlay()` for startup-gym
   auto-travel). Set your PlayerController class; pawn base is `ACk_Gym_Base_Pawn`.
3. **PlayerController:** subclass `ACk_Gym_Base_PlayerController` and override
   `Get_RequiredStations()` (return `TArray<FCkGym_Station_SpawnParams_Payload>`; stations
   auto-spawn in a default grid when transforms are identity) and `Request_StartGym()` (your
   startup logic). Useful base API (`Script/Common/CkGym_Base_PlayerController.as:74-253`):
   `Get_StationHandle(Tag)`, `Get_StationTransform(Tag)`, `Set_StationTitleAndDescription(...)`,
   `Get_StationAnchorLocation(Tag, Anchor)` (PanelCenter is the default anchor; FootprintCenter
   for nav/physics gyms). Auto-mode: `gym_auto::Setup(...)` + `FCkGym_AutoConfig`
   (`Script/Common/CkGym_AutoStation.as`).
4. **Register** in `Script/Common/CkTests_GymRegistry.as` (keep alphabetical):
   `CkGym_Cycler::RegisterProjectGym("My Feature", ACk_MyFeatureGym_GameMode);` — optional third
   arg is a level name (`CkGym_Cycler.as:43`; dedupes by display name). Host projects register in
   their own registry via their own base GM (BusterBlock: `Script/Gyms/BB_Gyms_Registry.as` +
   `ABb_Gym_Base_GameMode`).
5. **Level:** `Content/TestGyms/TestGyms_CkTests_Level.umap`. PIE there; the Tab menu lists
   registered gyms.
6. **In-PIE exec commands** (exact names — verified
   `Script/Common/CkGym_Base_PlayerController.as:255-287`; the DisplayNames differ, don't type
   those): `Ck_Gym_Restart`, `Ck_Gym_Next`, `Ck_Gym_Prev`, `Ck_Gym_GoTo <index>`, `Ck_Gym_List`.
7. `[EDITOR-VERIFY]` Gym checks are inherently visual: PIE in the gym level → press Tab → your
   gym's display name appears in the menu → travel to it → stations spawn in a grid and the
   BP_DemoDisplay panels render your title/description → run the exec commands above from the
   `~` console and watch the cycler respond.

## 2e. ADD a Gauntlet test (real-process boot; HOST-side)

This plugin ships the framework only — `UCk_GauntletAsBridgeController : UGauntletTestController`
and `UCk_GauntletAsTest_Base : UObject` — and **zero** in-plugin tests. Hosts author test classes,
dispatcher scripts, and maps. Read `Script/Common/CkGauntlet_CreationSpecification.txt` first
(fully current, audited 2026-07-02); internals doc: `Source/CkTests/Gauntlet_ARCHITECTURE.md`.

1. **Author (in the HOST project's Script tree)** one AS class:

```angelscript
// Shape from Source/CkTests/Public/CkGauntletAsTest_Base.h:15-27
class UCk_MyGame_GauntletAsTest_Foo : UCk_GauntletAsTest_Base
{
    UFUNCTION(BlueprintOverride)
    void OnAsInit() { Controller.Request_MarkHeartbeat("foo init"); }

    UFUNCTION(BlueprintOverride)
    void OnAsTick(float32 InDelta)
    {
        if (Controller.Get_FirstPlayerController() != nullptr)
        { Controller.Request_EndTest(0); }
    }
}
```

   Hooks: `OnAsInit`, `OnAsTick`, `OnAsPostMapChange`, `OnAsStateChange`
   (`CkGauntletAsTest_Base.h:61-71`). Tunables via `default`:
   `_RequirePlayerControllerOnInit` (default true — OnAsInit waits for PC+Pawn; `:80`) and
   `_TimeoutSeconds` (default 30; bridge watchdog fires EndTest(1) on expiry; `:90`).
2. **Bridge API** (call via `Controller.`): `Request_EndTest(Code)`, `Request_MarkHeartbeat`,
   `Request_ExecConsoleCommand`, `Get_FirstPlayerController`, `Get_BoundImcCount`,
   `Request_InjectInputForAction` (Enhanced Input injections are NOT sticky — re-inject every
   tick), `Request_WatchLogSubstring` / `HasObservedLogSubstring` (case-sensitive substring,
   thread-safe). All in `Source/CkTests/Public/CkGauntletAsBridgeController.h:56-131`.
3. **Invoke** (flag names verified against `CkGauntletAsBridgeController.h:17-18` +
   `.cpp:116,128`; PowerShell — drop the backtick continuation for cmd/bash):

```powershell
<Editor>-Cmd.exe <Project>.uproject <Map> -game -nullrhi -unattended `
    -gauntlet=Ck_GauntletAsBridgeController -asgauntlet=UCk_MyGame_GauntletAsTest_Foo
```

   Optional: `-asgauntlet-waitsec=<n>` extends the 5 s wait for the AS class to register
   (`.cpp:128`, default `_AsClassWaitTimeoutSeconds = 5.0f` at `.h:169`).
4. **Exit codes** (the contract; all sites verified in `CkGauntletAsBridgeController.cpp`):
   **0** pass · **1** AS test failed or watchdog timeout (`:185`) · **2** no `-asgauntlet=` on the
   command line (`:121`) · **3** NewObject failed (`:289`) · **4** AS class never registered —
   usually your `.as` failed to compile (`:171`). Non-zero codes are forced through a
   TerminateProcess backstop so `%ERRORLEVEL%` is trustworthy (`.h:137-145`).

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

## 5. Golden inventory (as of 2026-07-02, CkTests HEAD `b89f110`)

No hand-written registry exists; the committed generated artifacts + gym registry ARE the census.

| Kind | Count | Canonical list |
|---|---|---|
| AS PIE autotests | **~502** = 432 generated wrappers + 70 hand-authored-wrapper files | `Script/Generated/CkTests_AutoTestActors.as` |
| Net AS autotests | **34** `.as` files → **34** tracked stub entries (a working tree may show more — the generator drops untracked stubs for host-authored tests mid-flight; 38 on disk at count date) | `Source/CkTests/Private/Net/Generated/*_NetAutoTestStubs.spec.cpp` |
| Hand C++ automation | **195** macros (automation macros in `Source/` minus the generated net stubs — 195 either way you slice tracked vs on-disk) | the `UnitTests/`, `CkSnapshot/`, `Net/` trees |
| Gyms | **43** registrations | `Script/Common/CkTests_GymRegistry.as` |
| Gauntlet tests in-plugin | **0** (framework only) | hosts own the tests |

Re-derive (Git Bash, cwd `Plugins/CkTests/`; the repo-level `.ignore` blinds plain grep tooling
under `Script/` — always `rg --no-ignore` there):

```bash
rg --no-ignore -c '^class A\w+_Actor : ACk_AutoTestRunner' Script/Generated/CkTests_AutoTestActors.as
rg --no-ignore -l '^class A\w+_Actor : ACk_AutoTestRunner' Script --glob '!**/Generated/**' | wc -l
rg --no-ignore --files Script | grep -c 'CkAutoTest_Net_'
rg -c 'IMPLEMENT_\w*AUTOMATION_TEST' Source/ | awk -F: '{s+=$2} END {print s}'          # use this exact pattern — plain 'IMPLEMENT_' also catches IMPLEMENT_MODULE (+2)
rg -c 'IMPLEMENT_\w*AUTOMATION_TEST' Source/CkTests/Private/Net/Generated/ | awk -F: '{s+=$2} END {print s}'
rg --no-ignore -c 'CkGym_Cycler::RegisterProjectGym' Script/Common/CkTests_GymRegistry.as
```

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
