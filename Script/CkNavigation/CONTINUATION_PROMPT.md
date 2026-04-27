# CkNavigation + GymStation continuation prompt

I'm continuing work on CkNavigation + a procedurally-generated `GymStation` system. Read the full prompt below before doing anything.

---

## High-level mission

Two streams converged into this session:

1. **CkNavigation** (CkFoundation `feature/navigation`) — implementing dtCrowd integration on top of the path-find work from earlier sessions. Steps 1-7 were committed before this session. Steps 8-11 committed this session; steps 12-13 + minimal 14 are uncommitted.
2. **GymStation** (CkTests `dev`) — replacing `BP_DemoDisplay` (the BP that visually hosts gym stations) with a code-driven, procedurally-generated alcove whose dimensions are *exactly known*. The motivation is placement-correctness: the Navigation gym (and similar) currently mis-places test entities because the BP station's mesh dimensions are opaque to gym-author code.

---

## Repo paths

- `D:\Repos\CkPlugins\Plugins\CkFoundation` — branch `feature/navigation`
- `D:\Repos\CkPlugins\Plugins\CkGameplayDebugger` — branch `dev`
- `D:\Repos\CkPlugins\Plugins\CkTests` — branch `dev`
- Outer `D:\Repos\CkPlugins` — branch `dev`

---

## What got committed this session

### CkFoundation `feature/navigation` (latest 8 commits)

```
8508a20d6 feat(Navigation): add Crowd setup + push-position + update-target + step processors  ← Steps 8-11
e2fa0bc24 docs(Pmg): document API tiers, duration sentinel, and fragment requirements
66f31208c chore: remove legacy Script/Progress.md (superseded by Source/CkNavigation/PROGRESS.md)
e000e9668 docs: cross-reference Source/Script CLAUDE.md, clarify build flow, add module-discovery hint
320e7b31f fix(Pmg): ensure DebugShape_Common when appending debug lines  ← critical PMG fix
5d2f60aeb feat(Navigation): capture detailed path-find fail reasons + diagnostics
043f4bf51 feat(Navigation): add HandleRequests processor + minimal Utils for path queries  ← Step 7
```

### Pushed to origin

`feature/navigation` on CkFoundation, `dev` on CkGameplayDebugger, `dev` on CkTests, outer `dev`.

---

## Uncommitted state

### CkFoundation (`feature/navigation`)

```
M Source/CLAUDE.md
M Source/CkNavigation/Public/CkNavigation/Nav/CkNav_Processor.cpp
M Source/CkNavigation/Public/CkNavigation/Nav/CkNav_Processor.h
M Source/CkNavigation/Public/CkNavigation/Utils/CkNav_Utils.cpp
M Source/CkNavigation/Public/CkNavigation/Utils/CkNav_Utils.h
```

What's in those:

- **CkNav_Processor.h/.cpp**: added `FProcessor_Nav_CrowdReadVelocity` (Step 12) and `FProcessor_Nav_CrowdEndPlay` (Step 13). CrowdSetup and CrowdPushPosition rebuild path now project the entity location onto the navmesh via `Crowd->getNavMeshQuery()` + `FCk_Nav_Algorithm::FindNearestPoly` BEFORE calling `RegisterAgent`/`addAgent`, then snap the entity transform via `UCk_Utils_Transform_UE::Request_SetTransform`. Same root cause as Step 7's `FindPath` fix: dtCrowd's internal poly resolution uses the navmesh's small `DefaultQueryExtent` and silently registers on a bogus poly when the entity is far above/below the surface. Also cleaned up `ck::IsValid_Policy_NullptrOnly{}` misuse on TSharedPtr — that policy is for raw pointers only.
- **CkNav_Utils.h/.cpp**: added `Get_CurrentVelocity`, `Get_DesiredVelocity`, `Get_IsCrowdRegistered` for AS gym scripts (minimal Step 14).
- **Source/CLAUDE.md**: documented the IsValid policy gotcha so future sessions don't repeat it. Bare `ck::IsValid(x)` works for handles, smart pointers (TSharedPtr / TWeakPtr / TWeakObjectPtr / TStrongObjectPtr), and any type with a `ck::IsValid` overload. The `Policy_NullptrOnly{}` overload is for *raw pointers only*.

### CkGameplayDebugger (`dev`)

```
M Source/CkNavDebugger/CkNavDebugger_Module.cpp
M Source/CkNavDebugger/Public/CkNavDebugger/DebugDraw/CkNavDebugger_WorldDraw.cpp
```

NavDebugger overlay-gate fix. Old gate `(AlwaysOn || GIsWindowOpen) AND SelectedId >= 0` was fragile — saved-layout tab restores left `GIsWindowOpen` stale, so the user had to manually set the `OverlayAlwaysOn` cvar. New gate is selection-only: `Ck.NavDebugger.SelectedEntityId >= 0`. Both `CloseDebugger` and the `OnTabClosed_Lambda` clear that cvar to -1, so closing the tab tears the overlay down naturally.

### CkTests (`dev`)

```
M Script/CkNavigation/CkNavigationGym_GameMode.as           — added test-station spawn (currently uses SpawnActor(ACk_GymStation, ...))
M Script/CkNavigation/CkNavigationGym_PlayerController.as   — registered Gym.Navigation.Move station
M Script/CkNavigation/CkNavigation_Shared.as                — added Gym.Navigation.Move tag
M Script/Generated/CkTests_EntitySpawnParams.as             — auto-generated; will pick up the new EntityScript
?? Script/CkNavigation/CkNavigationGym_MovingAgent.as       — moving-agent test station entity script
?? Script/Common/CkGymStation.as                            — current station ACTOR (about to be replaced)
?? Content/Common/DemoRoom/Blueprints/BP_DemoDisplay.txt    — BP export (reference)
?? Content/Common/DemoRoom/Blueprints/BP_DemoDisplay.json   — BP export (reference)
```

The `CkGymStation.as` file is the work-in-progress that needs to be **rewritten as an EntityScript** (next task — see "Pending work" below).

---

## What got done this session — narrative summary

### CkNavigation steps 12-13 + minimal 14 (uncommitted)

- `FProcessor_Nav_CrowdReadVelocity` (Step 12): copies `Agent->vel` and `Agent->dvel` into `FFragment_Nav_CrowdVelocity` each frame. Match: `FCk_Handle_NavAgent + ck::TReadOnly<FFragment_Nav_CrowdAgent> + ck::TReadWrite<FFragment_Nav_CrowdVelocity> + FTag_Nav_CrowdRegistered + CK_IGNORE_PENDING_KILL`. RunAfter=`FProcessor_Nav_CrowdStep`.
- `FProcessor_Nav_CrowdEndPlay` (Step 13): on entity teardown, `Crowd->removeAgent(Idx)` if `Idx >= 0`. Tolerates null crowd weak-pin. CK_IF_END_PLAY + FGroup_EndPlay.
- `UCk_Utils_Nav_UE::Get_CurrentVelocity / Get_DesiredVelocity / Get_IsCrowdRegistered` (minimal Step 14): exposed for AS so the gym MovingAgent station can read steered velocity each tick and integrate into its transform. Pattern in `Plugins/CkTests/Script/CkNavigation/CkNavigationGym_MovingAgent.as`.

### Navmesh pre-projection fix in CrowdSetup + CrowdPushPosition rebuild (uncommitted)

When agent transform is far above/below the navmesh (e.g. agent at Z=0, navmesh at Z=-300), `dtCrowd::addAgent` uses the small `DefaultQueryExtent` to resolve a poly and silently registers on a bogus poly. The user diagnosed this — same root cause as Step 7's `FindPath` issue. Fix:

```cpp
// In CrowdSetup ForEachEntity, before RegisterAgent:
auto AgentLocation = InTransform.Get_Transform().GetLocation();
if (const auto* NavQuery = Crowd->getNavMeshQuery()) {
    const auto SearchExtent = UCk_Utils_Nav_ProjectSettings::Get_NavQuerySearchHalfExtent();
    const auto [PolyRef, Snapped] = FCk_Nav_Algorithm::FindNearestPoly(*NavQuery, AgentLocation, SearchExtent);
    if (PolyRef != 0) { AgentLocation = Snapped; }
}
// ...register...
// then snap entity transform so CrowdPushPosition stays in steady-state no-op:
auto TransformHandle = UCk_Utils_Transform_UE::Cast(InHandle);
UCk_Utils_Transform_UE::Request_SetTransform(TransformHandle,
    FCk_Request_Transform_SetTransform{FTransform{AgentLocation}});
```

Same pattern in CrowdPushPosition's teleport-rebuild branch.

### NavDebugger gate simplification (uncommitted)

Dropped the `(AlwaysOn || GIsWindowOpen)` half of the overlay gate. Now selection cvar alone controls. `CloseDebugger` and the `OnTabClosed_Lambda` set `Ck.NavDebugger.SelectedEntityId` to -1 so the overlay tears down on close.

### CkGymStation saga (the meandering visual journey)

Goal: replace BP_DemoDisplay with code-driven station so dimensions are exact and gym placement code can trust anchors. Iterations:

1. **First attempt**: ISM-based actor faithfully porting BP's `Scalable Panel` tile system using `Display_Main_B / Display_Corner_B / Display_Side_B / Display_Curve_B / Display_EdgeCurve_B` — disjoint pieces because the per-tile mesh anchors are unknown without inspecting the assets.
2. **Second attempt**: single scaled `Display_Main_B` — clean rectangle, text positioned correctly. User said "perfect" but visually plain.
3. **Third attempt**: re-introduced corner+side+curve tiles for visual richness — broke geometry again (curve hood floating, sides disjoint).
4. **Reverted to flat rectangle**.
5. User showed the actual BP look — it's an **architectural alcove**: curved hood, vertical interior walls, back wall with text, floor stage, base trim. Not a flat panel.
6. **Fourth attempt** (current `CkGymStation.as`): pivoted to procedural generation — replaced static-mesh tiles with multiple `UStaticMeshComponent`s using `/Engine/BasicShapes/Cube` scaled to form an alcove from 6 boxes (BackWall, LeftWall, RightWall, FloorStage, Roof, BaseTrim). User pointed out I deviated from the agreed PMG plan.
7. User confirmed: **switch to PMG**, use the EcsWorld transient entity as the owner, and **make the station an EntityScript** so AS auto-generates its spawn-params struct.

That's where we are.

---

## Pending work — what to do NEXT

User's confirmed direction:

### 1. Make the station an EntityScript (`UCk_EntityScript_GymStation : UCk_GenericEntityScript_UE`)

- All tuners as `UPROPERTY(ExposeOnSpawn)` so they auto-generate the spawn-params struct in `Plugins/CkTests/Script/Generated/CkTests_EntitySpawnParams.as`. Tuners:
  - `FTransform InitialTransform`
  - `double Width = 6.0`, `double Depth = 5.0`, `double Height = 5.0` (100×cm units)
  - `double WallThickness = 15.0`, `double FloorThickness = 15.0`, `double RoofThickness = 25.0` (cm)
  - `FLinearColor BodyColour = FLinearColor(0.02, 0.02, 0.02, 1.0)` (near-black)
  - `FText TitleText`
  - `TArray<FText> DescriptionText`
  - `double TitleScale = 20.0`, `double DescriptionScale = 12.0`
  - `FColor TitleColour`, `FColor DescriptionColour`
  - `EHorizTextAligment TextAlignment = EHTA_Left`
  - `bool ShowSpotlight = true`
  - `bool FloorText = false`
  - Base trim: `BaseTrimDepth/Width/Height/ForwardOffset` if we keep that piece

### 2. Build the alcove with CkPmg `Create_Box`

- Six boxes: BackWall, LeftWall, RightWall, FloorStage, Roof, BaseTrim.
- Owner = the EcsWorld transient entity, fetched via `utils_ecs_world_subsystem::Get_TransientEntity_FromContextObject(this)` (header at `D:\Repos\CkPlugins\Plugins\CkFoundation\Source\CkEcs\Public\CkEcs\Subsystem\CkEcsWorld_Subsystem.h`).
- For each piece, compute **world transform** by composing `InitialTransform` × local-offset:
  - `WorldLoc = InitialTransform.GetLocation() + InitialTransform.Rotator().RotateVector(LocalLoc)`
  - `WorldRot = InitialTransform.Rotator()` (boxes axis-aligned in local; rotation inherits from station)
- `InExtent` is **half-extent** in cm. E.g. back wall extent = `FVector(WallThickness/2, Width*50, Height*50)`.
- `InDuration = -1.0f` for persistent (NOT 0 — that destroys after one tick).
- `InDrawLines = true` (filled mesh + auto wireframe).
- `InColor = BodyColour`.
- Store the returned `FCk_Handle_Pmg_DebugShape` per piece for cleanup.

### 3. Geometry conventions (decided this session)

- Actor pivot at the alcove **centre on the ground** (Z=0).
- Alcove opens toward **+X** (player approaches from world +X looking -X; matches BP).
- Width along Y (`±Width*50` cm), Depth along X (`-Depth*50` back wall to `+Depth*50` front opening), Height along Z (0 floor to `Height*100` top).
- Width/Depth/Height in 100×cm units; WallThickness/RoofThickness/FloorThickness in cm.

Box positions in actor-local (apply `InitialTransform` to get world):

| Piece | Local centre (X, Y, Z) cm | Half-extent (X, Y, Z) cm |
|---|---|---|
| BackWall | (-Depth*50 + WallThickness/2, 0, Height*50) | (WallThickness/2, Width*50, Height*50) |
| LeftWall | (0, +Width*50 - WallThickness/2, Height*50) | (Depth*50, WallThickness/2, Height*50) |
| RightWall | (0, -Width*50 + WallThickness/2, Height*50) | (Depth*50, WallThickness/2, Height*50) |
| FloorStage | (0, 0, FloorThickness/2) | (Depth*50, Width*50, FloorThickness/2) |
| Roof | (0, 0, Height*100 - RoofThickness/2) | (Depth*50, Width*50, RoofThickness/2) |
| BaseTrim | (Depth*50 + BaseTrimForwardOffset + BaseTrimDepth/2, 0, BaseTrimHeight/2) | (BaseTrimDepth/2, BaseTrimWidth*50, BaseTrimHeight/2) |

### 4. Sibling visual Actor (`ACk_GymStation_Visual : AActor`) — text + anchor SceneComponents

EntityScripts are UObjects, not Actors — they can't host UTextRenderComponent / USceneComponent directly. Spawn a thin sibling actor in `DoConstruct` that holds:

- `UTextRenderComponent TitleText_Component` (positioned on back wall's inner face, facing +X toward viewer)
- `UTextRenderComponent DescriptionText_Component` (below title)
- `USpotLightComponent Spotlight_Component` (illuminates back wall)
- `USceneComponent` anchors: `FootprintCenterAnchor`, `AgentSpawnFrontAnchor`, `AgentSpawnLeftAnchor`, `AgentSpawnRightAnchor`, `AgentSpawnBackAnchor`, `PanelTopFrontAnchor`, `PanelCenterAnchor`

Public methods on the visual actor:
- `Update_TextContent(FText InTitle, TArray<FText> InDesc)`
- `Set_Dimensions(double Width, double Depth, double Height)` (recomputes anchor positions + text Z)

### 5. EntityScript anchor API — public UFUNCTIONs

The placement-correctness contract. Computed from `InitialTransform` + dimensions:

```as
FVector Get_FootprintCenterWorldLocation();
FVector Get_AgentSpawnFrontWorldLocation();   // +Depth*50 + 100 cm in front of opening, ground level
FVector Get_AgentSpawnBackWorldLocation();    // behind back wall
FVector Get_AgentSpawnLeftWorldLocation();    // +Width*50 + 100 cm to the left
FVector Get_AgentSpawnRightWorldLocation();   // -Width*50 - 100 cm to the right
FVector Get_PanelTopFrontWorldLocation();     // top edge of front opening
FVector Get_PanelCenterWorldLocation();       // alcove centre at mid-height
```

**This is what fixes the gym placement issue.** Gym scripts call these functions and trust them to the centimetre. Same maths source as the boxes (the dimensions param) so they line up exactly.

### 6. EntityScript lifecycle

```as
UFUNCTION(BlueprintOverride)
ECk_EntityScript_ConstructionFlow DoConstruct(FCk_Handle& InHandle)
{
    utils_transform::Add(InHandle, InitialTransform, ECk_Replication::DoesNotReplicate);
    Build_Alcove();        // 6× Create_Box on transient entity
    Spawn_VisualActor();   // SpawnActor(ACk_GymStation_Visual, ...)
    return ECk_EntityScript_ConstructionFlow::Finished;
}

UFUNCTION(BlueprintOverride)
void DoEndPlay(FCk_Handle InHandle)
{
    Destroy_Alcove();      // utils_entity_lifetime::Request_DestroyEntity per stored PMG handle
    // Visual actor cleans up via UE GC when the UPROPERTY ref drops.
}
```

### 7. Update `CkNavigationGym_GameMode.as` test spawn

Currently:
```as
auto TestStation = SpawnActor(ACk_GymStation, TestStationLocation, FRotator());
TestStation.Width = 6.0;  // etc
TestStation.Update_Display(...);
```

Replace with:
```as
auto Params = FCkTests_GymStation_SpawnParams();
Params.InitialTransform = FTransform(...);
Params.Width = 6.0;
// etc
auto StationEntity = utils_entity_script::Request_SpawnEntity(
    SomeOwnerHandle,    // figure out the right owner — possibly utils_ecs_world_subsystem::Get_TransientEntity_FromContextObject(this)
    UCk_EntityScript_GymStation,
    FInstancedStruct::Make(Params));
```

---

## Lessons learned this session — DO NOT repeat

1. **`ck::IsValid_Policy_NullptrOnly{}` is for raw pointers ONLY.** Smart pointers (TSharedPtr / TWeakPtr / TWeakObjectPtr / TStrongObjectPtr) have their own `ck::IsValid` overload — call it bare. Documented in `Source/CLAUDE.md`.

2. **`constexpr` is not an AngelScript keyword.** Use `const`. AS error: `"Expected ';' Instead found reserved keyword 'auto'"` after `constexpr auto`.

3. **CkPmg `Append_Debug*_World` is wireframe-only**, not a filled shape. For filled shapes use `UCk_Utils_Pmg_BasicShapes::Add_*` / `Create_*` — those create a real procedural mesh AND auto-include the wireframe via `InDrawLines=true`.

4. **CkPmg `InDuration = 0.0f` is a one-tick destroy**, not "no auto-destroy". For persistent overlays/geometry use `-1.0f`. The `CheckDuration` processor early-outs only on negative durations.

5. **`Append_Debug*_World` requires `Common + Lines + Transform` fragments on the entity.** Earlier `GetOrAddLinesFragment` only added `Lines` — fixed in commit `320e7b31f` to AddOrGet `Common` too.

6. **dtCrowd `addAgent` uses the navmesh's small `DefaultQueryExtent` to resolve a poly.** Same root cause as Step 7's `FindPath` issue. Pre-project locations using `getNavMeshQuery()` + `FindNearestPoly` before calling `addAgent`. CrowdSetup also snaps the entity transform via `Request_SetTransform` so subsequent CrowdPushPosition checks stay in steady-state no-op.

7. **`ck_exp::TProcessor` template requires a Handle + at least one fragment in the match list** — even for pure-DoTick processors. Specifying only `<Self, CK_IGNORE_PENDING_KILL>` fails template constraints.

8. **NavDebugger overlay gate** — the `WindowOpen` flag goes stale on saved-layout tab restore. Selection cvar alone is more reliable. Tab-close clears the cvar to tear down the overlay.

9. **AS class-level inline init for FVector** — use `FVector::ZeroVector`, not `FVector(0, 0, 0)` (existing codebase pattern). `default Array.Add(...)` doesn't work either — initialise lazily in ConstructionScript.

10. **Mesh anchor conventions vary per asset** — never guess the local origin / extent / pivot of a mesh you can't inspect. The `Display_*_B` BP meshes have non-uniform pivots/extents; trying to lay them out tile-by-tile without inspection produces broken disjoint geometry. Either inspect each asset or skip them and use known-dimension primitives (Engine `Cube`, or the procedural CkPmg `Box`). PMG is preferred — the half-extent is what you pass in.

11. **For UTextRenderComponent + alcove orientation**: text on the back wall faces +X (default rotation, no Yaw=180 needed) when the alcove opens toward +X and the viewer approaches from +X looking -X. BP's `TextAlignmentOffset` macro returns `+(W-Adj)/2*100` for `EHTA_Left` and `-(W-Adj)/2*100` for `EHTA_Right` (NOT inverted).

12. **CkPmg integration**: the BP-DemoDisplay-style pre-baked tile system was the wrong abstraction. Procedural geometry (Engine Cube or CkPmg Box) gives exact dimensions, which is what gym-author code needs to position test entities correctly.

---

## Critical references

- **CkPmg basic shapes API**: `Plugins/CkFoundation/Source/CkPmg/Public/CkPmg/CkPmg_Utils_BasicShapes.h` — `Add_Box`, `Create_Box`, `Add_Sphere`, etc.
- **EcsWorld transient entity**: `Plugins/CkFoundation/Source/CkEcs/Public/CkEcs/Subsystem/CkEcsWorld_Subsystem.h` — `UCk_Utils_EcsWorld_Subsystem_UE::Get_TransientEntity_FromContextObject(WorldContextObject)`.
- **AS EntityScript example**: `Plugins/CkTests/Script/CkNavigation/CkNavigationGym_Station.as`.
- **CkPmg CLAUDE.md**: `Plugins/CkFoundation/Source/CkPmg/Claude.md` — API tiers, duration sentinel, fragment requirements.
- **CkDebuggerCommon CLAUDE.md**: `Plugins/CkGameplayDebugger/Source/CkDebuggerCommon/CLAUDE.md` — has the "In-world overlays via PMG" section.
- **CkNavigation PROGRESS.md**: `Plugins/CkFoundation/Source/CkNavigation/PROGRESS.md` — pre-this-session progress notes for steps 1-7. Steps 8-13 + minimal 14 done in this session (uncommitted for 12-13).
- **CkNavigation TODO** (carry-forward):
  - [ ] Steps 12-13 + Utils additions: not yet committed; commit when verified working.
  - [ ] Step 14 full surface: `Request_StopPath`, `Remove`.
  - [ ] Step 15: `FProcessor_Nav_CrowdCancel` + wire `Request_StopPath`.
  - [ ] Step 18: `SCOPE_CYCLE_COUNTER` + profiling stats in 4 hotspots.
  - [ ] Update `cknavigation_prompt.md` spec with all session deviations.
  - [ ] Module CLAUDE.md.
  - [ ] v1.1: port `TryGetContext` factory pattern fix to CkProbe.
- **BP_DemoDisplay reference export** (for visual reference, NOT for asset-anchor-guessing): `Plugins/CkTests/Content/Common/DemoRoom/Blueprints/BP_DemoDisplay.txt`.

---

## Where to pick up

Start by reading the current `Plugins/CkTests/Script/Common/CkGymStation.as` (the static-mesh-cube actor), then rewrite it as the EntityScript + sibling visual actor described under "Pending work" above. Build, PIE the Navigation gym, verify the test station appears with correct geometry + anchors. Then commit Steps 12-13 + Utils + new GymStation as logical commits.

Avoid the failure modes documented under "Lessons learned" — especially #10 (don't guess mesh anchors) and #1-#5 (the IsValid / constexpr / PMG gotchas).
