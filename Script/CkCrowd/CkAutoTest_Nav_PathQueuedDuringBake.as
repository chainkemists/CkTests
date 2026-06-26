// Language=angelscript

//============================================================================
// CK NAV — AUTOMATION TEST: PATH REQUEST QUEUED DURING NAVMESH BAKE
//============================================================================
//
// Verifies the FProcessor_Nav_HandleRequests deferred-queue path:
//   1. Add Transform feature so the request handler can resolve start location.
//   2. Trigger a navmesh rebuild via Request_NavigationRebuild_ForTesting.
//      This leaves IsNavigationBuildInProgress=true for several ticks.
//   3. Issue Request_FindPath to a reachable target IMMEDIATELY (same tick).
//   4. Bind OnPathReady → expect signal with status Ready and >= 1 waypoint
//      AFTER the rebuild completes (the queue should defer-then-drain).
//   5. Bind OnPathFailed → asserts the request is NOT failed during bake.
//
// Without the deferred queue, step 3's request would fail with
// StartProjectFailed (or NoNavData on the first frame) and the test would
// observe OnPathFailed instead of OnPathReady. With the queue in place, the
// request is parked, then re-issued by DoTick once the rebuild finishes.
//
// REQUIREMENT: AutoTests_CkTests_Level has a NavMeshBoundsVolume + static
// floor covering origin (added for the Crowd_Separation tests). This test
// reuses the same fixture.
//============================================================================

class UCk_AutoTest_Nav_PathQueuedDuringBake : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathReady(LocalHandle,
            FCk_Delegate_Nav_OnPathReady(this, n"OnPathReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_nav::BindTo_OnPathFailed(LocalHandle,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Force a rebuild so the very next FindPath request lands while
        // IsNavigationBuildInProgress=true. Exercises the queue path.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        // Reachable target within ±500 of origin (same as Pathfinding_Success).
        auto Request = FCk_Request_Nav_FindPath(FVector(200.0, 0.0, 0.0));
        utils_nav::Request_FindPath(LocalHandle, Request);
    }

    UFUNCTION()
    private void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult.Get_Status() == ECk_Nav_PathStatus::Ready,
            f"Expected status Ready after queued-then-drained request, got {InResult.Get_Status()}");

        Assert_True(InResult.Get_Waypoints().Num() >= 1,
            f"Expected at least 1 waypoint after queue drain, got {InResult.Get_Waypoints().Num()}");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_nav::Get_PathResult(InHandle);
        const auto FailReason = Result.Get_Diagnostics().Get_LastFailReason();

        FinishFailure(f"Path query failed during/after navmesh rebuild — deferred-request queue should have held the request until IsNavigationBuildInProgress flipped false. Reason: {FailReason}");
    }
}

class ACk_AutoTest_Nav_PathQueuedDuringBake_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Nav_PathQueuedDuringBake;
    default _TimeoutSeconds = 15.0f;
}
