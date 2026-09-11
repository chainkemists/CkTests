# Selection gym

Open **Selection** from the CkTests gym switchboard. It is an interactive fixture bank for the Debug Overlay selection commands, not a visual-equivalence or packaged test.

Use the panel in this order:

1. Press `O` to run `ck.DebugOverlay 1`, then `P` for `ck.DebugOverlay.Settings` if the drawer is closed.
2. Aim at the fixtures to make the primary overlay follow them automatically. Use `[` / `]` for previous/next and hold `\` for family inspection while stepping through scenarios `1` through `5`. Comma resumes the best aim target; double-Shift pins its data.
3. Use `R` to prove the active scenario destroys and rebuilds its entire fixture bank. In scenario 5, use `X` repeatedly to destroy and replace one labelled root.

Discovery must update without pressing comma: the default range is 10,000 units, with stable numbers for surviving candidates. Cone/view settings control automatic aim targets, not whether other in-range roots are discovered. The bottom status panel has been removed; selection count/range and previous/next numbers are integrated into the existing focus card. Verify that the world diamonds have readable `#` numbers.

Expected observations:

| Scenario | Fixture contract to inspect |
| --- | --- |
| 1 — Topology | Two direct transient-parent roots and a root nested under an ordinary lifetime parent are all labelled `Ck.Debug.Selection.Root`. The nested candidate is its own context root. |
| 2 — Distance | Centered-near, exact co-located pair, and centered-far roots remain distinct navigable candidates. |
| 3 — Hierarchy | One labelled root owns transform, SceneNode, state-machine, timer, and integer-attribute composition; its ordinary descendant chain includes a no-transform family member. |
| 4 — Visibility | An offscreen labelled parent has a visible ordinary transform child that promotes the parent; a separate labelled root sits behind a real blocking wall. This distinguishes root grouping, discovery, and present visibility. |
| 5 — Lifecycle | One candidate moves continuously. `X` destroys and recreates the second root without leaving the old selection candidate in the family. |

Pass each scenario only when `Next`/`Prev` remain bounded to its rebuilt bank, `Family` represents the intended root-family relationship, and the drawer shows the label and transform availability accurately. Every marker has a collision-free cube and in-world text label; missing markers do not change fixture composition. No runtime result is claimed until these manual checks are performed.

The accompanying `UCk_AutoTest_Selection_FixtureComposition` verifies direct transient ownership, ordinary-child ownership, independent labelled context roots, transform variation, and cleanup in a PIE world.
