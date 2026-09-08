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

        // Kick the surface: AutoTests_CkTests_Level has NavMeshBoundsVolume + floor at origin
        // but the bake is lazy. Triggering a rebuild here ensures the surface is ready by the
        // time the synchronous query below runs. Mirrors CkAutoTest_Nav_PathQueuedDuringBake.
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        // Short, reachable target. Within 500cm of the start so any non-degenerate
        // surface covering origin satisfies it.
        auto Query = FCk_NavSurface_PathQuery(FVector::ZeroVector, FVector(200.0, 0.0, 0.0));
        const auto Result = utils_nav_surface::Try_FindPathSync(Query);

        Assert_True(Result.Get_Status() == ECk_NavSurface_QueryStatus::Success,
            f"Expected status Success, got {Result.Get_Status()}. Test fixture may be missing a NavMeshBoundsVolume covering origin.");

        Assert_True(Result.Get_Waypoints().Num() >= 1,
            f"Expected at least 1 waypoint, got {Result.Get_Waypoints().Num()}");

        FinishSuccess();
    }
}

class ACk_AutoTest_Crowd_Pathfinding_Success_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Pathfinding_Success;
}
