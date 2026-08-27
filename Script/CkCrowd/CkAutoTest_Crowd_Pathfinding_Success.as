// Language=angelscript

//============================================================================
// CK CROWD - AUTOMATION TEST: PATHFINDING SUCCESS
//============================================================================
//
// Verifies the CkNavigation API end-to-end on a known-good map:
//   1. Add a Transform feature anchored at world origin.
//   2. Bind OnPathReady -> expect signal with status Ready and >= 1 waypoint.
//   3. Issue Request_FindPath to (200, 0, 0) - short reachable target.
//   4. Assert the OnPathReady handler fires with Status == Ready and that
//      waypoint extraction yielded at least one point.
//
// REQUIREMENT: the test map must have a baked navmesh covering the area
// from (-500, -500, 0) to (500, 500, 0). TestGyms_CkTests_Level satisfies
// this once the Pathfinding gym's runtime-spawned floor is replaced by a
// test-map-side NavMeshBoundsVolume + floor mesh.
//
// If the navmesh is missing in the test map, the test fails with the
// NoNavData fail reason in the assertion message rather than EndProject /
// StartProject - that's the giveaway that the test fixture isn't set up.
//============================================================================

class UCk_AutoTest_Crowd_Pathfinding_Success : UCk_AutoTest_Base
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
            FCk_Delegate_Nav_OnPathFailed(this, n"OnUnexpectedFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Kick the navmesh: AutoTests_CkTests_Level has NavMeshBoundsVolume + floor at origin
        // but the bake is lazy. Triggering Build() here ensures the navmesh is ready by the
        // time the deferred-request queue drains. Mirrors CkAutoTest_Nav_PathQueuedDuringBake.
        utils_nav::Request_NavigationRebuild_ForTesting(LocalHandle);

        // Short, reachable target. Within 500cm of the start so any non-degenerate
        // navmesh covering origin satisfies it.
        auto Request = FCk_Request_Nav_FindPath(FVector(200.0, 0.0, 0.0));
        utils_nav::Request_FindPath(LocalHandle, Request);
    }

    UFUNCTION()
    private void OnPathReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }

        Assert_True(InResult.Get_Status() == ECk_Nav_PathStatus::Ready,
            f"Expected status Ready, got {InResult.Get_Status()}");

        Assert_True(InResult.Get_Waypoints().Num() >= 1,
            f"Expected at least 1 waypoint, got {InResult.Get_Waypoints().Num()}");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_nav::Get_PathResult(InHandle);
        const auto FailReason = Result.Get_Diagnostics().Get_LastFailReason();

        FinishFailure(f"Path query to reachable target (200, 0, 0) unexpectedly failed with reason {FailReason}. Test fixture may be missing a NavMeshBoundsVolume covering origin.");
    }
}

class ACk_AutoTest_Crowd_Pathfinding_Success_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Pathfinding_Success;
}
