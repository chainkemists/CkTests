# Authoring recipes 2a-2e

Reference for `ck-tests-authoring-and-running`: add an AS autotest, a net AS autotest, a C++ automation test, a gym, or a Gauntlet test. Pick the layer from the decision table in SKILL.md first.

## 2a. ADD an AS autotest (PIE, single world)

Reference exemplar: `Script/CkAttribute/CkAutoTest_Attribute_IntegerBasic.as`.

1. **Create** `Script/<FeatureModule>/CkAutoTest_<Feature>_<Scenario>.as` — **ONE class per file**
   (both generators key on this). `<Scenario>` names what is *verified* (`IntegerBasic`,
   `MultiOccupant`), never what the code does (`Test1`, `Demo`).
2. **Subclass** `UCk_AutoTest_Base` (`Script/Common/CkAutoTest_Base.as:30`). Override
   `DoBeginPlay(FCk_Handle InHandle)` only — the base owns `DoConstruct` (it writes
   `Running` to the result fragment the C++ runner polls). Base defaults:
   `_TimeoutSeconds = 5.0`, `_NetMode = Standalone`, `_Replication = DoesNotReplicate`.
3. **Declare the test as steps** — the default shape for a linear test:
   - `Add_Step("does something", n"Step_Fn")` — an action. Signature is `FCk_Lambda_InHandle`:
     `UFUNCTION() private void Step_Fn(FCk_Handle InHandle, FInstancedStruct InPayload)`.
   - `Add_Step_WaitUntil("what must become true", n"Check_Fn")` — polls a predicate every frame
     until it holds. Signature is `FCk_Predicate_InHandle_OutResult`:
     `UFUNCTION() private void Check_Fn(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)`.
     **Answer through a local copy** — `auto Res = OutResult; Res.Set(...);` — AngelScript rejects
     `OutResult.Set(...)` on a by-value struct param (Script/CLAUDE.md 9.1); `FCk_SharedBool` is a
     shared cell so the copy writes the same bool.
   - `Run_Steps(InHandle)` at the end of `DoBeginPlay`. The last step finishing passes the test —
     no trailing `FinishSuccess()`, and no `if (IsFinished())` guard in step bodies.
   - **Never wait a fixed number of hops.** How many processor passes an effect needs is a
     property of processor ORDERING, not elapsed time; a hop count bakes that guess into the test
     and silently depends on frame rate. A predicate converges as soon as it is true and, when it
     never is, the failure names the step and the condition.
4. **Branching tests** (net authority splits, signal-driven flows) use the standalone
   `WaitUntil(n"Check_Fn", n"ContinueFn", InFrameBudget = 0)` instead of a step list.
   `ContinueFn` takes the `FCk_Delegate_Timer` signature and may start the next `WaitUntil`.
   `WaitFrames(N, n"ContinueFn")` is the frame-counted twin — use it ONLY when there is no
   observable condition, i.e. when asserting that something does **not** happen.
   **Never convert a settle that guards a NEGATIVE into a condition.** If the test asserts that
   something does *not* happen, or that a value *survives* some event, the naive predicate is
   already true when first evaluated — the wait returns before the event under test occurs and the
   test passes vacuously, which is worse than the flake it replaced. Ask: *if the system did nothing
   at all, would my predicate still be true?* If yes, use `WaitFrames`. In-tree cases deliberately
   left on frame settles: `ObjectPooling_PinnedSurvivesGCThenUnpins` (asserts survival of a GC),
   `EntityTag_RequestTryRemoveAbsentFailed`. Before settling for frames, look for a positive
   observable hiding in the test's own assertions — `Fog_StartsUnexplored` was on this list until
   `Get_CellCounts` going non-zero was recognised as proof the grid composed.
   **A predicate on a SHARED surface must name its own entities.** Every autotest runs in one PIE
   world, so compass/minimap entries and global registries contain *other tests'* data — that is why
   projection tests carry an "Isolated Y band" header. `Get_Entries(_Compass).Num() >= 4` cannot
   distinguish "my four" from "any four" and will release on a neighbouring band's POIs. Scan for
   the test's own handle (or a category tag private to it) instead. This is not hypothetical:
   `Compass_BearingAtCardinalOffsets` failed exactly this way during migration (4 entries projected,
   none its own, 7/9 assertions failed), and six CkMinimap tests carried the same predicate and
   *passed* for several gates before `267bd7e` corrected them — passing is not evidence of soundness
   here. When asserting an EXCLUSION, wait on the entity that must SURVIVE: a broken filter yields
   *extra* entries, satisfying the wait and then failing the existing assertion.
   **Wait on the stage the *assertion* depends on.** A multi-hop settle often spans a cascade of
   processor passes; collapsing it into a predicate for the *first* observable stage releases early
   and fails correct code. `Aggro_OwnerAddThreat_CreatesTarget` gated on the tracked target
   *existing* while asserting the routed threat — the target is born carrying `_InitialThreat` (1.0)
   and the routed 7.0 lands a pass later, so it read 1.0 against a `> 5.0` contract. Ask *which stage
   does my assertion read?* Also: before waiting on a **value** rather than an event, confirm it is
   monotonic in the direction you need — Aggro is safe only because `_ThreatDecayRate` defaults to 0.
   A value that can decay or be re-clamped can miss its window entirely; use the event or a bounded
   frame settle.
   **`WaitOneFrame` is 0.05s of wall-clock, not one frame** (~3 passes at 60fps, 1 at 20fps).
   Deciding a hop stays a settle is only half the decision; **duration is an orthogonal axis**.
   `WaitFrames(N)` is the better instrument when the hop waits for a known number of processor
   passes — but swapping a small N into a window that was tuned against the 0.05s duration
   *shortens* it. `Transform_ForceRefreshRebroadcasts` failed this way: `WaitFrames(2)` let the bind
   and `Request_ForceRefresh` land mid-setup, the refresh was absorbed, and no distinct `OnUpdate`
   broadcast — a working system failed by a shortened stimulus. Same arithmetic keeps the
   CkIskmRenderer `_SettleTicks < 3` loops (three timer fires ≈ 9 passes at 60fps, not 3). Convert
   only when you can say what N counts; otherwise leave `WaitOneFrame` and say why in a comment.
   **Where the feature already broadcasts the transition, bind the signal instead of polling** —
   it fires exactly on the change with no tick race. Reach for `WaitUntil` when no signal exists
   or the condition spans several observables. Precedent:
   `CkAutoTest_Net_Float_Local_AddWorksOnBothWorlds.as` replaced a settle with
   `BindTo_OnValueChanged` after a 0.05s timer raced the override-application processor.
5. **Assert and finish** (verified `CkAutoTest_Base.as`):
   - `Assert_True` / `Assert_False` / `Assert_Equals_Int` / `Assert_Equals_Float(A, E, Tol, Msg)` /
     `Assert_Equals_String` / `Assert_Valid` / `Assert_Invalid` — these count and stash the first
     failure but do **not** finish the test. Failures are auto-tagged with the active step.
   - `FinishSuccess()` / `FinishFailure(Msg)` remain available for early exit.
   - `WaitOneFrame(n"OnSettled")` is **legacy**. It is a 0.05s timer, not a frame wait: it yields
     at least one frame but the frame count scales with frame rate. Retained so unmigrated tests
     compile; do not write new ones.

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

