# Gate 1 — Registry & data model

> **Status:** ✅ Done (2026-08-29)
> **Depends on:** P0 ✅ (three research reports in PROGRESS.md, 2026-08-29)
> **Estimate:** 1 session

## Goal

"After this gate: the gym registry lives in a C++ `UGameInstanceSubsystem` inside CkTests, every
entry carries a Category (and optional HintCode override), all 81 CkTests gyms are categorized,
recents persist per-user, and every existing behavior — registration at GameMode BeginPlay,
ServerTravel, startup auto-travel, HUD suppression, exec commands, BusterBlock's 77 uncategorized
callsites — works exactly as before."

## Entry criteria (pre-flight)

- [x] P0 reports recorded (PROGRESS.md 2026-08-29, three entries).
- [ ] Baseline captured: full-suite fresh-boot run in flight (`Test-Baseline-GymSwitchboard.log`);
      counts to be recorded here before any source edit lands.
- [x] Code shapes spot-checked against doctrine: request/settings patterns mimic
      `UCk_Utils_GymStartup_UE` (existing, in-module); subsystem lifetime decision follows the
      per-GameInstance semantics the AS subsystem already has.

## Locked design (from P0)

- **C++ owns everything the AS `UCkGym_CyclerSubsystem` owned**: registry array, CurrentGymIndex,
  GymLevelName fallback, SuppressHUDDuringStartup, travel, startup resolve. No split-state.
  Per-GameInstance (`UGameInstanceSubsystem`) — NOT a module static (multi-client PIE).
- **`FCkGym_Entry` moves to C++** (USTRUCT, house style `_Fields` + `CK_PROPERTY_GET` +
  `CK_DEFINE_CONSTRUCTORS`), gaining `_Category` (FString) and `_HintCode` (FString, empty =
  derive later). AS struct deleted in the same change (no shims).
- **`CkGym_Cycler.as` namespace stays as a thin facade** forwarding to the C++ utils — all 158
  registration callsites and BB's base GameMode compile unchanged.
- **`RegisterProjectGym(DisplayName, GameModeClass, LevelName = "", Category = "")`** — Category
  APPENDED after LevelName (BB passes LevelName positionally). Empty Category → fallback bucket
  ("Misc") at display time; the stored value stays empty.
- **Recents**: `RecentGymNames` (capped 8, most-recent-first, deduped) on `UCkGym_StartupSettings`,
  pushed from the C++ travel path alongside the existing LastGymName write.
- **Preserve verbatim:** RegisterAll-before-Super ordering, the 0.01s deferred startup travel, the
  synchronous suppress-flag decision, index wrap on travel, dedupe-by-DisplayName idempotency.

## Work items

1. `FCkGym_Entry` USTRUCT + `UCkGym_Registry_Subsystem : UGameInstanceSubsystem` (CkTests
   Source, mimicking `CkGym_StartupSettings.{h,cpp}` file style)
   → verify: compiles; unit test registers 3 entries, dedupes a repeat, wraps travel index.
2. `UCk_Utils_GymRegistry_UE` BPFL — Register / Get_Entries / Get_CurrentGymIndex /
   Request_TravelToGym(Index|Name) / Resolve_StartupGymIndex / suppress accessors — pattern:
   `CkGymStartup_Utils.{h,cpp}` (GetDefault/GetMutableDefault + SaveConfig for settings; subsystem
   lookup via GameInstance for state)
   → verify: AS can call every function the facade needs (test compile of facade).
3. Recents on `UCkGym_StartupSettings` (+ push from travel; read accessor for the menu)
   → verify: unit test — push 10, capped at 8, most-recent-first, dedupe moves-to-front.
4. Rewrite `CkGym_Cycler.as` as facade; delete `CkGym_CyclerSubsystem.as`; update AS read sites:
   `CkGym_Base_GameMode.as` (startup logic), `CkGym_MenuHUD.as` (suppress + registry reads — menu
   itself is replaced in P2/P3 but must keep working until then), `CkGym_ControlPanelHUD.as`,
   `CkVfxExamplesGym_HUD.as` (suppress reads)
   → verify: full AS compile via test boot; gym registration count logged = 81.
5. Categorize the 81 CkTests callsites per CategoryMap.md (module-named categories; singles keep
   per-module categories)
   → verify: unit test or log assert — every CkTests entry has non-empty Category; count 81.
6. NEW INFRASTRUCTURE — unknown: none. Every item replicates an in-module proven pattern.

## Expected observations at the gate

| I will run | I expect to observe | If instead I see | Prewritten response |
|---|---|---|---|
| toolbox `--build --test` (pattern: Gym + full CkTests AS boot) | build green; new unit tests pass; no new AS compile errors | AS compile error on facade | fix spelling against generated `utils_*` wrappers; AS binds are the known risk surface |
| full suite (fresh boot) | counts == baseline | new failures naming gym/HUD tests | bisect: facade read-site rewrite is the likely culprit |
| [EDITOR-VERIFY at P3 checkpoint, not here] | Tab menu still opens and travels (old Canvas menu on new store) | — | — |

## Exit criteria — same commit as last work item

- [x] Build + targeted tests green; full-suite counts vs baseline recorded in PROGRESS.md
- [x] PLAN.md P1 row ✅ + this Status header ✅ — same commit
- [x] PROGRESS.md dated entry with confirmed/inferred split
- [x] CategoryMap.md tombstoned (categories now live in the registry file)
