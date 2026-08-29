# Gym Switchboard — mission brief (PROMPT.md)

> **Written:** 2026-08-29. STABLE content only — current state lives in [PROGRESS.md](PROGRESS.md).
> **This doc dies when:** the campaign ships and CkTests/CLAUDE.md's Gyms section describes the
> switchboard. On death: delete it, or replace the body with one tombstone line.

## Goal

The gym cycler's selection menu is replaced by the **Gym Switchboard**: a Slate widget on the game
viewport, styled after CkEntityDebugOverlay (CkStyle tokens, hue-hashed module pills, rounded
chips), offering **four selectable layouts** — Group Rail (default), Chip Wall, Palette, Hint
Select — chosen per-user in Editor Preferences and cyclable live from inside the menu. All
switchboard interaction, the control panel, and the gym pawn's movement run through **CkInput's
raw-input layer stack**, so an open menu structurally masks gameplay input (the "game still
receives input while the selector is up" bug class is eliminated by architecture, not by key
etiquette). The gym registry carries a Category per gym; hue, grouping, and hint codes derive from
it. Design reference: the four mockups at
https://claude.ai/code/artifact/96989e25-ec5b-4770-9a1e-cb545c36e9af (local copy:
`D:\Repos\CkPlugins\_scratch\gym-switchboard.html`).

## Success criteria

1. In the gym level, Tab opens the switchboard; while it is open, WASD/mouse do not move the pawn
   and control-panel keys do not fire; closing it restores both — observed in PIE.
2. Group Rail layout renders all registered gyms grouped by Category with counts; arrow keys +
   Enter travel to the selected gym.
3. Typing letters in any layout filters gyms (fuzzy, word-prefix ranked); Escape clears/closes.
4. `;` toggles hint mode in any layout: two-letter codes appear, typing a code travels. Codes are
   stable across registry edits (derived, not positional).
5. Editor Preferences → Ck Tests → Gym Cycler shows a Menu Layout setting (default Group Rail);
   `[`/`]` inside the menu cycles layouts live and persists the choice.
6. Recents (last N traveled gyms) surface in the Palette layout; persisted per-user.
7. BusterBlock compiles against the new registry API without source changes until it opts into
   categories (default param), and its gyms land in a visible fallback bucket.
8. A startup lint reports gym GameModes on disk that are not registered (catches the orphaned
   A-Star gym).
9. `Ck_Gym_GoTo` accepts a hint code as well as an index.
10. Full CkTests suite: no regressions vs the baseline captured at P1 entry.

## Constraints & locked decisions

| Decision | Choice | Why |
|---|---|---|
| Menu substrate | C++ Slate widget in CkTests runtime module, visual-only | Slate gives the overlay's chip grammar; Canvas immediate-mode is what we're escaping |
| Widget focus | The widget NEVER takes keyboard focus (HitTestInvisible) | CkInput's Slate writer records only under direct viewport focus; a focused text field would starve our own pipeline |
| Interaction transport | CkInput input-layer entities; menu = high-priority layer with catch-all Consume while open | User directive; masking becomes structural |
| Tab to open | Global action (reserved bottom layer); menu's catch-all consumes Tab while open and treats it as close | Debug keys stop working under a modal without the modal knowing them — exactly the documented pattern |
| Pawn movement | Migrated off ADefaultPawn engine bindings onto a low-priority gameplay layer | The Ck stack can only mask Ck consumers; this is the actual fix for the input-bleed bug |
| Priority order | menu ≫ control panel ≫ pawn ≫ global actions | Modal masks panel masks movement |
| Style tokens | CkStyle:: from CkEditorTools (Runtime, T1) — real dependency, no duplicated constants | CkEditorTools is Runtime on purpose, already consumed by debugger runtime modules |
| Hue | Hash of Category via the overlay's MakeFromHSV8(hash, 150, 205) idiom | Same visual language; BusterBlock categories color themselves for free |
| Layout setting | `ECkGym_MenuLayout` on existing UCkGym_StartupSettings (EditorPerProjectUserSettings) | The per-user settings home already exists |
| Default layout | Group Rail (user decision) | — |
| Registry API | RegisterProjectGym gains optional Category (+ optional HintCode override); default keeps BB compiling | Optional metadata, not a back-compat shim |

## Non-goals

- Mouse-driven selection (click chips) — keyboard-first like today's menu; mouse can come later.
- Migrating the CkInput KeyBinding/Playground gyms' own subject-matter input handling — they keep
  testing what they test; only the shared framework surfaces move.
- Gamepad navigation of the menu — the layer stack makes it possible later; not this campaign.
- Any change to AutoTest pipelines a–d — gyms only.

## Reading list

- PLAN.md (gate index) + Plan/Gate_NN files as they land.
- Reference modules to mimic: CkEntityDebugOverlay (Slate visual language, viewport residency),
  CkInput autotests in `Script/CkInput/` (layer recipes), CkTimer (feature quartet shape, if any
  new C++ ECS surface is added), existing `CkGym_StartupSettings` (settings + AS boundary).
- P0 research reports: recorded in PROGRESS.md (2026-08-29 entries).

## Things ruled out — do not re-investigate

| Ruled out | Why | Evidence |
|---|---|---|
| Slate text field for palette search | Focus steal pauses the Ck input pipeline | CkInput/CLAUDE.md "Slate writer" — direct-viewport-focus gate |
| Duplicating CkStyle color constants into CkTests | CkEditorTools is Runtime tier T1, directly consumable | CkFoundation Source/CLAUDE.md tier table |
| Keeping ADefaultPawn engine bindings + "suppress input" flags | Ck layer Consume can't mask UE's own delivery (Slate writer is observe-only) | CkInput/CLAUDE.md "The Slate writer" |
| UE input suspension (CkUICore) instead of layers | User explicitly chose the layering system | User directive 2026-08-29 |
