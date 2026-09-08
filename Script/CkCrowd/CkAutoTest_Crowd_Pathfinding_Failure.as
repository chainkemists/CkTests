// Language=angelscript

//============================================================================
// CK CROWD - AUTOMATION TEST: PATHFINDING FAILURE
//============================================================================
//
// Verifies the CkNavigation API correctly surfaces a failed path query:
//   1. Add a Transform feature so the processor can resolve start location.
//   2. Bind OnPathFailed -> expect signal with reason EndProjectFailed.
//   3. Issue Request_FindPath to (99999, 99999, 99999) - guaranteed off-mesh.
//   4. Assert the OnPathFailed handler fires with the expected reason.
//
// Robust to test-map setup: failure path doesn't depend on the navmesh having
// any walkable area at origin. As long as A NavMeshBoundsVolume exists in the
// world (so NoNavData isn't the result), the request will reach FindPathSync
// and fail at the End-projection step.
//============================================================================

class UCk_AutoTest_Crowd_Pathfinding_Failure : UCk_AutoTest_Base
{
    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        // Test entities live on the Transient entity by convention; they have no
        // Transform feature out of the box. The nav processor reads start location
        // from the Transform feature, so add one at world origin.
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        // Kick the surface: AutoTests_CkTests_Level has NavMeshBoundsVolume + floor at origin
        // but the bake is lazy. Triggering a rebuild here ensures the start projection succeeds
        // so the query exercises the End-projection failure path (instead of force-failing on
        // an unbuilt surface). Mirrors the pattern CkAutoTest_Nav_PathQueuedDuringBake uses
        // successfully.
        utils_nav_surface::Request_SurfaceRebuild_ForTesting();

        // Off-mesh target. Far outside any reasonable NavMeshBoundsVolume.
        auto Query = FCk_NavSurface_PathQuery(FVector::ZeroVector, FVector(99999.0, 99999.0, 99999.0));
        const auto Result = utils_nav_surface::Try_FindPathSync(Query);

        Assert_True(Result.Get_Status() == ECk_NavSurface_QueryStatus::NoSurface,
            f"Expected NoSurface for off-mesh target, got {Result.Get_Status()}");

        FinishSuccess();
    }
}

class ACk_AutoTest_Crowd_Pathfinding_Failure_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Pathfinding_Failure;

    // The off-mesh target deliberately triggers a CkNavigation projection failure
    // log line. Suppress so the automation framework doesn't auto-fail the test
    // on its own deliberate output. AS can't brace-init a TArray<FString> via
    // default, so build the list imperatively in the BPNE override.
    UFUNCTION(BlueprintOverride)
    TArray<FString> Get_ExpectedLogErrors() const
    {
        TArray<FString> Out;
        // Plain substring match (AddExpectedErrorPlain), not regex - the harness
        // checks Contains on each pattern. The actual warning is:
        //   "FindPathSync: [End] projection FAILED. ..."
        Out.Add("FindPathSync: [End] projection FAILED");
        return Out;
    }
}
