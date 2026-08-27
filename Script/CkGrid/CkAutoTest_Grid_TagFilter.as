// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: CELL TAG-GATING (GRID DEFAULT + PER-CELL)
//============================================================================
//
// Pins the tag-gating union in Get_CanPlace: a cell's effective tag set is the
// grid's _DefaultCellTags unioned with the cell's own _Tags, checked against an
// object's _RequiredCellTags / _ForbiddenCellTags.
//
// Fixture:
//   - 10x10 grid with _DefaultCellTags = { Grid.Zone.Produce } (every cell).
//   - Cell (1,1) additionally tagged Grid.Zone.Electronics (per-cell _Tags).
//   - ProduceObj  : _RequiredCellTags = { Grid.Zone.Produce }.
//   - ElecObj     : _RequiredCellTags = { Grid.Zone.Electronics }.
//
// Assertions (connectivity Ignore, all via Get_CanPlace().Get_CanPlace()):
//   - ProduceObj @ (5,5) -> true  (grid default Produce satisfies the require).
//   - ElecObj    @ (1,1) -> true  (per-cell Electronics unions with default).
//   - ElecObj    @ (5,5) -> false (only Produce there; Electronics missing).
//
// Tag-gating is read-only and per-cell _Tags mutation is immediate (no
// processor deferral), so the whole test runs synchronously in DoBeginPlay.
//============================================================================

namespace Ck
{
    asset Asset_AutoTest_Grid_TagFilter_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Grid.Zone.Produce");
        GameplayTags.Add(n"Grid.Zone.Electronics");
    }
}

class UCk_AutoTest_Grid_TagFilter : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ProduceTag = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Produce");
        auto ElecTag    = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Electronics");

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

        // ---- Per-cell: add Electronics to cell (1,1) only. ----
        auto Cell11 = utils_2d_grid_system::Get_CellAt(Grid, FIntPoint(1, 1));
        Assert_True(ck::IsValid(Cell11), "Cell (1,1) must resolve to a valid handle");
        utils_2d_grid_cell::Request_AddTag(Cell11, ElecTag);
        Assert_True(utils_2d_grid_cell::Get_Tags(Cell11).HasTag(ElecTag),
            "Cell (1,1) must carry the per-cell Electronics tag after Request_AddTag");

        // ---- ProduceObj: requires Produce. ----
        auto ProduceObjEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ProduceParams = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1));
        auto ProduceReq = FGameplayTagContainer();
        ProduceReq.AddTag(ProduceTag);
        ProduceParams.Set_RequiredCellTags(ProduceReq);
        auto ProduceObj = utils_2d_grid_object::Add(ProduceObjEntity, ProduceParams);

        // ---- ElecObj: requires Electronics. ----
        auto ElecObjEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ElecParams = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1));
        auto ElecReq = FGameplayTagContainer();
        ElecReq.AddTag(ElecTag);
        ElecParams.Set_RequiredCellTags(ElecReq);
        auto ElecObj = utils_2d_grid_object::Add(ElecObjEntity, ElecParams);

        // ---- Assertions. ----
        auto ProduceAt55 = utils_2d_grid_placement::Get_CanPlace(
            Grid, ProduceObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(ProduceAt55.Get_CanPlace() == true,
            "ProduceObj @ (5,5): grid default Produce tag satisfies the requirement");

        auto ElecAt11 = utils_2d_grid_placement::Get_CanPlace(
            Grid, ElecObj, FIntPoint(1, 1),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(ElecAt11.Get_CanPlace() == true,
            "ElecObj @ (1,1): per-cell Electronics unions with grid default to satisfy the requirement");

        auto ElecAt55 = utils_2d_grid_placement::Get_CanPlace(
            Grid, ElecObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(ElecAt55.Get_CanPlace() == false,
            "ElecObj @ (5,5): only Produce present, Electronics missing -> placement rejected");

        FinishSuccess();
    }
}
