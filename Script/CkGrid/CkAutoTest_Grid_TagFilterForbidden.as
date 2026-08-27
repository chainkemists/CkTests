// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: FORBIDDEN-TAG GATING + REQUIRED&FORBIDDEN
//============================================================================
//
// TagFilter only covers _RequiredCellTags. This pins the forbidden side of
// Get_CanPlace's tag-gating (and the Required&Forbidden interaction):
//
// Fixture:
//   - 10x10 grid with _DefaultCellTags = { Grid.Zone.Produce } (every cell).
//   - Cell (1,1) additionally tagged Grid.Zone.Hazard (per-cell _Tags).
//
// Assertions (connectivity Ignore):
//   - HazardObj (_ForbiddenCellTags = {Hazard}):
//       @ (5,5) -> CanPlace true   (no Hazard there).
//       @ (1,1) -> CanPlace false, Reason == TagMismatch, FailedCells has (1,1).
//   - StrictObj (_RequiredCellTags = {Produce} AND _ForbiddenCellTags = {Hazard}):
//       @ (5,5) -> true  (has Produce, lacks Hazard).
//       @ (1,1) -> false (has Produce but ALSO Hazard -> forbidden hit).
//   - Remove Hazard from (1,1) via Request_RemoveTag -> HazardObj @ (1,1) becomes
//     CanPlace true again (per-cell tag mutation is immediate).
//
// Tag mutation is a direct params-fragment write (immediate, no processor
// deferral), so the whole test runs synchronously in DoBeginPlay.
//============================================================================

namespace Ck
{
    asset Asset_AutoTest_Grid_TagFilterForbidden_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Grid.Zone.Produce");
        GameplayTags.Add(n"Grid.Zone.Hazard");
    }
}

class UCk_AutoTest_Grid_TagFilterForbidden : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ProduceTag = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Produce");
        auto HazardTag  = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Hazard");

        // ---- Grid: every cell carries Produce by default. ----
        auto GridOwner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto DefaultTags = FGameplayTagContainer();
        DefaultTags.AddTag(ProduceTag);
        GP.Set_DefaultCellTags(DefaultTags);
        auto Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        // ---- Per-cell: add Hazard to cell (1,1) only. ----
        auto Cell11 = utils_2d_grid_system::Get_CellAt(Grid, FIntPoint(1, 1));
        Assert_True(ck::IsValid(Cell11), "Cell (1,1) must resolve to a valid handle");
        utils_2d_grid_cell::Request_AddTag(Cell11, HazardTag);
        Assert_True(utils_2d_grid_cell::Get_Tags(Cell11).HasTag(HazardTag),
            "Cell (1,1) must carry the per-cell Hazard tag after Request_AddTag");

        // ---- HazardObj: forbids Hazard. ----
        auto HazardObjEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto HazardParams = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1));
        auto HazardForbid = FGameplayTagContainer();
        HazardForbid.AddTag(HazardTag);
        HazardParams.Set_ForbiddenCellTags(HazardForbid);
        auto HazardObj = utils_2d_grid_object::Add(HazardObjEntity, HazardParams);

        // HazardObj @ (5,5): no Hazard -> allowed.
        auto HazardAt55 = utils_2d_grid_placement::Get_CanPlace(
            Grid, HazardObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(HazardAt55.Get_CanPlace() == true,
            "HazardObj @ (5,5): no forbidden Hazard present -> placement allowed");

        // HazardObj @ (1,1): Hazard present -> rejected with TagMismatch.
        auto HazardAt11 = utils_2d_grid_placement::Get_CanPlace(
            Grid, HazardObj, FIntPoint(1, 1),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(HazardAt11.Get_CanPlace() == false,
            "HazardObj @ (1,1): forbidden Hazard present -> placement rejected");
        Assert_True(HazardAt11.Get_Reason() == ECk_2dGridPlacement_Failure::TagMismatch,
            "HazardObj @ (1,1): failure reason must be TagMismatch (forbidden-tag hit)");
        Assert_True(HazardAt11.Get_FailedCells().Contains(FIntPoint(1, 1)),
            "HazardObj @ (1,1): FailedCells must contain the forbidden cell (1,1)");

        // ---- StrictObj: requires Produce AND forbids Hazard. ----
        auto StrictObjEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto StrictParams = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1));
        auto StrictReq = FGameplayTagContainer();
        StrictReq.AddTag(ProduceTag);
        StrictParams.Set_RequiredCellTags(StrictReq);
        auto StrictForbid = FGameplayTagContainer();
        StrictForbid.AddTag(HazardTag);
        StrictParams.Set_ForbiddenCellTags(StrictForbid);
        auto StrictObj = utils_2d_grid_object::Add(StrictObjEntity, StrictParams);

        // (5,5): has Produce, lacks Hazard -> allowed.
        auto StrictAt55 = utils_2d_grid_placement::Get_CanPlace(
            Grid, StrictObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(StrictAt55.Get_CanPlace() == true,
            "StrictObj @ (5,5): has Produce, lacks Hazard -> placement allowed");

        // (1,1): has Produce but ALSO Hazard -> rejected on the forbidden tag.
        auto StrictAt11 = utils_2d_grid_placement::Get_CanPlace(
            Grid, StrictObj, FIntPoint(1, 1),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(StrictAt11.Get_CanPlace() == false,
            "StrictObj @ (1,1): Required Produce satisfied but forbidden Hazard present -> rejected");

        // ---- Remove Hazard from (1,1): HazardObj can now place there. ----
        utils_2d_grid_cell::Request_RemoveTag(Cell11, HazardTag);
        Assert_True(!utils_2d_grid_cell::Get_Tags(Cell11).HasTag(HazardTag),
            "Cell (1,1) must no longer carry Hazard after Request_RemoveTag");

        auto HazardAt11After = utils_2d_grid_placement::Get_CanPlace(
            Grid, HazardObj, FIntPoint(1, 1),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(HazardAt11After.Get_CanPlace() == true,
            "HazardObj @ (1,1): after Hazard removed, placement becomes allowed again");

        FinishSuccess();
    }
}
