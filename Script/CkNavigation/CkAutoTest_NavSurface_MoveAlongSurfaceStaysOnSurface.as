// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: A SHORT WALK STAYS ON THE SURFACE
//============================================================================
//
// Try_MoveAlongSurface is the constrain-to-mesh primitive every steering
// consumer leans on: it must return a point that is still walkable, never the
// raw requested end. Over open floor with no obstruction between the two, it
// must ALSO actually get there - a constrainer that answers with the start
// point for every call would satisfy "on the surface" and be useless.
//
// So the contract this pins is both halves at once:
//   1. Success (the segment was walkable end to end),
//   2. the reached point is where we asked to go, and
//   3. the reached point independently projects onto the surface.
//
// (3) is the load-bearing one - it re-asks the facade rather than trusting the
// move result's own status, so a status that lied would still be caught.
//
// Everything here goes through UCk_Utils_NavSurface_UE.
//============================================================================

class UCk_AutoTest_NavSurface_MoveAlongSurfaceStaysOnSurface : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    // Short enough to sit well inside the level's nav volume from the origin, long enough that
    // "answered with the start point" and "answered with the end point" are far apart.
    private const FVector WalkOffset = FVector(200.0, 0.0, 0.0);

    // Recast answers on poly centres and edge crossings rather than exact points, so the arrival
    // check is a tolerance, not an equality. 60uu is comfortably under the 200uu walk.
    private const float ArrivalToleranceUu = 60.0;

    // Tight box for the re-projection: a generous extent would let a point that had fallen OFF
    // the mesh snap back onto it and pass.
    private const FVector ConfirmHalfExtents = FVector(30.0, 30.0, 60.0);

    private FVector _FloorPoint = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",  n"Check_ProviderIsReady", 900);
        Add_Step(          "find a point that is genuinely on the floor", n"Step_FindFloorPoint");
        Add_Step(          "walk a short segment and land on the surface", n"Step_WalkAndAssert");
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
            FinishFailure(f"staging failed: the origin does not project onto the level's navmesh (status {Result.Get_Status()}) - the fixture, not the move-along contract, is broken");
            return;
        }

        _FloorPoint = Result.Get_Location();
    }

    UFUNCTION()
    private void Step_WalkAndAssert(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Target = _FloorPoint + WalkOffset;

        const auto Move = utils_nav_surface::Try_MoveAlongSurface(
            FCk_NavSurface_MoveAlongSurfaceQuery(_FloorPoint, Target));

        Assert_True(Move.Get_Status() == ECk_NavSurface_QueryStatus::Success,
            f"open floor separates {_FloorPoint} from {Target}, so the whole segment is walkable - got {Move.Get_Status()}");

        auto ArrivalDelta = Move.Get_ReachedLocation() - Target;
        ArrivalDelta.Z = 0.0;
        const auto ArrivalErrorUu = ArrivalDelta.Size();
        Assert_True(ArrivalErrorUu <= ArrivalToleranceUu,
            f"nothing blocks the segment, so the walk must actually arrive - stopped {ArrivalErrorUu}uu short of {Target} (ceiling {ArrivalToleranceUu}uu)");

        // Re-ask the facade rather than trusting the move's own status: the reached point has to be
        // walkable in its own right, or the constrainer handed back a point off the mesh.
        auto Confirm = FCk_NavSurface_ProjectionQuery(Move.Get_ReachedLocation());
        Confirm.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);
        Confirm.Set_SearchHalfExtents(ConfirmHalfExtents);

        const auto ConfirmResult = utils_nav_surface::Try_ProjectPoint(Confirm);
        Assert_True(ConfirmResult.Get_Status() == ECk_NavSurface_QueryStatus::Success,
            f"the point a move-along returns must itself be on the surface - re-projecting {Move.Get_ReachedLocation()} within {ConfirmHalfExtents} answered {ConfirmResult.Get_Status()}");
    }
}
