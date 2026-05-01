// Language=angelscript

//============================================================================
// CK CROWD — AUTOMATION TEST: PATHFINDING FAILURE
//============================================================================
//
// Verifies the CkNavigation API correctly surfaces a failed path query:
//   1. Add a Transform feature so the processor can resolve start location.
//   2. Bind OnPathFailed → expect signal with reason EndProjectFailed.
//   3. Issue Request_FindPath to (99999, 99999, 99999) — guaranteed off-mesh.
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
        auto LocalHandle = InHandle;

        // Test entities live on the Transient entity by convention; they have no
        // Transform feature out of the box. The nav processor reads start location
        // from the Transform feature, so add one at world origin.
        utils_transform::Add(LocalHandle,
            FTransform(FRotator::ZeroRotator, FVector::ZeroVector, FVector::OneVector),
            ECk_Replication::DoesNotReplicate);

        utils_nav::BindTo_OnPathFailed(LocalHandle,
            FCk_Delegate_Nav_OnPathFailed(this, n"OnPathFailed"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_nav::BindTo_OnPathReady(LocalHandle,
            FCk_Delegate_Nav_OnPathReady(this, n"OnUnexpectedReady"),
            ECk_Signal_BindingPolicy::FireIfPayloadInFlightThisFrame,
            ECk_Signal_PostFireBehavior::DoNothing);

        // Off-mesh target. Far outside any reasonable NavMeshBoundsVolume.
        auto Request = FCk_Request_Nav_FindPath(FVector(99999.0, 99999.0, 99999.0));
        utils_nav::Request_FindPath(LocalHandle, Request);
    }

    UFUNCTION()
    private void OnPathFailed(FCk_Handle InHandle)
    {
        if (IsFinished()) { return; }

        const auto Result = utils_nav::Get_PathResult(InHandle);
        const auto FailReason = Result.Get_Diagnostics().Get_LastFailReason();

        Assert_True(FailReason == ECk_Nav_PathFailReason::EndProjectFailed,
            f"Expected EndProjectFailed for off-mesh target, got {FailReason}");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnUnexpectedReady(FCk_Handle InHandle, FCk_Nav_PathResult InResult)
    {
        if (IsFinished()) { return; }
        FinishFailure(f"Path query to off-mesh target (99999, 99999, 99999) unexpectedly returned Ready with {InResult.Get_Waypoints().Num()} waypoints");
    }
}

class ACk_AutoTest_Crowd_Pathfinding_Failure_Actor : ACk_AutoTestRunner
{
    default _TestEntityScriptClass = UCk_AutoTest_Crowd_Pathfinding_Failure;
}
