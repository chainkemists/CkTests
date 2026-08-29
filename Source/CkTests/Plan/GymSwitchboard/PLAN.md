# Gym Switchboard — PLAN.md (gate index)

> **Written:** 2026-08-29. Update the Status column in the SAME commit as each gate's landing.
> **This doc dies when:** PROMPT.md dies (campaign ships).

Mission: [PROMPT.md](PROMPT.md). Volatile state: [PROGRESS.md](PROGRESS.md).

| Gate | Name | Contract | Status |
|---|---|---|---|
| P0 | Research & locked decisions | Three read-only research reports (gym data flow, input-layer recipes, Slate substrate) recorded in PROGRESS.md; open decisions in PROMPT.md resolved | ✅ Done (2026-08-29) |
| P1 | Registry & data model | C++ gym store AS registers into; Category (+HintCode) on the entry; 81 gyms categorized; recents persistence; hue hash util | ✅ Done (2026-08-29) |
| P2 | Input + widget substrate | Menu input-layer entity (catch-all Consume open/close), Tab global action, empty Slate switchboard shell on the viewport driven by it | ✅ Done (2026-08-29) |
| P2.5 | Gameplay onto the stack | Pawn movement via low-priority layer; control panel rows via mid-priority layer; masking verified | ✅ Done (2026-08-29) |
| P3 | Group Rail layout (default) | Full default layout: groups, filter, navigate, travel. **First user-test checkpoint — STOP for PIE verification** | ✅ Code (2026-08-29) — PIE pending |
| P4 | Remaining layouts | Chip Wall, Palette (+recents), Hint Select; `;` hints cross-layout | ⏳ Pending |
| P5 | Setting + live switching | ECkGym_MenuLayout, `[`/`]` cycle + persist | ⏳ Pending |
| P6 | Lint + GoTo codes + docs | Registration lint, Ck_Gym_GoTo hint codes, CLAUDE.md updates (stale 43-gym count), full-suite gate | ⏳ Pending |

Gate files (`Plan/Gate_NN_*.md`) are authored at each gate's entry, not all up front — P0's
research feeds their work items.
