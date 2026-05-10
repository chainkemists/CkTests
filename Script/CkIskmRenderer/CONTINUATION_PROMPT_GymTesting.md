# Continuation Prompt — CkIskmRenderer Gym Testing (post-content-migration)

**One-line:** CkIskmRenderer Plan-1 is fully implemented and 18/18 AutoTests pass via skip-on-missing-content gates. The user has migrated UE Mannequin content into the CkTests plugin's Content folder; **next session: help test all 7 gym stations + upgrade the 6 Q success-path tests from skip mode to real assertions, iterating on asset-wiring issues as they surface.**

---

## Repo state

| Path | Branch | State | Last commit |
|---|---|---|---|
| `D:/Repos/CkPlugins/` (root) | (project root) | Uncommitted plan-file edits — never committed (user explicitly forbade) | — |
| `D:/Repos/CkPlugins/Plugins/CkFoundation/` | `feature/ckiskmrenderer-plan-1` | Clean | `570fd8f8` (Phase K/I double-event fix + tier table + sandbox cleanup) |
| `D:/Repos/CkPlugins/Plugins/CkTests/` | `feature/ckiskmrenderer-plan-1` | Clean | `cbade4a` (AnimBPDemo gym station) |

**No submodule pointer bumps** in CkPlugins root — user explicitly forbade. Don't do them.

---

## What the user is doing right now

The user just finished migrating a curated subset of the UE Mannequin assets from `D:/Repos/CkPlugins/Content/Characters/Mannequins/` into the **CkTests plugin Content folder** (likely `D:/Repos/CkPlugins/Plugins/CkTests/Content/...`). The migration:
- Pruned the original 128 files / 126 MB down to ~21 files / ~46 MB
- Was driven by a Content Browser delete-filter we iterated on across the conversation
- Final keep set listed below

**The migration is untested.** The next session needs to help validate that the gym + Q tests actually work with this content.

---

## The 21 kept assets (what the user has)

```
SKM_Manny_Simple                  (skeletal mesh)
SK_Mannequin                      (USkeleton — confirmed via /Script/Engine.Skeleton)
PA_Mannequin                      (PhysicsAsset — for ragdoll)
M_Mannequin                       (base material)
MI_Manny_01_New                   (material instance — primary skin)
MI_Manny_02_New                   (material instance — alt skin)
T_Manny_01_BN, T_Manny_01_D, T_Manny_01_MRA   (primary skin textures)
T_Manny_02_BN, T_Manny_02_N, T_Manny_02_D, T_Manny_02_MRA  (alt skin textures)
T_UE_Logo_M                       (UE logo texture)
MM_Idle                           (looping idle anim)
MM_Jump                           (non-looping anim)
MM_ChargedAttack                  (anim — montage source)
MM_Death_Front_01                 (anim)
MF_Unarmed_Walk_Fwd               (locomotion anim)
MF_Unarmed_Jog_Fwd                (locomotion anim — BlendSpace sample)
BS_Idle_Walk_Run                  (BlendSpace driven by ABP_Unarmed)
ABP_Unarmed                       (Anim Blueprint — drives BS_Idle_Walk_Run)
```

**The user's source folder paths (before migration) were under `/Game/Characters/Mannequins/...`. After migration they should live somewhere in the CkTests plugin — but the exact paths may differ from what the gym/tests expect (see below).** Ask the user to LIST what they actually have at `/CkTests/...` before assuming.

---

## What the gym/tests expect (path conventions)

The gym stations and Q tests load via `utils_i_o::LoadAssetByName` from these specific paths (`ECk_AssetSearchScope::Plugins`, `ExactOnly`):

| Path | Expected type | Used by |
|---|---|---|
| `/CkTests/CkIskmRenderer/Demo/RendererData_Demo` | `UCk_IskmRenderer_Data` | All 7 stations + all 6 Q tests |
| `/CkTests/CkIskmRenderer/Demo/AnimCollection_Demo` | `UCk_IskmAnimCollection_Data` | Referenced internally by RendererData_Demo |
| `/CkTests/CkIskmRenderer/Anim/MM_Idle` | `UAnimSequence` (looping) | SpawnArmy, TransitionCycle, AnimBPDemo, TransitionReplaced test |
| `/CkTests/CkIskmRenderer/Anim/MM_Jump` | `UAnimSequence` (non-looping) | AnimationFinishes test, TransitionCycle, TransitionReplaced |
| `/CkTests/CkIskmRenderer/Anim/AM_NotifyTest` | `UAnimMontage` (with ≥1 named notify) | MontageBurst station, MontageNotify test |

**The two wrapper assets (`RendererData_Demo`, `AnimCollection_Demo`) MUST be authored in editor** — the user's migration only brought over the raw UE assets, not these CkFoundation-specific wrappers. Same for the AM_NotifyTest montage (likely needs to be authored from MM_ChargedAttack with a notify track added).

**All other migrated assets (SKM_Manny_Simple, SK_Mannequin, PA_Mannequin, materials, textures, BS_Idle_Walk_Run, ABP_Unarmed, locomotion anims) only need to be at SOME path within the plugin** — they're referenced indirectly via the AnimCollection_Demo's fields. The gym/tests don't load them by path.

---

## Required wrapper asset wiring (engineer steps)

The user needs to do these in the editor **before any gym/test will exercise success paths**:

### `AnimCollection_Demo` (UCk_IskmAnimCollection_Data)
- `_Skeleton` → `SK_Mannequin`
- `_DefaultMesh` → `SKM_Manny_Simple`
- `_Sequences` → at least one entry. For Plan-1 demos: add MM_Idle (loop), MM_Walk_Fwd, MM_Jog_Fwd, MM_Jump (non-loop)

### `RendererData_Demo` (UCk_IskmRenderer_Data)
- `_AnimCollection` → ref to `AnimCollection_Demo` (above)
- `_Submeshes` → **at least one entry with Name = "Hat"** (gym OutfitSwap + Q3 OutfitAttach require it). Mesh field can be SKM_Manny_Simple as a placeholder
- `_NumCustomDataFloat` → ≥ 1 (CustomData station + Q5 test require slot 0 valid)
- `_DefaultAnimInstanceClass` → `ABP_Unarmed_C` (the AnimBP's generated class — needed for AnimBPDemo station's left proxy and SpawnArmy to use the AnimBP path)

### `AM_NotifyTest` (UAnimMontage)
- Author from one of the migrated anims (MM_ChargedAttack is a candidate)
- Add at least one named anim notify event in the montage track

---

## The 7 gym stations (registered in `CkTests_GymRegistry.as` as "IskmRenderer")

1. **SpawnArmy** — 5×5 grid of NPCs at the panel anchor, each gets its own IskmProxy
2. **OutfitSwap** — single proxy, periodic Attach/Detach of submesh named "Hat" (1.5s cycle)
3. **MontageBurst** — single proxy, plays `AM_NotifyTest` montage every 3s
4. **RagdollDemo** — single proxy, alternates Begin/End ragdoll (5s ragdoll, 3s recovery)
5. **CustomData** — single proxy, sin-wave on custom-data slot 0
6. **TransitionCycle** — single proxy, alternates `MM_Idle` (loop) ↔ `MM_Jump` (non-loop) every 2.5s — exercises the Replaced + Completed paths
7. **AnimBPDemo** — TWO proxies side-by-side. Left uses RendererData's `_DefaultAnimInstanceClass` (engineer wires to ABP_Unarmed). Right is forced to Sequence mode via `Request_SetAnimInstanceClass(null)` + plays MM_Idle.

Stations face **world -X** (gym convention — player camera is at -X, +X is behind the panel).

When a station can't find content, it calls `IskmGym_PrintMissingContent("<StationName>")` which puts an on-screen text message naming the missing path. **Use this as the first diagnostic.**

---

## The 18 AutoTests (current state — all green via skip-on-missing-content)

| Test | What it does | Skip condition |
|---|---|---|
| `Ck_AutoTest_IskmRenderer_PdaSmoke` | Phase B PDA construction smoke | none — always runs |
| `Ck_AutoTest_IskmRenderer_SubsystemSmoke` | Phase C subsystem | none |
| `Ck_AutoTest_IskmRenderer_RendererAdd` | Phase D Renderer Add boundary | none |
| `Ck_AutoTest_IskmRenderer_ProxyAdd` | Phase E Proxy Add boundary | none |
| `Ck_AutoTest_IskmRenderer_AnimationPlayback` | Phase F null-safety boundary | none |
| `Ck_AutoTest_IskmRenderer_CustomData` | Phase G null-safety boundary | none |
| `Ck_AutoTest_IskmRenderer_OutfitSubmesh` | Phase H null-safety boundary | none |
| `Ck_AutoTest_IskmRenderer_AnimBP` | Phase I null-safety boundary | none |
| `Ck_AutoTest_IskmRenderer_Montage` | Phase J null-safety boundary | none |
| `Ck_AutoTest_IskmRenderer_Ragdoll` | Phase K null-safety boundary | none |
| `Ck_AutoTest_IskmRenderer_Sockets` | Phase L null-safety boundary | none |
| `Ck_AutoTest_IskmRenderer_AnimationFinishes` | **Q1 success path: Completed event** | Skips if `RendererData_Demo` or `MM_Jump` missing |
| `Ck_AutoTest_IskmRenderer_MontageNotify` | **Q2 success path: notify + montage finish** | Skips if `RendererData_Demo` or `AM_NotifyTest` missing |
| `Ck_AutoTest_IskmRenderer_OutfitAttach` | **Q3 success path: submesh attach increments count** | Skips if no `_Submeshes` entry named "Hat" |
| `Ck_AutoTest_IskmRenderer_RagdollPoseSource` | **Q4 success path: pose-source flips to Ragdoll** | Skips if mesh has no PhysicsAsset |
| `Ck_AutoTest_IskmRenderer_CustomDataSuccess` | **Q5 success path: SetCustomDataFloat round-trips** | Skips if NumCustomDataFloat == 0 |
| `Ck_AutoTest_IskmRenderer_AsyncLoad` | **Q6: post-load Add → Has** | Skips if `RendererData_Demo` missing |
| `Ck_AutoTest_IskmRenderer_TransitionReplaced` | Replaced event when interrupting a still-playing seq | Skips if `RendererData_Demo`, `MM_Idle`, or `MM_Jump` missing |

**Verifying success-path tests are actually running** (not skipping): if you suspect skip mode, the simplest signal is the test runs in <50ms (skip path is just `FinishSuccess()`). Real path takes 200ms-2s. Also check the LogAutomationController test-completed entry's preceding lines for any LogAssertionFailure or actual proxy-spawn output.

---

## Critical files

- `Plugins/CkTests/Script/CkIskmRenderer/CkIskmRenderer_GymStation.as` — all 7 station entity scripts. ~330 lines.
- `Plugins/CkTests/Script/CkIskmRenderer/CkIskmRenderer_GymPlayerController.as` — registers stations + spawns them via `utils_entity_script::Request_SpawnEntity`
- `Plugins/CkTests/Script/CkIskmRenderer/CkIskmRenderer_GymGameMode.as` — 5-line GameMode subclass
- `Plugins/CkTests/Script/CkIskmRenderer/CkIskmRenderer_Shared.as` — gameplay tags (7 entries)
- `Plugins/CkTests/Script/Common/CkTests_GymRegistry.as` — registration line `RegisterProjectGym("IskmRenderer", ACk_IskmRendererGym_GameMode)`
- `Plugins/CkTests/Script/CkIskmRenderer/CkAutoTest_IskmRenderer_*.as` — 18 test files, 6 of which are Q success-path tests with skip gates
- `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Renderer/CkIskmRenderer_Fragment_Data.h` — `UCk_IskmRenderer_Data` field schema (what wrapper assets need)
- `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/AnimCollection/CkIskmAnimCollection_Fragment_Data.h` — `UCk_IskmAnimCollection_Data` schema
- `Plugins/CkFoundation/Source/CkIskmRenderer/Public/CkIskmRenderer/Proxy/CkIskmProxy_Processor.cpp` — Setup processor (line ~99: reads `_DefaultAnimInstanceClass`, applies via `DoApply_AnimInstanceClass`)
- `Plugins/CkFoundation/Source/CkIskmRenderer/Claude.md` — module overview + async-loading section

---

## Diagnostic branch table

| Symptom | Likely cause | Where to look |
|---|---|---|
| Gym station shows on-screen "Missing content" text | The wrapper `RendererData_Demo` doesn't exist at expected path | `IskmGym_LoadRendererData()` in `CkIskmRenderer_GymStation.as`, hardcoded path `/CkTests/CkIskmRenderer/Demo/RendererData_Demo` |
| Station spawns but characters are invisible / T-posed | `AnimCollection_Demo._DefaultMesh` not set, or skeleton mismatch | Open `AnimCollection_Demo` in editor → check Skeleton + DefaultMesh fields |
| Characters render but frozen in default pose | No `_DefaultAnimInstanceClass` set on RendererData (sequence mode) AND no `Request_PlayAnimation` call from the station OR sequences in AnimCollection are empty | RendererData_Demo's `_DefaultAnimInstanceClass`; SpawnArmy doesn't call PlayAnimation, relies on AnimBP |
| OutfitSwap doesn't show submesh swap | RendererData's `_Submeshes` array has no entry named "Hat" | RendererData_Demo `_Submeshes` array |
| MontageBurst doesn't fire / MontageNotify test skips | `AM_NotifyTest` missing, isn't a UAnimMontage, or has no notifies | Author the montage from MM_ChargedAttack |
| RagdollDemo doesn't ragdoll | Mesh has no PhysicsAsset bound, OR PA_Mannequin's skeleton differs from SK_Mannequin | Open SKM_Manny_Simple → check PhysicsAsset field. Open PA_Mannequin → verify it's the right one |
| CustomData has no visible effect | `_NumCustomDataFloat = 0`, or material doesn't read custom-data slot 0 | RendererData_Demo `_NumCustomDataFloat` field; M_Mannequin material must read CustomData slot 0 |
| AnimBPDemo's left proxy looks identical to right | `_DefaultAnimInstanceClass` not set on RendererData (left falls back to UCk_IskmNotify_AnimInstance) | RendererData_Demo `_DefaultAnimInstanceClass` → set to `ABP_Unarmed_C` |
| Q tests "succeed" suspiciously fast (<50ms) | They're hitting the skip-on-missing-content gate, not running real assertions | Test file's DoBeginPlay — early-return on null content. To verify: read the test source, look for `if (ck::Is_NOT_Valid(...)) { FinishSuccess(); return; }` |
| Gym doesn't appear in the Cycler at all | CkTests_GymRegistry.as doesn't have IskmRenderer entry | Already added at line ~33: `RegisterProjectGym("IskmRenderer", ACk_IskmRendererGym_GameMode)` |
| Editor build fails / hot-reload errors | Another Claude session has the editor open, or a stale editor lock | Pre-flight check the editor lock before any toolbox run (the `/build-test` skill has this baked in now) |
| Anim plays but loops back to T-pose periodically | The AnimSequence's looping flag doesn't match the Request_PlayAnimation `bLoop` parameter | The Request struct's bLoop is a runtime override; check the actual sequence asset's `bLoop` setting too |

---

## Things ruled out (do not re-investigate)

| Ruled out | Why |
|---|---|
| Plan-1 architecture changes | Plan is settled. 18 AutoTests passing baseline. Don't refactor module structure |
| Submodule pointer bumps in CkPlugins root | User explicitly forbade across multiple sessions |
| Co-Authored-By trailers | Forbidden across all commits this branch |
| Adding more null-safety boundary tests | Already covered for every public API surface in Phases F-L |
| `DynamicHandleTypes.json` registration | NO-OP for static C++ typesafe handles. The JSON is for `UCkDynamic_HandleDefinition` data assets only. Verified by `utils_iskm_*.as` files appearing in `Plugins/CkFoundation/Script/Generated/` already |
| Sandbox file at `Plugins/CkFoundation/Script/Sandbox/CkIskmRenderer_Sandbox.as` | Deleted in commit `570fd8f8`. Don't re-create |
| Loading AnimBP class via path in AS | Awkward — AS bindings for class-only loading are unclear. AnimBPDemo station relies on RendererData's `_DefaultAnimInstanceClass` instead, which Setup processor applies automatically |
| MasterPoseComponent | Deprecated UE 5.6+; codebase uses LeaderPoseComponent everywhere |

---

## Architecture / framework gotchas accumulated this session

### AS-side
- **AS function params are read-only by-value** — pass `auto Local = InParam;` to wrappers that take non-const refs. Especially for `FCk_Handle&` params being passed into `utils_*` calls expecting `const FCk_Handle &in`.
- **CK_PROPERTY-backed fields aren't exposed as bare names in AS** — use the `Set_Field()` setter or the `CK_DEFINE_CONSTRUCTORS` constructor. Direct `Struct.Field = value` fails to compile.
- **`InHandle.IsValid()` doesn't compile for typesafe handles** — use `ck::IsValid(handle)` / `ck::Is_NOT_Valid(handle)` (free functions).
- **`Cast<UClass>(LoadAssetByName(...)._Asset)` is unreliable for AnimBPs** — the asset registry doesn't surface generated-class objects directly. Workaround used in AnimBPDemo station: rely on RendererData's `_DefaultAnimInstanceClass` (the C++ Setup processor reads it).
- **AS `ck::Is_NOT_Valid(TObjectPtr<X>)` doesn't bind** — when getters return TObjectPtr, AS can't call ck::Is_NOT_Valid on them. The gym/tests sidestep this by using direct UPROPERTY refs (UAnimSequenceBase, UAnimMontage) instead of TObjectPtr-typed accessors.
- **`int32(0)` and `float32(value)` are needed in some Request_* signatures** — AS literal `0` is treated as `int` (not `int32`); `0.5f` is `float` (which AS treats as 64-bit double, not float32). Explicit casts avoid signature-mismatch errors against the `(int32 InOffset, float32 InValue)` wrappers.

### C++ side (recently surfaced)
- **friend class inside `namespace ck` injects forward decls into `ck::`** — when Adaptive Build pulls a .cpp out of unity, the inner `namespace ck { ... Cast<UCk_X>(...) }` resolves to `ck::UCk_X` (incomplete forward decl) instead of the file-scope UCLASS. Workaround: `Cast<::UCk_X>(...)` with explicit global qualifier. Already applied in `CkIskmProxy_Processor.cpp`.
- **Phase K/I double-event hazard** — when a request flips pose-source away from Sequence (Begin Ragdoll, SetAnimInstanceClass), `_CurrentSequence` and `_LastFinishedDispatched` must be cleared to prevent EmitFinishedEvents from firing a spurious `OnAnimationFinished(Completed)` next tick. Fix already applied in commit `570fd8f8`.

### Editor coordination
- **Wait for the editor lock before running the toolbox** — another Claude session may have the editor open. Pattern: poll `Saved/Logs/CkPlugins.log` for an exclusive write lock; if held, sleep 60s and retry. The `/build-test` skill has this baked in now (`C:\Users\sulfu\.claude\commands\build-test.md` → "Pre-flight" section).

---

## Recommended diagnostic flow for the next session

### Phase 1: Verify content placement (5 min)

1. Ask the user to list what they have at `D:/Repos/CkPlugins/Plugins/CkTests/Content/CkIskmRenderer/` (or wherever they migrated to). Get a concrete file/folder listing.
2. Cross-reference against the path conventions table above. The two paths that MUST exist:
   - `/CkTests/CkIskmRenderer/Anim/MM_Idle.uasset`
   - `/CkTests/CkIskmRenderer/Anim/MM_Jump.uasset`
3. The AnimBP `ABP_Unarmed`, BlendSpace `BS_Idle_Walk_Run`, and supporting Walk/Jog anims can be at any path within the plugin — they'll be referenced via the AnimCollection_Demo's fields (created in step 2 below), not loaded by absolute path.
4. **If paths don't match**: either (a) tell the user to rename/move, OR (b) update the AS path strings in `CkIskmRenderer_GymStation.as` + the Q test files. (a) is preferred — fewer files to touch.

### Phase 2: Author the wrapper assets (10 min — engineer-driven)

Walk the user through:
1. Create `/CkTests/CkIskmRenderer/Demo/AnimCollection_Demo.uasset` (UCk_IskmAnimCollection_Data) — populate per the wiring section above.
2. Create `/CkTests/CkIskmRenderer/Demo/RendererData_Demo.uasset` (UCk_IskmRenderer_Data) — populate per the wiring section above. Critical fields: `_AnimCollection`, `_Submeshes` (1+ entries with Name="Hat"), `_NumCustomDataFloat ≥ 1`, `_DefaultAnimInstanceClass = ABP_Unarmed_C`.
3. Create `/CkTests/CkIskmRenderer/Anim/AM_NotifyTest.uasset` (UAnimMontage) — author from MM_ChargedAttack with at least one notify event.

### Phase 3: Re-run AutoTests + verify they're hitting real paths (5 min)

After content is wired:

```bash
cd D:/Repos/CkPlugins
# Pre-flight editor lock; or just use the /build-test skill which does it for you.
./CkAuto/UnrealToolbox.exe --build --config=DebugGame --target=Editor --test --test-pattern iskm --output=Saved/Logs/BuildTest.log --project="D:/Repos/CkPlugins/CkPlugins.uproject"
```

Verify 18/18 still green. Then check Q tests are actually exercising real paths (not skipping):
- `grep -E "Test Started|Test Completed|FinishSuccess" Saved/Logs/BuildTest.log` — look at duration deltas. Q tests in real-path mode take 200ms-2s vs <30ms in skip mode.
- For each Q test, scan the LogAutomationController preceding lines for any actual proxy-spawn / signal-fire log entries. If absent, the test still skipped — content is wired wrong somewhere.

### Phase 4: Run the gym (10-30 min)

1. Open the project in editor.
2. Pick the gym map (the IskmRenderer gym should appear in the Cycler now).
3. PIE start. Cycler advances through the 7 stations on its timer.
4. For each station, verify:
   - **SpawnArmy** — 25 characters in a 5×5 grid behind the panel, all idling
   - **OutfitSwap** — single character with "Hat" submesh attaching/detaching every 1.5s
   - **MontageBurst** — single character plays the AM_NotifyTest montage every 3s
   - **RagdollDemo** — character drops to ragdoll, recovers (5s/3s cycle)
   - **CustomData** — material tint oscillates (requires M_Mannequin to read custom-data slot 0)
   - **TransitionCycle** — character alternates idle ↔ jump every 2.5s
   - **AnimBPDemo** — two characters side-by-side. Left runs ABP_Unarmed (BlendSpace-driven). Right runs MM_Idle in single-node mode.
5. Screenshot each working station. Iterate on broken ones using the diagnostic table above.

### Phase 5: Match expectations to PR description (5 min)

If P4 visual verification was the goal, capture screenshots and add to PR notes. Per Plan-1 wrap-up: 100 entities at 60 FPS (5×5 grid is 25 entities, well within target).

---

## Last commits (reference)

```
CkFoundation submodule (D:/Repos/CkPlugins/Plugins/CkFoundation):
  cbade4a (HEAD)       (in CkTests, see below)
  570fd8f8             fix(CkIskmRenderer): Phase K/I double-event fix + tier-table entry + sandbox cleanup
  ...                  (Plan-1 phase commits A through Q)

CkTests submodule (D:/Repos/CkPlugins/Plugins/CkTests):
  cbade4a              test(CkIskmRenderer): AnimBPDemo gym station (Sequence vs AnimBP side-by-side)
  f1c07be              test(CkIskmRenderer): TransitionCycle gym station + TransitionReplaced AutoTest
  0befbe4              test(CkIskmRenderer): gym + Q tests auto-load content from /CkTests/CkIskmRenderer/Demo/
  4ad2e76              test(CkIskmRenderer): Phase Q success-path AutoTests (6 tests)
  d152f17              test(CkIskmRenderer): gym scaffold (Phase P) - 5 stations registered with cycler
```

---

## Suggested first message to the user

> I've read the continuation prompt. Plan-1 is fully implemented and 18/18 AutoTests pass via skip-on-missing-content gates. You've migrated UE Mannequin content to the CkTests plugin folder, and the next step is to test the 7 gym stations + verify the 6 Q success-path tests actually exercise real assertions (not just skip).
>
> Before I start: can you list what you have at `D:/Repos/CkPlugins/Plugins/CkTests/Content/CkIskmRenderer/` (or wherever the migrated assets actually landed)? I need to cross-reference against the path conventions the gym/tests load from. Specifically the gym/tests look for `MM_Idle`, `MM_Jump`, and (eventually) `RendererData_Demo` + `AnimCollection_Demo` + `AM_NotifyTest`.
>
> Also: have you authored the two wrapper assets yet (`RendererData_Demo` and `AnimCollection_Demo`), or do we need to walk through that first? They're CkFoundation-specific UDataAssets and can't be auto-stamped from AS — engineer-only step.
