# Gate 4 — Control-panel adoption sweep (every gym knob is a row)

> **Status:** ⏳ Pending (inventory complete 2026-08-29; execution blocked on the settings-in-menu
> gate landing first)
> **Depends on:** P3 round-2 fixes ✅; user directive 2026-08-29 ("panel is the core standard;
> gym CVars removed")
> **Estimate:** 2-3 sessions (40+ AS files)

## Goal

"After this gate: every user-facing knob in every CkTests gym is a control-panel row; the four
gym-owned CVars (`ck.JoltStressGym.*`) are deleted; no gym tells the user to type a console
command for something a row can do."

## Inventory (agent report, 2026-08-29 — full text in the session log; counts VERIFIED)

- 81 gyms: 37 fully adopted / 13 partial (8 hard-gap) / 27 not adopted (~199 execs) / 4 no-knobs.
- Gym-owned CVars: exactly 4 (`ck.JoltStressGym.{InitialBalls,BallsPerWave,WaveIntervalSeconds,MaxBalls}`
  in `Source/CkTests/Private/CkJoltStressGym_Utils.cpp`) → DELETE, replace with rows.
- 11 gyms advertise module CVars in text (6 Jolt `ck.Jolt.DebugDraw.*`, 5 Crowd) → Toggle rows
  writing the module cvar (CkQueue capture/restore is the reference pattern); module cvars stay.
- Old non-adopter rationale VOID for KeyBinding (nothing polls keys), NARROWED for Playground
  (reserve LMB/RMB/W/LeftShift/Q + H), SEMANTIC for VoiceChat (V stays a held poll; rows get a
  latched TX toggle + status).

## Locked policy (stated to the user 2026-08-29; objections change it)

1. Gym-owned CVars: deleted, replaced by rows (preset rings for counts; a restart Action where the
   value is only read at gym start).
2. Parameterless execs: become rows; the exec is DELETED in the same change (no aliases).
3. Arg-taking execs: a row with a preset ring (`Cycle`) or ±step Action pair where a sensible
   ladder exists; execs KEPT only for genuinely console-shaped input (FString asset paths, 3-4
   float tuples: Vat SetCollection/PlayClip, VfxExamples Tune, Attribute SetVelocity), each
   advertised by a Status row.
4. Pure console aliases of row-reachable states (the 4 Stylize CyclePreset, PixelArt CycleStation):
   deleted.
5. Framework execs on the base PC (Ck_Gym_Restart/Next/Prev/GoTo/List) stay — they are the
   scriptable surface, not gym knobs.
6. Bonus fixes folded in where touched: missing EndPlay cvar restores (VoxelNav x2, PathNetwork,
   CrowdPathing, CrowdAvoidanceVolume — adopt CkQueue's capture/restore); the VfxExamples H-key
   filter/panel double-fire.

## Batches (each: edit → AS-compile smoke → commit; full suite once at gate exit)

| Batch | Scope | Risk |
|---|---|---|
| A | CkJolt (11 gyms): cvar deletion + C++ edit + 25 execs + DebugDraw toggle rows | cvar restart semantics |
| B | Parameterless mass: CkGoap(44), CkProbe(12), CkMinimap(9), CkCompass(5), CkCamera(3), CkRenderTarget(3), CkSceneNodeTween(2), CkIskmBatchedStress(1) | low — delegate-able |
| C | CkAttribute (75 knobs, 20 arg-taking → ladders) | high — main thread |
| D | Partial hard-gaps: Interaction(6), Inventory(7), Vat(6), Queue(4), Pmg(2), Messaging(1), PixelArt(1), VfxExamples(4) + its H-key fix | mixed |
| E | KeyBinding(16), Playground(2, 5-key reservation), VoiceChat(2, latch), soft-gap alias deletions | semantic care |

## Exit criteria

- [ ] `rg` finds zero `ck.JoltStressGym` anywhere; zero gym text advertising a console command a
      row now covers
- [ ] Full suite at baseline; [EDITOR-VERIFY] spot-check list (one gym per batch)
- [ ] CkTests/CLAUDE.md gym-section rewrite folded into P6 (stale 43-count, stale "panel polls"
      wording — both flagged by the inventory)
