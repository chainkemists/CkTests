// Language=angelscript

//============================================================================
// CK AUTOMATION TEST — NETWORKED GRID OCCUPANCY REPLICATION
//============================================================================
//
// Server calls Request_Place on its occupancy-capable grid, placing a 1x1
// GridObject occupant at anchor (2,2); assert the resulting cell occupancy
// replicates to the client via the FCk_RepData_2dGridPlacements handler.
//
// Server and client each have their own grid + occupant child entities created
// by UCk_AutoTest_NetSubject_GridEntityScript_UE during Construct (symmetric
// setup — mandatory for the container replication pattern), stashed on the
// actor as `_TestGrid` / `_TestOccupant`. The placement record's contents
// (the {Occupant, Anchor, Rotation, Cells} entries) flow server->client; the
// client-side ClientOnly SyncReplication processor rebuilds a placement entity
// from the entry's Cells and the reconcile pass stamps the `Occupied` tag — so
// the client observes Get_IsOccupied((2,2)) flip true.
//
// Surface: Ck.Grid.Net.AS_Grid_OccupancyReplicates
//============================================================================

class UCk_AutoTest_Net_Grid_OccupancyReplicates : UCk_AutoTest_NetBase
{
    default _NetSubjectClass = ACk_AutoTest_NetSubject_Grid_UE;

    // Anchor + the single cell a 1x1 occupant occupies when placed there.
    private FIntPoint Get_TargetCell() const { return FIntPoint(2, 2); }

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Subject = Get_SubjectEntity();
        if (ck::Is_NOT_Valid(Subject))
        { FinishFailure("subject not found — harness misconfigured?"); return; }

        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto GridActor = Cast<ACk_AutoTest_NetSubject_Grid_UE>(SubjectActor);
        if (GridActor == nullptr)
        { FinishFailure("subject actor isn't a grid net-subject"); return; }

        auto Grid = GridActor._TestGrid;
        if (ck::Is_NOT_Valid(Grid))
        { FinishFailure("grid handle not populated by entity-script"); return; }

        auto Occupant = GridActor._TestOccupant;
        if (ck::Is_NOT_Valid(Occupant))
        { FinishFailure("occupant handle not populated by entity-script"); return; }

        if (utils_net::Get_HasAuthority(Subject))
        {
            // Server-side: drive the placement, then finish. The 1x1 occupant at anchor (2,2)
            // occupies exactly cell (2,2). Request_Place is authority-gated.
            utils_2d_grid_placement::Request_Place(
                Grid, Occupant, Get_TargetCell(), ECk_CardinalRotation::None);
            FinishSuccess();
            return;
        }

        // Client-side: wait for the replicated occupancy to arrive and stamp the cell.
        WaitOneFrame(n"OnPollTick");
    }

    private int _PollCount = 0;
    private const int kPollBudget = 400;

    UFUNCTION()
    private void OnPollTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        _PollCount++;

        auto Subject = Get_SubjectEntity();
        auto SubjectActor = utils_owning_actor::Get_EntityOwningActor(Subject);
        auto GridActor = Cast<ACk_AutoTest_NetSubject_Grid_UE>(SubjectActor);
        if (GridActor == nullptr)
        { WaitOneFrame(n"OnPollTick"); return; }

        auto Grid = GridActor._TestGrid;
        if (ck::Is_NOT_Valid(Grid))
        { WaitOneFrame(n"OnPollTick"); return; }

        if (utils_2d_grid_occupancy::Get_IsOccupied(Grid, Get_TargetCell()))
        {
            FinishSuccess();
            return;
        }

        if (_PollCount > kPollBudget)
        { FinishFailure("client never observed replicated occupancy"); return; }

        WaitOneFrame(n"OnPollTick");
    }
}
