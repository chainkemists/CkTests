// Language=angelscript

//============================================================================
// CK GRID - AUTOMATION TEST: AUTHORING SPEC -> RUNTIME GRID (DATA CONTRACT)
//============================================================================
//
// Proves the authoring data contract end-to-end: a grid Spec carrying
// disabled cells + per-cell tags + a named blocker yields a runtime grid where
// ALL of those are reflected, and a subsequent placement respects shape +
// blocker + tags.
//
// CONSTRUCTION PATH: (b) - replicate the Spec->runtime composition in AS.
//
//   The real authoring entry point UCk_2dGridSystem_EntityScript::Construct is
//   NOT cleanly drivable from an AngelScript autotest:
//     - Its `Spec` UPROPERTY is PRIVATE + EditAnywhere (a TObjectPtr to a
//       UDataAsset), so AS cannot assign it on a spawned instance.
//     - UCk_2dGridSystem_Spec::Resolve_GridParams() is a plain C++ method (not
//       a UFUNCTION), so it is not callable from AS.
//     - The EntityScript is spawner-driven (UCk_GenericEntityScript_UE injects
//       SpawnTransform); there is no AS-reachable "spawn with this Spec" path.
//   So this test reproduces EXACTLY what the EntityScript does:
//     1. Resolve_GridParams's field mapping (DefaultCellState=Enable,
//        ExceptionCoordinates = DisabledCells, DefaultCellTags) -> Add the grid.
//     2. The EntityScript's post-Add loop: per-cell Request_AddTag from
//        PerCellTags, and a named blocker per Blockers entry via
//        utils_2d_grid_blocker::Add with the Name.
//   This exercises the same runtime code paths the EntityScript drives.
//
// Spec content (per the task):
//   - 10x10 grid.
//   - DisabledCells = {(2,2)}.
//   - PerCellTags: Grid.Zone.Produce on (5,5).
//   - One named blocker Grid.Blocker.Wall covering (7,7)..(8,7).
//
// Assertions:
//   - (2,2) IsDisabled == true (ExceptionCoordinate, synchronous at Add).
//   - (5,5) carries the Produce tag (per-cell, immediate).
//   - named blocker resolves via Get_BlockerWithTag(Grid.Blocker.Wall)
//     (synchronous, record-backed).
//   - poll a tick for the deferred blocker stamp, then:
//       (7,7),(8,7) IsDisabled == true.
//   - placement respects it:
//       plain 1x1: CanPlace FALSE @ (2,2) (Disabled), FALSE @ (7,7) (blocker),
//                  TRUE @ an open cell.
//       1x1 requiring Produce: CanPlace TRUE @ (5,5), FALSE @ a cell lacking it.
//============================================================================

namespace Ck
{
    // Tags must be letter-leading (AngelScript exposes each tag as a global
    // constant; a "2dGrid..."/digit-leading identifier fails RegisterGlobalProperty).
    asset Asset_AutoTest_Grid_AuthoringSpecToRuntime_Tags of UCk_GameplayTags
    {
        GameplayTags.Add(n"Grid.Zone.Produce");
        GameplayTags.Add(n"Grid.Blocker.Wall");
    }
}

class UCk_AutoTest_Grid_AuthoringSpecToRuntime : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 10.0f;

    private FCk_Handle_2dGridSystem _Grid;
    private FCk_Handle_2dGridObject _PlainObj;
    private FCk_Handle_2dGridObject _ProduceObj;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto ProduceTag = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Zone.Produce");
        auto WallTag    = utils_gameplay_tag::ResolveGameplayTag(n"Grid.Blocker.Wall");

        // ---- Path (b): Resolve_GridParams's exact field mapping. ----
        // Resolve_GridParams: DefaultCellState=Enable, ExceptionCoordinates=DisabledCells,
        // DefaultCellTags=Spec.DefaultCellTags. The Spec here has no DefaultCellTags.
        auto GridOwner  = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto GridOwnerT = utils_transform::Add(
            GridOwner, FTransform::Identity, ECk_Replication::DoesNotReplicate);

        auto GP = FCk_Fragment_2dGridSystem_ParamsData(FIntPoint(10, 10), FVector2D(100.0f, 100.0f));
        GP.Set_DefaultCellState(ECk_EnableDisable::Enable);
        auto DisabledCells = TArray<FIntPoint>();
        DisabledCells.Add(FIntPoint(2, 2));
        GP.Set_ExceptionCoordinates(DisabledCells);
        _Grid = utils_2d_grid_system::Add(GridOwnerT, GP);

        // ---- EntityScript post-Add: PerCellTags -> Produce on (5,5). ----
        auto Cell55 = utils_2d_grid_system::Get_CellAt(_Grid, FIntPoint(5, 5));
        Assert_True(ck::IsValid(Cell55), "Cell (5,5) must resolve to a valid handle");
        utils_2d_grid_cell::Request_AddTag(Cell55, ProduceTag);

        // ---- EntityScript post-Add: one named blocker over (7,7)..(8,7). ----
        auto BlockerEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto BP = FCk_Fragment_2dGridBlocker_ParamsData(_Grid, FIntPoint(7, 7), FIntPoint(8, 7));
        BP.Set_Name(WallTag);
        utils_2d_grid_blocker::Add(BlockerEntity, BP);

        // ---- Synchronous contract checks. ----
        auto Cell22 = utils_2d_grid_system::Get_CellAt(_Grid, FIntPoint(2, 2));
        Assert_True(ck::IsValid(Cell22), "Cell (2,2) must resolve to a valid handle");
        Assert_True(utils_2d_grid_cell::Get_IsDisabled(Cell22),
            "DisabledCells -> ExceptionCoordinate (2,2) must be disabled at construction");

        Assert_True(utils_2d_grid_cell::Get_Tags(Cell55).HasTag(ProduceTag),
            "PerCellTags must place the Produce tag on cell (5,5)");

        auto Resolved = utils_2d_grid_blocker::Get_BlockerWithTag(_Grid, WallTag);
        Assert_True(ck::IsValid(Resolved),
            "Named blocker Grid.Blocker.Wall must resolve via Get_BlockerWithTag");

        // ---- Objects for the placement checks. ----
        auto PlainEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _PlainObj = utils_2d_grid_object::Add(
            PlainEntity, FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1)));

        auto ProduceEntity = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        auto ProduceParams = FCk_Fragment_2dGridObject_ParamsData(FIntPoint(1, 1));
        auto ProduceReq = FGameplayTagContainer();
        ProduceReq.AddTag(ProduceTag);
        ProduceParams.Set_RequiredCellTags(ProduceReq);
        _ProduceObj = utils_2d_grid_object::Add(ProduceEntity, ProduceParams);

        // Blocker stamp is processor-driven (deferred); poll until (7,7) is disabled.
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

        // Wait for the named blocker to stamp its footprint before querying placement.
        if (!IsCellDisabled(FIntPoint(7, 7)) || !IsCellDisabled(FIntPoint(8, 7))) { return; }

        Assert_True(IsCellDisabled(FIntPoint(7, 7)),
            "Blocker Grid.Blocker.Wall must disable cell (7,7)");
        Assert_True(IsCellDisabled(FIntPoint(8, 7)),
            "Blocker Grid.Blocker.Wall must disable cell (8,7)");

        // ---- Placement respects shape + blocker. ----
        auto PlainAt22 = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _PlainObj, FIntPoint(2, 2),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(PlainAt22.Get_CanPlace() == false,
            "1x1 @ (2,2): disabled-by-Spec cell rejects placement");

        auto PlainAt77 = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _PlainObj, FIntPoint(7, 7),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(PlainAt77.Get_CanPlace() == false,
            "1x1 @ (7,7): blocker-disabled cell rejects placement");

        auto PlainAt00 = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _PlainObj, FIntPoint(0, 0),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(PlainAt00.Get_CanPlace() == true,
            "1x1 @ (0,0): open cell accepts placement");

        // ---- Placement respects per-cell tags. ----
        auto ProduceAt55 = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _ProduceObj, FIntPoint(5, 5),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(ProduceAt55.Get_CanPlace() == true,
            "Produce-requiring 1x1 @ (5,5): per-cell Produce tag satisfies requirement");

        auto ProduceAt00 = utils_2d_grid_placement::Get_CanPlace(
            _Grid, _ProduceObj, FIntPoint(0, 0),
            ECk_CardinalRotation::None, ECk_GridConnectivity::Ignore);
        Assert_True(ProduceAt00.Get_CanPlace() == false,
            "Produce-requiring 1x1 @ (0,0): no Produce tag there -> placement rejected");

        FinishSuccess();
    }
}
