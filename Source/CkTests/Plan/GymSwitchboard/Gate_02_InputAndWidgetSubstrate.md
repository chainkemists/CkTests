# Gate 2 — Input + widget substrate

> **Status:** ⏳ Pending
> **Depends on:** Gate 1
> **Estimate:** 1-2 sessions (P2 + P2.5 together)

## Goal

"After this gate: Tab is a global action on the local player's input source; pressing it opens a
Slate switchboard shell on the game viewport whose input arrives exclusively through a
top-priority CkInput layer (catch-all Consume while open); the gym pawn flies and mouse-looks via
its own low-priority layer; the control panel's keys are captures on a mid-priority layer — so an
open menu structurally silences pawn + panel, verified by an AutoTest with synthetic injection."

## Locked design (from P0 research)

- **Priorities** (constants in C++, exposed to AS): Menu = 1000, ControlPanel = 500, Pawn = 100.
  Global actions occupy the reserved bottom.
- **`UCkGym_Switchboard_Subsystem : ULocalPlayerSubsystem`** (mimics
  `CkInputHud_Subsystem.cpp:184-310`): activation from `PlayerControllerChanged` (Initialize is
  too early), `AddViewportWidgetContent(Root, ZOrder ~90)` (below debug overlay's 100),
  idempotent re-activation, per-tick source acquisition retried until LP+PC exist.
- **Menu input layer**: owned by the subsystem; created lazily once the input source exists
  (guard with `TryGet_LayerWithPriority` first). Open = `Request_AddCapture(CatchAll, Consume)`;
  close = `Request_RemoveCapture(CatchAll)`. Tab opens via `Request_AddGlobalAction(Source, Tab)`;
  while open the catch-all consumes Tab and the menu treats it as close. One-frame capture-edit
  deferral is the contract (an open command masks from the NEXT routing pass).
- **Widget is visual-only**: root `SetVisibility(HitTestInvisible)` (attribute-bound with
  streamer-mode collapse, per `SCkDebugOverlay_Root.cpp:101-106`); NEVER takes keyboard focus; all
  interaction from `OnCaptureTriggered` (dynamic delegate bound on the subsystem UObject).
- **Key repeat** is menu-side: press starts repeat timer, release cancels — release always
  cancels, including the synthetic Releases the focus-loss flush writes.
- **Transitional Tab ownership**: through P2 the OLD Canvas menu keeps Tab; the shell is opened
  via console `ck.Gym.Switchboard` for iteration. P3 hands Tab to the switchboard and retires the
  Canvas menu. This keeps every intermediate commit shippable.
- **Pawn (P2.5)**: `ACk_Gym_Base_Pawn` stays `ADefaultPawn` for its movement component but sets
  `bAddDefaultMovementBindings = false`; a pawn-owned layer (priority 100) captures
  W/A/S/D/Q/E/SpaceBar (Consume) + MouseX/MouseY (PassThrough, event-driven
  `Get_AnalogValue()`); held state hand-tracked from press/release edges; movement applied in
  Tick via AddMovementInput / AddControllerYaw-PitchInput. Never poll conditioned axis state.
- **Control panel (P2.5)**: `H` + row keys become captures on a priority-500 layer owned by the
  panel HUD/controller; row rebuild logic unchanged.

## De-risk items (NEW INFRASTRUCTURE — unknowns)

1. **Axis events through a layer have zero runtime test coverage** (code says a Key capture on
   MouseX matches AnalogAxis — `CkInputLayer_Processor.cpp:245-260` — but no test proves it).
   FIRST work item: AutoTest `CkAutoTest_InputLayer_AxisEventsReachCapture` injecting an
   AnalogAxis row at a Key capture, asserting delivery + analog value + no press-owner recording.
2. C++-side `BindTo_OnCaptureTriggered` from a subsystem UObject — pattern exists BP/AS-side;
   verify the C++ dynamic-delegate bind compiles and fires in the same AutoTest where possible.

## Work items

1. De-risk AutoTest (above) → verify: test green in toolbox run.
2. Priority constants + `UCkGym_Switchboard_Subsystem` skeleton (viewport widget add/remove,
   cvar gate, source acquisition, layer creation) → verify: shell toggles via console in PIE
   [EDITOR-VERIFY], no ensure spam in headless boot.
3. Menu open/close over the layer (catch-all add/remove, Tab global action wired but shell-only)
   → verify: AutoTest with synthetic source: open → inject W → menu saw it, a lower probe layer
   did not; close → probe sees W again.
4. `SCkGym_Switchboard` shell (glass panel, CkStyle tokens, empty body) → verify: [EDITOR-VERIFY]
   visual.
5. P2.5 pawn migration → verify: AutoTest for held-set bookkeeping where feasible; PIE parity
   check [EDITOR-VERIFY]: fly speed/feel unchanged, menu open freezes pawn.
6. P2.5 control panel migration → verify: PIE: panel keys work, dead while menu open.

## Expected observations at the gate

| I will run | I expect to observe | If instead I see | Prewritten response |
|---|---|---|---|
| Axis de-risk AutoTest | delivered event carries the injected analog value | no delivery | STOP: mouse-look design falls back to polling `Get_LastRawAxisValue` on the source each tick while the pawn layer is unmasked — write addendum before proceeding |
| Masking AutoTest | probe layer silent while catch-all open | probe still fires | routing bug or wrong priority — debug with `Get_RoutedEventsThisFrame` |
| PIE: menu open + WASD | pawn frozen, menu navigates | pawn moves | pawn still on engine bindings — check bAddDefaultMovementBindings actually honored |
| Full suite | == baseline (1270/19) | new reds in CkInput tests | our layers leak into shared-world tests — ensure gym layers only exist in gym worlds |

## Exit criteria — same commit as last work item

- [ ] All expected observations confirmed; PROGRESS.md updated with evidence
- [ ] PLAN.md rows P2 + P2.5 ✅ + this header — same commit
- [ ] [EDITOR-VERIFY] items listed for the P3 user checkpoint
