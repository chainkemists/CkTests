# Gym → Category map (P1 input data)

> **TOMBSTONE (2026-08-29):** Superseded by the categories now live in
> `Script/Common/CkTests_GymRegistry.as` — kept for history. Note the registry's exact display
> names differ from the mockup's shortened forms below; the registry file is authoritative.

> **Written:** 2026-08-29, lifted from the approved mockup's grouping
> (`_scratch/gym-switchboard.html`, GROUPS/SOLO arrays), which was derived from the real
> 81-entry registry. **Display names below are the mockup's shortened forms** — P1 must
> reconcile each against the exact `RegisterProjectGym` DisplayName before assigning
> categories (the mockup stripped shared prefixes for chip brevity, e.g. "Crowd Pathing" →
> group CkCrowd + chip "Pathing").
> **This doc dies when:** P1 lands the categories in CkTests_GymRegistry.as.

Multi-gym categories (Category string = the module name; hue derives from its hash at runtime,
the mockup's fixed hues are illustrative only):

| Category | Gyms (mockup display forms) |
|---|---|
| CkJolt (11) | Jolt Character, Debug Draw Overlay, Doors, Hair, Projectile CCD, Ramp Roll, Ropes, Sleep/Wake, Springs, Static Bake, Stress |
| CkCrowd (10) | Avoidance Volume, Foundation, Pathfinding, Pathing, Locomotion, Separation, Diagnostic, BunchUp, NarrowGap, QueueCross |
| CkUsf (6) | USF Materials, Solid Outline, Cel Shade, Cross Hatch, Hand-Drawn, Screen Dither |
| CkIskmRenderer (5) | IskmRenderer, Stress (Static 500), Stress (Moving 500), Batched, Batched Stress (600) |
| CkAttribute (4) | Basic, Byte, Float, Integer |
| CkGoap (4) | Goap, AutoReplan, Empire, F.E.A.R. |
| CkInput (2) | Key Binding, Playground |
| CkVoxelNav (2) | Flying vs Grounded, Stress (Flying 400) |

Single-gym categories (37) — each its own category named for its module; P1 decides whether
singles keep per-module categories (mockup's choice: yes, rendered as a "solo" flow section)
or collapse into a shared bucket:

Aggro, Audio Simple, Camera, Compass, Cue, Dialog, Entity Lifecycle, Entity Script, EQS,
Game Settings, Station Showcase, Interaction, Inventory, Messaging, Minimap, Net Two-Player,
Object Pooling, Particles, Path Network, Pixel Art, PMG Shapes, Probe, Projectiles & Lag Comp,
Queue, Render Target, Replication, Scene Node, Scene Node Tween, State Machine, Timer,
Transform, Tween, Unreal Component, VAT, VFX Examples, Visual LOD, Voice Chat

Known data notes carried over from the mockup research:
- 81 registered gyms / 45 distinct modules at 2026-08-29 (CkTests CLAUDE.md's "43" is stale).
- One fully-authored but NEVER-registered gym exists (A-Star) — P6's lint target.
- Display-name prefixes don't always match the owning module — categorize by module, not by
  parsing names.
