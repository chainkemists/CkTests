// Language=angelscript

//============================================================================
// CK GRID - GRID PAINT ED-MODE TEST SPECS
//============================================================================
//
// Two UCk_2dGridSystem_Spec assets for exercising the Grid Paint editor mode
// (CkGridEditor). Authored in script rather than as .uasset files so the
// fixtures live in version control as text.
//
// KNOWN AND ACCEPTED: edits the paint tool makes to these (disabled cells,
// per-cell tags, blocker rects) do NOT persist - a script-defined asset is
// rebuilt from this file at every engine start, so Spec->Modify() has nothing
// durable to write to. They are throwaway canvases for tool verification, not
// authoring targets.
//
// Assign via an ACk_EntitySpawner_UE whose EntityScript is
// UCk_2dGridSystem_EntityScript; its private `Spec` property is what
// ck::grid_editor::Resolve_SpecFromSpawner reads.
//
// Object paths:
//   /Script/AngelscriptAssets.GridPaint_TestSpec_Large
//   /Script/AngelscriptAssets.GridPaint_TestSpec_Small
//============================================================================

// 10x10 @ 100cm - the busy fixture: pre-existing disabled cells, two tagged
// zones and a named blocker, so every paint sub-tool has something to hit on
// the first click.
asset GridPaint_TestSpec_Large of UCk_2dGridSystem_Spec
{
    Dimensions = FIntPoint(10, 10);
    CellSize   = FVector2D(100.0, 100.0);

    // An L-shaped notch out of the far corner plus a lone hole near the middle:
    // asymmetric on purpose, so a mis-mapped coordinate axis is obvious on sight.
    DisabledCells.Add(FIntPoint(9, 9));
    DisabledCells.Add(FIntPoint(8, 9));
    DisabledCells.Add(FIntPoint(9, 8));
    DisabledCells.Add(FIntPoint(4, 6));

    FGameplayTagContainer ElectronicsZone;
    ElectronicsZone.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Electronics"));
    PerCellTags.Add(FIntPoint(1, 1), ElectronicsZone);
    PerCellTags.Add(FIntPoint(2, 1), ElectronicsZone);

    FGameplayTagContainer HazardZone;
    HazardZone.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Hazard"));
    PerCellTags.Add(FIntPoint(6, 2), HazardZone);

    FCk_2dGridSystem_Spec_Blocker WallBlocker;
    WallBlocker.Name     = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Blocker.Wall");
    WallBlocker.RangeMin = FIntPoint(7, 4);
    WallBlocker.RangeMax = FIntPoint(8, 6);
    Blockers.Add(WallBlocker);
}

//============================================================================

// 6x4 @ 150cm - the clean fixture: no disabled cells, no blockers, one uniform
// default tag. Wider cells and a non-square footprint make it unmistakable
// against the Large spec in the viewport.
asset GridPaint_TestSpec_Small of UCk_2dGridSystem_Spec
{
    Dimensions = FIntPoint(6, 4);
    CellSize   = FVector2D(150.0, 150.0);

    DefaultCellTags.AddTag(utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Produce"));
}
