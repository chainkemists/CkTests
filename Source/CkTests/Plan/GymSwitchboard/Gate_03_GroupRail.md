# Gate 3 — Group Rail layout, Tab handover, Canvas menu retirement

> **Status:** ✅ Code done (2026-08-29) — AT THE USER-TEST CHECKPOINT; [EDITOR-VERIFY] pending
> **Depends on:** Gate 2 (P2 substrate green; P2.5 code landed, PIE checks folded into this gate's user checkpoint)
> **Estimate:** 1 session
> **THIS GATE ENDS AT THE USER-TEST CHECKPOINT** — stop for PIE verification before P4.

## Goal

"After this gate: Tab opens the switchboard's Group Rail layout (the default) in any gym world;
arrows navigate groups/gyms, typing filters, Enter travels, Esc/Tab closes; the Canvas cycler menu
is gone; while the switchboard is open the pawn and control panel are structurally silent."

## Locked design

- **Tab arming is HUD-scoped**: `ACkGym_ControlPanelHUD` (gym worlds only, by HUDClass
  construction) tells the subsystem to arm; the subsystem registers the Tab **global action** on
  the local player's source. No arming in non-gym worlds (AutoTests map stays untouched).
- **Canvas menu retired**: `CkGym_MenuHUD.as` deleted; `ACkGym_ControlPanelHUD` rebases onto
  `AHUD`; its closed-state hint line ("[Tab] gyms") moves into the panel HUD, gated on
  `Get_IsOpen()` (new BlueprintPure on the subsystem). `Request_StartGym`'s dead
  show-menu path rewires to `Request_Open`. `bMenuVisible` gates die.
- **Keyboard model (Group Rail)**: Left/Right = prev/next group; Up/Down = move gym selection
  (windowed list, ~18 visible, EnsureVisible math); typing = fuzzy filter across ALL groups
  (flattened view with group pills); Backspace edits filter; Enter = travel + close;
  Esc = clear filter first, else close; Tab = close. Key repeat for Up/Down/Backspace via an
  FTSTicker armed only while open; a Release ALWAYS cancels repeat (incl. focus-flush synthetics).
- **Model in the subsystem** (`groups sorted by category name, "Misc" fallback bucket, selection,
  filter`), widget rebuilt on state change with deterministic sort tie-breaks (category name, then
  display name). Hue = `MakeFromHSV8(GetTypeHash(Category) % 256, 150, 205)`, the overlay's idiom.
- Travel = `UCk_Utils_GymRegistry_UE::Request_TravelToGym(RegistryIndex)`; entries carry their
  registry index through the model so filtering never breaks travel targets.

## Work items

1. Model + Group Rail widget content (C++; the layout arrangement over P2's shell) → verify:
   compiles; toolbox suite at baseline.
2. Key handling in the subsystem's OnMenuCaptureTriggered (navigation, filter, repeat) → verify:
   [EDITOR-VERIFY] full interaction pass in PIE.
3. Tab handover + Canvas menu retirement (AS: delete MenuHUD, rebase ControlPanelHUD, rewire
   Request_StartGym; C++: arm API + Get_IsOpen UFUNCTION) → verify: AS compiles in test boot;
   suite at baseline.
4. PROGRESS/PLAN updates; [EDITOR-VERIFY] checklist for the user (below).

## [EDITOR-VERIFY] — the user-test checklist (success criteria 1-3 of PROMPT.md)

In PIE on the gym level:
1. Tab opens the Group Rail switchboard; Tab or Esc closes it.
2. While open: WASD/mouse do NOT move the pawn; control-panel keys do NOT fire; H does nothing.
   Close it: movement and panel keys return. (The bug this campaign exists to kill.)
3. Left/Right walks groups; Up/Down walks gyms; Enter travels to the selected gym and the menu
   is closed on arrival; current gym shows its marker when reopening.
4. Typing letters filters (e.g. "cr" shows the Crowd gyms); Backspace edits; Esc clears then closes.
5. Startup modes still work (Default/Last auto-travel, HUD suppressed during transition).
6. Control panel still works when menu closed (rows dispatch, H hides panel, hidden rows keep firing).
7. Pawn parity: fly feel (WASD + E/Q/Space/C + mouse look) matches the old DefaultPawn behavior.

## Exit criteria

- [ ] Suite at baseline; AS compile clean
- [ ] PLAN.md P3 row + this header — same commit
- [ ] **STOP: hand the [EDITOR-VERIFY] list to the user; do not start P4 until verdicts return**
