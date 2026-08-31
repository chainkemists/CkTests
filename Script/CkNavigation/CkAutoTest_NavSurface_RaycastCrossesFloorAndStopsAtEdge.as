// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: A SURFACE RAYCAST CROSSES FLOOR, STOPS AT AN EDGE
//============================================================================
//
// Try_SurfaceRaycast reports Success when the WHOLE segment is walkable and
// Blocked when it hits a boundary, carrying the boundary point in
// _HitLocation. Both are asserted here, because either one alone is satisfied
// by a degenerate implementation (always-Success, or always-Blocked-at-start).
//
// The blocking feature is the navmesh's OWN outer edge rather than a painted
// obstacle: the level's nav volume reaches roughly |x| <= 1000, so a ray fired
// 20,000uu out is guaranteed to leave the mesh, and the fixture needs nothing
// staged, nothing rebuilt, and leaves nothing behind for the tests that follow.
//
// The hit point is bounded from BOTH sides. A hit within 100uu of the start
// would mean the ray never left the poly it began on (a stopped-at-start
// implementation); a hit at the full segment length would mean nothing was
// actually clipped.
//
// Everything here goes through UCk_Utils_NavSurface_UE.
//============================================================================

class UCk_AutoTest_NavSurface_RaycastCrossesFloorAndStopsAtEdge : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private const FVector OpenSegment = FVector(200.0, 0.0, 0.0);
    private const FVector OffMeshSegment = FVector(20000.0, 0.0, 0.0);

    private const float MinClipDistanceUu = 100.0;
    private const float MaxClipDistanceUu = 20000.0;

    private FVector _FloorPoint = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",     n"Check_ProviderIsReady", 900);
        Add_Step(          "find a point that is genuinely on the floor",    n"Step_FindFloorPoint");
        Add_Step(          "a ray across open floor is not blocked",         n"Step_CastAcrossOpenFloor");
        Add_Step(          "a ray off the mesh is blocked at the edge",      n"Step_CastOffTheMesh");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_FindFloorPoint(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Query = FCk_NavSurface_ProjectionQuery(FVector::ZeroVector);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        const auto Result = utils_nav_surface::Try_ProjectPoint(Query);
        if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"staging failed: the origin does not project onto the level's navmesh (status {Result.Get_Status()}) - the fixture, not the raycast contract, is broken");
            return;
        }

        _FloorPoint = Result.Get_Location();
    }

    UFUNCTION()
    private void Step_CastAcrossOpenFloor(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Target = _FloorPoint + OpenSegment;

        const auto Result = utils_nav_surface::Try_SurfaceRaycast(
            FCk_NavSurface_RaycastQuery(_FloorPoint, Target));

        Assert_True(Result.Get_Status() == ECk_NavSurface_QueryStatus::Success,
            f"Success means the whole segment is walkable, and {_FloorPoint} -> {Target} is open floor - got {Result.Get_Status()}");
    }

    UFUNCTION()
    private void Step_CastOffTheMesh(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Target = _FloorPoint + OffMeshSegment;

        const auto Result = utils_nav_surface::Try_SurfaceRaycast(
            FCk_NavSurface_RaycastQuery(_FloorPoint, Target));

        Assert_True(Result.Get_Status() == ECk_NavSurface_QueryStatus::Blocked,
            f"the segment runs 20,000uu past the level's nav volume, so it must be reported Blocked at the mesh boundary - got {Result.Get_Status()}");

        const auto ClipDistanceUu = (Result.Get_HitLocation() - _FloorPoint).Size();
        Assert_True(ClipDistanceUu >= MinClipDistanceUu,
            f"the ray was clipped {ClipDistanceUu}uu from its start - anything under {MinClipDistanceUu}uu means it never left the polygon it began on, which is not the boundary the test is asking about");
        Assert_True(ClipDistanceUu < MaxClipDistanceUu,
            f"the ray was reported blocked at {ClipDistanceUu}uu, i.e. at the far end of the segment - nothing was actually clipped");
    }
}
