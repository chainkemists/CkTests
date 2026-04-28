# GymStation continuation prompt

I'm continuing debugging work on `UCk_EntityScript_GymStation` in CkFoundation/CkTests. Read this fully before doing anything. **A screenshot of the GOAP Auto-Replan station with debug overlays + the output-log dump from PIE will be pasted alongside this prompt.** That's the immediate diagnostic data — start there.

---

## Repo state

- Outer: `D:\Repos\CkPlugins`, branch `dev`
- CkTests submodule: `D:\Repos\CkPlugins\Plugins\CkTests`, branch `feature/navigation` — **lots of uncommitted local changes**
- CkFoundation submodule: branch `feature/navigation`
- CkGameplayDebugger submodule: branch `dev`

The GymStation work was rebased onto `origin/dev` earlier in the prior session; only one trivial conflict (binary `.umap` rewind from a `CkGym_AllTests → TestGyms_CkTests_Level` rename upstream) was resolved by accepting the deletion.

---

## The active bug

**The GOAP Auto-Replan gym station shows a Y-axis size mismatch between its body pieces.** Specifically: the **floor extends much further along Y (the alcove width direction) than the back wall** — the user confirmed the floor sits at the geometric centre of the back wall but extends far past it on either side. Top trim, bottom trim, side trims, and back wall all appear to share one (small) Width, while the floor has a larger Width.

**It only manifests on GOAP Auto-Replan.** No other gym shows this. The differentiator: GOAP is the only gym in the project that calls `CkGym_Common::Update_StationDisplay` every tick with a long multi-line description (~500-600 chars across ~13 lines, longest line ~50 chars). All other migrated gyms either don't push runtime updates or push very short ones.

GOAP is therefore the only gym that exercises the **runtime-grow path** — `Refit_FromMeasuredBounds` → `Resize_Alcove` → `Update_BodyTransforms` → six `utils_scene_node::Request_UpdateOffset_*` calls per body piece.

The bug is somewhere in that grow/resize plumbing. It does **not** affect initial Build — pieces match at construction time.

### Things already ruled out

1. **Old heuristic Refit treating the entire fragment description as one line.** Fixed: replaced with `Refit_FromMeasuredBounds` that reads `UTextRenderComponent::GetTextLocalSize()` for actual rendered bounds.
2. **`Get_OwningEntity().As_SceneNode()` chain unreliability.** Refactored: each visible piece now has its own stored `FCk_Handle_SceneNode` field (`_BackWallSCN`, `_FloorStageSCN`, `_LeftTrimSCN`, `_RightTrimSCN`, `_TopTrimSCN`, `_BottomTrimSCN`, `_TitleSCN`, `_DescriptionSCN`, `_FloorDescriptionSCN`, `_SpotlightSCN`). `Resize_Alcove` walks them directly via `utils_scene_node::Request_UpdateOffset_Location/Scale/Rotation` — no derivation, no per-piece variance.
3. **High-water-mark stickiness from the buggy heuristic.** User confirmed mismatch persists after a full PIE stop+play cycle.

### Suspect hypotheses to investigate (in order)

1. **`UTextRenderComponent::GetTextLocalSize()` returns unexpected values.** If it returns world-scaled bounds, returns coordinates in a different convention than I assumed (`.X` for horizontal width, `.Z` for vertical height), or returns NaN/Inf when text isn't yet rendered — `Refit_FromMeasuredBounds` would compute a wrong `RequiredW` and grow `Width` to a huge value. **The print log dump should reveal this immediately.**
2. **`Request_UpdateOffset_Scale` doesn't propagate consistently across SceneNode children.** Possible if some pieces have a different SceneNode setup (one parented differently from the others). Unlikely since all body pieces use the same `Spawn_StaticMeshPiece` helper.
3. **`Apply_AutoSize_FromSpawnParams` math being inconsistent.** Sets Width and Height at construction; should affect all pieces uniformly through Build_Body.
4. **PushTransform processor processes some pieces but not others.** Would mean SCN updates are happening but not reaching the SMC for some pieces. Hard to verify without deeper instrumentation.

---

## Diagnostics now in place (the data the user is pasting)

Two diagnostic features are wired in and enabled on the GOAP Auto-Replan station:

### Debug overlay PMG boxes

When `ShowDebugOverlays = true` on a station's spawn params, `Build_DebugOverlays` (called from `DoConstruct`) and `Rebuild_DebugOverlays` (called from `Update_BodyTransforms` after a resize) draw translucent wireframe PMG boxes at each body piece's **expected** world transform (computed straight from `InitialTransform.TransformPosition(LocalOffset)` + half-extent math).

Colour key:
- 🔴 Red — back wall
- 🔵 Blue — floor stage
- 🟡 Yellow — top trim
- 🟠 Orange — bottom trim
- 🔷 Cyan — left trim
- 🟣 Magenta — right trim

If a piece's actual rendered geometry sits *inside* its overlay box, that piece's transform is correct. If the geometry extends past the overlay, its transform is bigger than expected. If it sits inside but the overlay is way bigger than the piece, the math computed something extreme.

### Print statements

Gated on `ShowDebugOverlays`:

In `Refit_FromMeasuredBounds`:
```
[GymStation Refit] TitleSize={...}  DescSize={...}  Required=(W, H)  Current=(W, H)  NeedsGrow=true|false
```

In `Update_BodyTransforms`:
```
[GymStation Resize] Width={W}  Depth={D}  Height={H}
[GymStation Resize]   BackWall: loc={...} scale={...}
[GymStation Resize]   FloorStage: loc={...} scale={...}
[GymStation Resize]   LeftTrim: loc={...} scale={...}
[GymStation Resize]   RightTrim: loc={...} scale={...}
[GymStation Resize]   TopTrim: loc={...} scale={...}
[GymStation Resize]   BottomTrim: loc={...} scale={...}
```

### What to look for in the pasted log

1. **`TitleSize` / `DescSize` values from Refit.** Sanity-check `.X` (horizontal width in cm) and `.Z` (vertical height in cm). If `.X` is in the thousands for ~50-char text at scale 12, `GetTextLocalSize` is reporting world-scaled bounds, not local — heuristic axis assumption is wrong.
2. **`RequiredW` from Refit.** Should land around 4-7 units for GOAP's text. If it's 30+, that's how Width grew huge.
3. **`scale` values per piece in Resize.** Every body piece should have `scale.Y = Width` (back wall, floor, top trim, bottom trim) or `scale.Y = WT/100` (left trim, right trim). If scales differ unexpectedly, the math itself is wrong. If all scales match but the rendered geometry doesn't match, `Request_UpdateOffset_Scale` isn't propagating.

### What to look for in the screenshot

- Compare each colored overlay box vs the actual piece geometry. The piece that DOESN'T match its overlay is the broken one.
- Specifically: blue overlay (floor) vs the actual floor SMC. If the overlay is small (correct expected size) but the SMC is huge, the SMC scale isn't being updated. If both match (both huge), `Width` itself was grown to a huge value — likely a `GetTextLocalSize` axis-or-units issue.

---

## Architecture summary (current, post-big-bang)

`UCk_EntityScript_GymStation` lives in `Plugins/CkTests/Script/Common/CkGymStation_EntityScript.as`. Pure ECS — no Actor.

Construction:
1. `DoConstruct(InHandle)` →
   - `Apply_AutoSize_FromSpawnParams()` if `AutoSize=true` (heuristic from `TitleText` + `DescriptionText` TArray — components don't exist yet)
   - `utils_transform::Add(InHandle, InitialTransform)`
   - `Build_Body(StationTH)` — creates 6 SceneNode children (back wall, floor, 4 trims), each with `UStaticMeshComponent` attached via `utils_unreal_component::Add`. Stores SCN handles in `_*SCN` fields and component handles in `_*Handle` fields. Default cube mesh + `CreateDynamicMaterialInstance(0)` with `"Color"` parameter for body/trim tinting.
   - `Build_Text(StationTH)` — 3 SceneNode children for `UTextRenderComponent`s (title, description, floor description).
   - `Build_Spotlight(StationTH)` — 1 SceneNode child for `USpotLightComponent`.
   - `Build_Anchors(StationTH)` — 7 SceneNode children for the named anchors (FootprintCenter, AgentSpawn{Front,Back,Left,Right}, PanelTopFront, PanelCenter).
   - `Populate_AnchorsFragment(InHandle)` — writes a snapshot `FCkGym_Station_Anchors` fragment with all 7 anchor world positions, computed from `InitialTransform × LocalOffset`.
   - Optional: `Build_AnchorVisuals` (PMG spheres on each anchor SCN if `ShowAnchors=true`).
   - Optional: `Build_DebugOverlays` (the PMG box overlays described above if `ShowDebugOverlays=true`).
   - Tags the station entity via `utils_entity_tag::Add` for each tag in `StationTags`.
   - Starts a tick timer for `OnDisplayTick` (the fragment watcher).

Runtime display updates:
- Director gym scripts call `CkGym_Common::Update_StationDisplay(SelfEntity, title, description, instructions)`.
- Implementation in `Plugins/CkTests/Script/Common/CkGym_Utils.as`: walks up the lifetime owner from `SelfEntity` to find the station entity, then writes a `FCkGym_Station_TitleAndDescription` fragment on it.
- `OnDisplayTick` polls that fragment each tick, comparing to cached values. On change, calls `Apply_TitleText` / `Apply_DescriptionText` / `Apply_FloorDescriptionText` which read the `_*Handle` UnrealComponents, cast to `UTextRenderComponent`, and call `SetText`.
- After Apply_*Text calls, if `AutoSize=true`, calls `Refit_FromMeasuredBounds` which reads `GetTextLocalSize()` from title + description components, computes required Width/Height with grow-only semantics, and calls `Resize_Alcove` if needed.
- `Resize_Alcove` walks all stored SCN handles and applies new local transforms via `utils_scene_node::Request_UpdateOffset_*`. PushTransform processor pushes the new world transforms onto the components next tick.

Cross-gym anchor lookup:
- `ECk_GymStation_Anchor` enum (FootprintCenter, AgentSpawn{F/B/L/R}, PanelTopFront, PanelCenter).
- `ACk_Gym_Base_PlayerController::Get_StationAnchorLocation(InTag, EAnchor)` reads the snapshot `FCkGym_Station_Anchors` fragment via `utils_entity_tag::ForEach_Entity` lookup → returns FVector.
- `Get_StationAnchorTransform(InTag, EAnchor)` composes `FTransform(stationRotation, anchorLocation)` for callers that need the full transform.
- 21 gym PCs migrated from `Get_StationTransform(InTag)` → `Get_StationAnchorTransform(InTag, ECk_GymStation_Anchor::PanelCenter)`. Navigation gym alone keeps `Get_StationTransform` (FootprintCenter equivalent) since its agents path on the floor.

---

## Critical files

- `Plugins/CkTests/Script/Common/CkGymStation_EntityScript.as` — the EntityScript itself. Where the bug is. Has all the Refit / Resize / Update_*Transforms / debug-overlay machinery.
- `Plugins/CkTests/Script/Common/CkGym_Utils.as` — `CkGym_Common::Request_SpawnNewStation` (spawns the EntityScript directly with payload params) and `Update_StationDisplay`. `FCkGym_Station_SpawnParams_Payload` lives here.
- `Plugins/CkTests/Script/Common/CkGym_Base_PlayerController.as` — `Get_StationHandle/Transform/AnchorLocation/AnchorTransform` + `Set_StationTitleAndDescription`. Drives station spawning via `Request_EnsureStationsExist`.
- `Plugins/CkTests/Script/CkGoap/CkGoapAutoReplan_GymPlayerController.as` — the gym exhibiting the bug. Has `AutoSize=true` + `ShowDebugOverlays=true` on its station payload.
- `Plugins/CkTests/Script/CkGoap/CkGoapAutoReplan.as` — the EntityScript spawned at the station; calls `CkGym_Common::Update_StationDisplay` with the long multi-line status text every tick (around line 499).

---

## AS / framework gotchas accumulated this session

1. **`Cast` is a reserved AS keyword.** Use `entity.As_NavAgent()` / `entity.As_SceneNode()` / `entity.As_Transform()` for typed-handle casts. Not `utils_x::Cast(handle)` (compiles via DoCastChecked but not idiomatic).
2. **`ck::TransientEntity()` is the AS shorthand** for the world-transient entity. The C++ `utils_ecs_world_subsystem::Get_TransientEntity_FromContextObject(this)` is *not* reflected in AS.
3. **By-value `FCk_Handle` parameters are const-readonly in AS.** Functions like `AddOrGet_Fragment` are non-const → use `FCk_Handle&` for params, store rvalues like `ck::ToEntity(this)` in a local before passing.
4. **`ck::ToEntity(this)` returns a temporary.** Can't pass directly to `FCk_Handle&` parameters — store in local first.
5. **`FString.Replace(old, new)` works in AS** (see CkAudioGym_Advanced_StationSpawner.as). Use it for newline counting via length-difference trick if needed.
6. **`FString.Find` / `ParseIntoArray` are NOT verified in AS.** Avoid; use `.Replace` or other primitives.
7. **`constexpr` is not an AS keyword.** Use `const` for class fields / locals.
8. **`utils_unreal_component::Add` is async.** Component instance doesn't exist immediately — bind `OnAdded` and configure inside the callback.
9. **`UPROPERTY(ExposeOnSpawn)` on EntityScript classes** is mirrored on a separate manually-written `USTRUCT FCk_X_SpawnParams`. The struct is what gym scripts construct and pass via `FInstancedStruct::Make(Params)` to `utils_entity_script::Request_SpawnEntity`.
10. **PMG `InDuration = -1.0f` for persistent;** `0.0f` (default) destroys after one tick. Footgun.
11. **PMG default debug-shape material is translucent + unlit.** Use `Add_*` / `Create_*` for filled shapes; static-mesh + MID for "real" lit geometry.
12. **`utils_scene_node::Request_UpdateOffset_*`** uses `ECk_RelativeAbsolute::Absolute` to set, `Relative` to add/multiply. We use Absolute everywhere.

---

## What I want from the new session

1. Look at the screenshot the user pastes. Identify which piece's actual geometry doesn't match its colored overlay. That's the broken piece.
2. Look at the `[GymStation Refit]` and `[GymStation Resize]` print log dumps. Sanity-check the numbers against what's expected (Width should be ~4-7 units for GOAP, not 30+; floor `scale.Y` should equal Width; back wall `scale.Y` should equal Width).
3. From those, determine whether the bug is:
   - In the `GetTextLocalSize` reading (likely if Width grew to an absurd value)
   - In `Request_UpdateOffset_Scale` propagation (likely if Resize prints show consistent scale.Y across pieces but the rendered geometry doesn't reflect it)
   - Somewhere else entirely

Probable next moves once we know:
- If `GetTextLocalSize` axis is wrong, swap to `.Y` for height or whatever the correct convention is.
- If `Request_UpdateOffset_Scale` is the culprit, try `Request_UpdateOffset` with a full `FCk_Request_SceneNode_UpdateRelativeTransform` instead of separate Location/Scale calls.
- If the bug is in some entirely different place, diagnose with additional prints.

---

## Pending TODOs (orthogonal to the active bug)

These can be picked up after the floor/wall bug is fixed:

- `CkGym_CreationSpecification.txt` doc still has stale `Get_StationTransform` examples that should be `Get_StationAnchorTransform`. Cosmetic, low priority.
- Several gyms still set explicit `Station.Width / Height` overrides instead of using `AutoSize=true`. Per-station migration as the user iterates.
- Per-tick fragment polling on every GymStation is per-station overhead. Fine at current scale (~5 stations per gym); optimise via signal-based fragment-change notification if it ever matters.
- `Get_StationByTag` is removed — derived gyms that called it have been audited and none did, but worth a final grep if anything new gets added.

---

## Where to pick up

Read the screenshot + log paste. Compute what the bug is from those. Propose a fix. Keep `ShowDebugOverlays=true` on GOAP until the bug is fixed; remove it (and the `Print` statements) as a cleanup commit afterwards.
