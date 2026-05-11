# Continuation Prompt — CkIskmRenderer Post-Fix Cleanup & Sibling Audit

**One-line:** 19/19 iskm tests green, gym visually verified end-to-end, two real C++ bugs fixed in CkIskmRenderer + a broad cleanup pass (b-prefix removal, ensure conversion, processor ordering); **next session: commit the CkFoundation submodule changes, then optionally audit the sibling `CkIsmRenderer` for the same processor-ordering bug.**

---

## Repo state

| Path | Branch | State |
|---|---|---|
| `D:/Repos/CkPlugins/` (root) | (project root) | Uncommitted plan-file edits forbidden to commit per user; submodule pointer bumps forbidden per user. |
| `D:/Repos/CkPlugins/Plugins/CkFoundation/` | `feature/ckiskmrenderer-plan-1` | **Uncommitted** — see "Uncommitted CkFoundation changes" below. |
| `D:/Repos/CkPlugins/Plugins/CkTests/` | `feature/ckiskmrenderer-plan-1` | **Uncommitted** — AS-authored wrappers, gym opt-in helper, regression test, all consumers updated. |
| `D:/Repos/BusterBlock/` | (sibling repo) | Not touched this session. Referenced for AS asset patterns (`/Script/CheckoutCounter/BB_CheckoutCounter_Assets.as`, `/Script/BB_Assets.as`). |

**No submodule pointer bumps in CkPlugins root** — user explicitly forbade across multiple sessions. Don't do them. The user will commit and bump when ready.

---

## Uncommitted CkFoundation changes (all in `Plugins/CkFoundation/Source/CkIskmRenderer/`)

These accumulated across the saga, in order of when they landed:

### Bug fixes
1. **Processor group ordering** — `Renderer/CkIskmRenderer_Processor.h` line 20: `FProcessor_IskmRenderer_Setup` moved from `FGroup_Gameplay_Rendering` → `FGroup_Gameplay_Audio`. Within `FGroup_Gameplay_Rendering`, Setup was registered after Proxy by link order, so `IskmProxy_Setup` ran first each tick → ensure-failed → tag dropped → proxy never recovered → A-pose. Moving Renderer one group earlier guarantees actor is ready when any proxy looks. (See `feedback_processor_group_ordering.md` in user memory.)
2. **Try-Remove for forward-compat tag** — `Renderer/CkIskmRenderer_Processor.cpp` ~line 47: `Remove<FTag_IskmRenderer_PendingAsyncLoad>()` → `Try_Remove<>`. Plan-1 never sets this tag, so the unconditional Remove was firing a "tag does not exist" ensure on every Setup. Now silent because the tag is expected-absent.
3. **PlayAnimation re-issue render-proxy desync** — `Proxy/CkIskmProxy_Processor.cpp` ~line 335: guard `SKMC->SetAnimInstanceClass(nullptr)` with `if (SKMC->AnimClass != nullptr)`. Unconditional clear tore down the freshly-created `UAnimSingleNodeInstance` on every PlayAnimation, corrupting the render proxy (visible mesh A-poses on re-issue, but framework signals fire normally — invisible to AutoTests). (See `feedback_iskm_playanimation_reissue.md`.)
4. **HasActiveMontage tag re-trigger** — `Proxy/CkIskmProxy_Processor.cpp` ~line 590: `Add<FTag_IskmProxy_HasActiveMontage>()` now guarded by `if (NOT Has<...>())`. Re-issuing PlayMontage (gym MontageBurst fires every 3s) was hitting the "tag already exists" ensure.

### Schema changes (BPRO → BPRW)
On `UCk_IskmRenderer_Data`, `UCk_IskmAnimCollection_Data`, `FCk_IskmRenderer_MeshDesc`, `FCk_IskmAnimCollection_SequenceDef` — every field that AS-authored asset blocks needed to populate. **Why:** the AS `asset Foo of UType {...}` initializer block writes private UPROPERTY fields via reflection; BPRO rejected the writes, leaving the asset empty post-construction. BPRW fixed it. No functional risk (these are `EditAnywhere` so editor authoring already had write access).

### Code-quality cleanup (most recent)
- **`b`-prefix Hungarian removed** from `FCk_Request_IskmProxy_PlayAnimation`: `_bLoop` → `_Loop`, `_bUnique` → `_Unique`. User explicitly forbids `b` prefix.
- **`TExclude<FTag_IskmProxy_NeedsSetup>`** added to `FProcessor_IskmProxy_HandleRequests`, `_UpdateTransform`, `_EmitFinishedEvents`. Setup-before-consumer guarantee — request handlers can no longer fire on pre-Setup entities. Combined with registration order (Setup is registered first), SKMC is always valid in HandleRequests.
- **Silent-return → `CK_ENSURE_IF_NOT`** across all 12 DoHandleRequest overloads + 4 ForEachEntity methods + `DoApply_AnimInstanceClass`. Intentional silent paths kept and annotated (dedup paths, "no current sequence" early-out in EmitFinishedEvents, "detach already-detached submesh" no-op, "null AnimInstanceClass = sequence mode sentinel").
- **`UCk_Utils_IskmProxy_Diag_UE`** added in `Proxy/CkIskmProxy_Diag_Utils.{h,cpp}` — single method `Get_AnimInstance` for test-only access. Kept out of `UCk_Utils_IskmProxy_UE` to avoid leaking SKMC internals into the public BPFL. Has explicit "diagnostic / test-only" header comment.

---

## Uncommitted CkTests changes (`Plugins/CkTests/Script/CkIskmRenderer/`)

1. **`CkIskmRenderer_Assets.as`** — new file. AS-authored `Asset_AnimCollection_Demo` + `Asset_RendererData_Demo` (`UCk_IskmAnimCollection_Data` / `UCk_IskmRenderer_Data`). Populated via `assets::load::*` against the migrated UE Mannequin content (`/CkTests/Characters/Mannequins/*`). Exposed via `iskm_assets::AnimCollection_Demo()` / `iskm_assets::RendererData_Demo()` accessor namespace — bare `Asset_Foo` symbols aren't visible across `.as` files (see `feedback_as_asset_authoring.md`).
2. **`CkIskmRenderer_GymStation.as`** — added `IskmGym_OptIn_AnimBP(_Proxy)` helper. Called from 5 stations that should idle (SpawnArmy, OutfitSwap, MontageBurst, RagdollDemo, CustomData, AnimBPDemo LEFT). TransitionCycle + AnimBPDemo RIGHT stay in Sequence mode by design. **Wrapper PDA's `_DefaultAnimInstanceClass` is intentionally unset** — ABP_Unarmed isn't a `UCk_IskmNotify_AnimInstance` subclass, and the AutoTest harness escalates the framework warning to a test failure (see `feedback_autotest_warning_escalation.md`). Stations opt in per-proxy; tests stay on the IskmNotify default.
3. **7 test files updated** to use `iskm_assets::RendererData_Demo()` + `assets::load::*` direct refs instead of `LoadAssetByName` paths.
4. **`CkAutoTest_IskmRenderer_PlayAnimationReissue.as`** — new regression test. Asserts `_Proxy.Get_AnimInstance()` pointer identity is preserved across a `Request_PlayAnimation` re-issue. Without the C++ guard fix (#3 above), the SingleNodeInstance gets recreated → pointer differs → test fails.
5. **`CkIskmRenderer_GymPlayerController.as`** — spawns `ACk_Gym_Floor` (40x40x0.5 cube) at gym start so RagdollDemo characters don't fall through the world.
6. **Shared / GymGameMode / Player Controller docs cleaned up** — stale references to the old path-based loading replaced with the AS asset / accessor pattern.

---

## Test status

**19/19 iskm tests green (38–43s).** Includes the new `Ck_AutoTest_IskmRenderer_PlayAnimationReissue` regression test. Run with:

```bash
cd D:/Repos/CkPlugins
./CkAuto/UnrealToolbox.exe --build --config=DebugGame --target=Editor --test --test-pattern iskm --output=Saved/Logs/BuildTest.log --project="D:/Repos/CkPlugins"
```

Pre-flight: probe `Saved/Logs/CkPlugins.log` for exclusive lock — wait if another editor is open.

---

## Gym visually verified

User confirmed in PIE: 7 stations all behave as designed.
- **SpawnArmy** — 5×5 grid, all idling (AnimBP).
- **OutfitSwap** — single proxy, idle + Hat attach/detach cycle.
- **MontageBurst** — single proxy, AnimBP idle + AM_NotifyTest montage every 3s (upper-body only — content limitation of stock ABP_Unarmed's DefaultSlot, see "Known content limitations" below).
- **RagdollDemo** — idle → ragdoll fall onto floor → recovery.
- **CustomData** — idle + material custom-data oscillation.
- **TransitionCycle** — idle ↔ jump alternation every 2.5s (this is the case that surfaced bug #3).
- **AnimBPDemo** — LEFT (AnimBP idle) and RIGHT (sequence mode MM_Idle) both animate.

---

## Open questions for the next session (user-directed work)

1. **Commit the CkFoundation changes.** The submodule has 4 bug fixes + the cleanup pass uncommitted. User will commit when ready; **do not bump pointers in CkPlugins root.** The user will likely want to break this into logical commits (group-ordering fix, BPRO→BPRW schema, PlayAnimation guard, code-quality cleanup, Diag utility).
2. **Commit the CkTests changes.** AS wrappers + gym helpers + tests + the regression test.
3. **Sibling audit — `CkIsmRenderer`.** Same processor-ordering structure as IskmRenderer: `FProcessor_IsmRenderer_Setup` and `FProcessor_IsmProxy_Setup` both in `FGroup_Gameplay_Rendering` with registration order putting Proxy first. Currently appears to work in BusterBlock, but may be relying on lucky timing. Worth applying the same group-move fix preventively. CkEcs auto-detected a similar write-conflict in `Pmg_DebugShape` processors (saw in earlier test output) — that's a separate latent ordering bug.
4. **Document the gotchas.** The user may want a short addendum to `CkIskmRenderer/CLAUDE.md` covering: (a) PlayAnimation re-issue + render-proxy desync (with the SetAnimInstanceClass guard), (b) ABP_Unarmed's DefaultSlot being upper-body-only (montage legs limitation), (c) Setup-before-consumer ordering via tag exclude.

---

## Critical files (most relevant to picking this up)

| File | Purpose |
|---|---|
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Renderer/CkIskmRenderer_Processor.h` | Renderer Setup processor — group is now `FGroup_Gameplay_Audio` |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Renderer/CkIskmRenderer_Processor.cpp` | Renderer Setup impl — uses `Try_Remove` for PendingAsyncLoad |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Proxy/CkIskmProxy_Processor.h` | Proxy processors — HandleRequests/UpdateTransform/EmitFinishedEvents have `TExclude<FTag_IskmProxy_NeedsSetup>` |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Proxy/CkIskmProxy_Processor.cpp` | Proxy handlers — all DoHandleRequest overloads use `CK_ENSURE_IF_NOT`; PlayAnimation guards `SetAnimInstanceClass(nullptr)` with AnimClass check |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Proxy/CkIskmProxy_Fragment_Data.h` | `_Loop`/`_Unique` (was `_bLoop`/`_bUnique`); BPRO→BPRW on fields written by AS asset blocks |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Renderer/CkIskmRenderer_Fragment_Data.h` | BPRO→BPRW on `_AnimCollection`, `_DefaultAnimInstanceClass`, `_Submeshes`, `_NumCustomDataFloat` |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/AnimCollection/CkIskmAnimCollection_Fragment_Data.h` | BPRO→BPRW on `_Skeleton`, `_DefaultMesh`, `_Sequences` |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Renderer/CkIskmRenderer_MeshDesc.h` | BPRO→BPRW on `_Name`, `_GroupName`, `_Mesh` |
| `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Proxy/CkIskmProxy_Diag_Utils.{h,cpp}` | New diagnostic utility — `Get_AnimInstance(proxy)` for tests |
| `Plugins/CkTests/Script/CkIskmRenderer/CkIskmRenderer_Assets.as` | AS-authored wrapper PDAs + `iskm_assets::` accessors |
| `Plugins/CkTests/Script/CkIskmRenderer/CkIskmRenderer_GymStation.as` | 7 stations + `IskmGym_OptIn_AnimBP` helper |
| `Plugins/CkTests/Script/CkIskmRenderer/CkAutoTest_IskmRenderer_PlayAnimationReissue.as` | Regression test — pointer-identity assertion via Diag utility |

---

## Things ruled out (do not re-investigate)

| Ruled out | Why |
|---|---|
| Submodule pointer bumps in CkPlugins root | User forbids across all sessions |
| Co-Authored-By trailers | Forbidden across all commits this branch |
| Generic `_RendererActor` weakptr lifetime issues | Verified — actor is held strongly by `_RendererActors` map in subsystem; weakptr is fine |
| AnimBP's upper-body-only montage as a code bug | It's an ABP_Unarmed graph content limitation (DefaultSlot doesn't cover lower body). Need full-body slot in the AnimBP to fix |
| Single-node SKMC visual playback being inherently broken | Was a teardown-on-re-issue bug, not a single-node mode issue. AnimBPDemo RIGHT proxy plays MM_Idle in pure Sequence mode and renders fine |
| `_DefaultAnimInstanceClass = ABP_Unarmed_Class()` on the wrapper PDA | AutoTest harness escalates the "AnimInstance does not derive from UCk_IskmNotify_AnimInstance" warning to a test failure. Stations opt in per-proxy; wrapper default is null |
| AS member-ref / GC subtlety for `_SeqLoop`/`_SeqNonLoop` in TransitionCycle | Suspected during isolation but ruled out — works fine with members. Was the PlayAnimation re-issue bug, not the ref storage |

---

## Architecture / framework gotchas accumulated this session

### C++ / processor framework
- **Same-group processor order is registration-order, not safe by default.** Within `FGroup_X`, processors run in link-order, not by dependency. Setup-before-consumer pairs need the Setup in an earlier GROUP, AND consumers should `TExclude` the Setup tag. (`feedback_processor_group_ordering.md`)
- **`ck::Context(this)` only works for UObject-derived classes** (Subsystems, Assets, EntityScripts). For plain TProcessor classes, `this` is a raw non-UObject pointer with no registered formatter — the format library can't `ForwarderForPointers` it and the build fails. Omit `ck::Context(this)` in processor ensures; CK_ENSURE_IF_NOT captures file/line context implicitly.
- **`ck::Format` doesn't accept arbitrary `const char*` or raw UObject*** — needs an explicit `CK_DEFINE_CUSTOM_FORMATTER_PTR_FORWARDER` for the type. For UObject pointers in messages, use `GetNameSafe(Ptr)` (returns FString).
- **`SKMC->SetAnimInstanceClass(nullptr)` is destructive even when AnimClass is already null** — it tears down the existing UAnimSingleNodeInstance via ClearAnimScriptInstance(). Always guard with `if (AnimClass != nullptr)` before the redundant clear. (`feedback_iskm_playanimation_reissue.md`)

### CkFoundation specifics
- **AS asset blocks need BPRW (not BPRO) on private UPROPERTY fields they write.** BPRO + `EditAnywhere` lets editor author, but AS reflection requires BPRW for the `_Field = value` writes inside `asset Foo of UType {...}`. (`feedback_as_asset_authoring.md`)
- **AutoTest harness escalates `ck::<module>::Warning` to Error → test fails** even if `FinishSuccess()` was called. Don't put warning-emitting state into shared wrappers used by tests. (`feedback_autotest_warning_escalation.md`)
- **Bare `asset Foo of ...` symbols aren't visible cross-file.** Wrap accessors in a namespace at the bottom of the assets file. (`feedback_as_asset_authoring.md`)
- **`ScriptMixin = "FCk_Handle_X"` makes AS expose static utility methods as instance methods on the handle.** `_Proxy.Get_AnimInstance()` works; `UCk_Utils_IskmProxy_Diag_UE::Get_AnimInstance(_Proxy)` does not (no matching signature error). Auto-generated `utils_X::Foo(handle)` namespace is the canonical call site for non-mixin invocation.

### Style rules surfaced this session
- **No `b` prefix on bool fields** (no Hungarian). `_Loop` not `_bLoop`.
- **`Get_BaseSkmc` not `Get_BaseSKMC`** — acronyms are treated as words. (Hypothetical — wasn't applied because Get_BaseSkmc shouldn't be in public utils anyway.)
- **Header function formatting** — UFUNCTION decls: `UFUNCTION()\n void\n FuncName(\n     args);` (no trailing return type). Non-UFUNCTION decls: `auto\n FuncName(...) -> Type;`. Implementations: full 4-space-indented trailing-return form with class-scope on its own line.
- **Test accessor exposure** — don't add debug/diagnostic accessors to public utils. Make a separate `_Diag_Utils` class (the established precedent now).

---

## Known content limitations (won't fix in code)

- **ABP_Unarmed's montage slot is upper-body-only.** MontageBurst gym station's montage plays on the upper body while the BlendSpace idle drives the legs → visible disjoint pose. Fix is in the AnimBP graph (add a FullBodySlot covering all bones). Not a code bug.
- **ABP_Unarmed doesn't derive from `UCk_IskmNotify_AnimInstance`.** OnAnimationNotify and OnMontageFinished signals won't fire on AnimBP-driven proxies. Gym opts into ABP_Unarmed knowingly (visual is the priority); tests stay on the IskmNotify default to avoid the AutoTest warning escalation.

---

## Recommended diagnostic flow for the next session

### If the user wants to commit (most likely first ask)

1. Run the toolbox once to confirm 19/19 still green from the current state.
2. From `Plugins/CkFoundation`, propose breaking the changes into logical commits:
   - `fix(CkIskmRenderer): processor group ordering + tag exclude — Setup-before-consumer guarantee`
   - `fix(CkIskmRenderer): guard SetAnimInstanceClass(nullptr) against teardown on re-issue`
   - `fix(CkIskmRenderer): Try_Remove for forward-compat PendingAsyncLoad tag; guard HasActiveMontage Add`
   - `refactor(CkIskmRenderer): BPRO→BPRW on PDA fields needed by AS asset blocks`
   - `refactor(CkIskmRenderer): silent-returns → CK_ENSURE_IF_NOT in proxy processor; remove b-prefix from PlayAnimation request fields`
   - `feat(CkIskmRenderer): diagnostic Get_AnimInstance utility for tests`
3. From `Plugins/CkTests`, commit:
   - `test(CkIskmRenderer): AS-authored RendererData_Demo + AnimCollection_Demo wrappers via iskm_assets:: accessors`
   - `test(CkIskmRenderer): gym opts into ABP_Unarmed per-station; collidable floor for RagdollDemo`
   - `test(CkIskmRenderer): PlayAnimation re-issue regression test via Get_AnimInstance pointer identity`
   - `test(CkIskmRenderer): tests + gym use iskm_assets:: accessors instead of LoadAssetByName`
4. Do NOT bump submodule pointers in CkPlugins root.

### If the user wants to audit the sibling CkIsmRenderer

1. Check `Plugins/CkFoundation/Source/CkIsmRenderer/Public/CkIsmRenderer/Proxy/CkIsmProxy_Processor.h` — confirm `FProcessor_IsmProxy_Setup` and `FProcessor_IsmRenderer_Setup` are both in `FGroup_Gameplay_Rendering`.
2. Check registration order in the .cpp `CK_REGISTER_PROCESSOR` calls.
3. If the same pattern as Iskm, apply the same fix (move Renderer Setup to `FGroup_Gameplay_Audio`).
4. Also check the `Pmg_DebugShape` write-conflict warning the build log surfaced — it's a separate latent ordering bug worth flagging.

### If a new symptom shows up

Match against the diagnostic table:

| Symptom | Likely cause | Where to look |
|---|---|---|
| "Tag does not exist" ensure on Iskm Setup | Reverted the `Try_Remove` fix for PendingAsyncLoad | `CkIskmRenderer_Processor.cpp` ~line 47 |
| "Renderer actor missing" ensure on Iskm Proxy Setup | Reverted the group move | `CkIskmRenderer_Processor.h` line 20 (`Group = FGroup_Gameplay_Audio`) |
| TransitionCycle / re-issuing PlayAnimation shows A-pose visually | Reverted the SetAnimInstanceClass guard | `CkIskmProxy_Processor.cpp` ~line 335 |
| "Tag IskmProxy_HasActiveMontage already exists" on MontageBurst | Reverted the Has-check guard around tag Add | `CkIskmProxy_Processor.cpp` ~line 590 |
| Q tests fail with "AnimInstance does NOT derive from UCk_IskmNotify_AnimInstance" | Wrapper PDA's `_DefaultAnimInstanceClass` got set to ABP_Unarmed | `CkIskmRenderer_Assets.as` (should be unset) |
| Setup never runs / boundary tests fail | AS asset block fields not populating | Check BPRO→BPRW on the PDA fields in CkFoundation headers |
| AS test fails with "no matching signatures" calling Diag utility | Called as `UCk_Utils_IskmProxy_Diag_UE::Get_AnimInstance(handle)` | Use mixin pattern: `handle.Get_AnimInstance()` |

---

## Suggested first message to the user

> I've read the continuation prompt. We're at 19/19 iskm tests green with two real bugs fixed (processor group ordering + PlayAnimation re-issue render-proxy desync) plus a code-quality cleanup pass (b-prefix removal, silent-returns → ensures, processor-ordering tag excludes).
>
> The CkFoundation submodule has accumulated uncommitted changes across the saga — bug fixes, schema BPRO→BPRW, the Diag utility. Same for CkTests with the AS wrappers, gym opt-ins, and the regression test. Per your standing rule I haven't touched the submodule pointers in CkPlugins root.
>
> Three obvious next steps: (a) commit the CkFoundation and CkTests changes, (b) audit the sibling `CkIsmRenderer` for the same processor-ordering bug I fixed in Iskm, (c) add a short addendum to `CkIskmRenderer/CLAUDE.md` documenting the gotchas this session uncovered. Which do you want first?
