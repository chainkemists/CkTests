// Language=angelscript

//============================================================================
// CK GRID — AUTOMATION TEST: NAMED BLOCKER TOGGLE
//============================================================================
//
// Verifies a GameplayTag-named blocker is findable at runtime and can be
// toggled on/off via the resolved handle:
//
//   0. Add a named blocker; Get_BlockerWithTag resolves it (synchronous,
//      record-backed). The active blocker then stamps cell (3,3) Disabled.
//   1. Request_SetActive(false) on the RESOLVED handle -> cell (3,3) Enabled.
//   2. Request_SetActive(true)  on the RESOLVED handle -> cell (3,3) Disabled.
//
// Get_BlockerWithTag for an unknown tag must return an invalid handle, and the
// resolved handle must equal the entity we added.
//============================================================================

namespace Ck
{
    // Registered up front so the tags resolve (mirrors CkAutoTest_Grid_TagFilter). Tags must be
    // letter-leading: AngelScript exposes each gameplay tag as a global constant, and an identifier
    // cannot start with a digit (a "2dGridBlocker..." tag fails RegisterGlobalProperty).
    asset Asset_AutoTest_Grid_BlockerNamedToggle_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Grid.Blocker.Test.Doorway");
        GameplayTags.Add(n"Grid.Blocker.Test.Absent");
    }
}

class UCk_AutoTest_Grid_BlockerNamedToggle : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem      _Grid;
    private FCk_Handle                   _BlockerEntity;
    private FCk_Handle_2dGridBlocker     _Resolved;
    private int32                        _Step = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto LocalHandle = InHandle;

        auto BlockerTag  = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Blocker.Test.Doorway");
        auto UnknownTag  = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Blocker.Test.Absent");

        auto GridOwner  = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        // ---- Named blocker over cell (3,3). ----
        _BlockerEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto BP = FCk_Fragment_2dGridBlocker_ParamsData(_Grid, FIntPoint(3, 3), FIntPoint(3, 3));
        BP.Set_Name(BlockerTag);
        utils_2d_grid_blocker::Add(_BlockerEntity, BP);

        // ---- Lookup is synchronous (record is connected inside Add). ----
        _Resolved = utils_2d_grid_blocker::Get_BlockerWithTag(_Grid, BlockerTag);
        Assert_True(ck::IsValid(_Resolved),
            "Get_BlockerWithTag resolves the named blocker");
        Assert_True(_Resolved == _BlockerEntity.As_2dGridBlocker(),
            "Resolved blocker handle equals the added blocker entity");

        auto Absent = utils_2d_grid_blocker::Get_BlockerWithTag(_Grid, UnknownTag);
        Assert_True(ck::Is_NOT_Valid(Absent),
            "Get_BlockerWithTag returns invalid for an unknown tag");

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    private bool IsCellDisabled(FIntPoint InCoord)
    {
        auto Cell = utils_2d_grid_system::Get_CellAt(_Grid, InCoord);
        return ck::IsValid(Cell) ? utils_2d_grid_cell::Get_IsDisabled(Cell) : false;
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Coord = FIntPoint(3, 3);

        if (_Step == 0)
        {
            // Active named blocker stamps the cell.
            if (IsCellDisabled(Coord))
            {
                Assert_True(true, "Active named blocker disables covered cell (3,3)");
                utils_2d_grid_blocker::Request_SetActive(_Resolved, false);
                _Step = 1;
            }
            return;
        }

        if (_Step == 1)
        {
            // Toggling off via the resolved handle re-enables the cell.
            if (!IsCellDisabled(Coord))
            {
                Assert_True(true, "Disabling resolved blocker re-enables covered cell (3,3)");
                utils_2d_grid_blocker::Request_SetActive(_Resolved, true);
                _Step = 2;
            }
            return;
        }

        if (_Step == 2)
        {
            // Toggling back on disables the cell again.
            if (IsCellDisabled(Coord))
            {
                Assert_True(true, "Re-enabling resolved blocker disables covered cell (3,3) again");
                FinishSuccess();
            }
            return;
        }
    }
}
