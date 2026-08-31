// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: REACHABILITY SEPARATES CONNECTED FROM OFF-MESH
//============================================================================
//
// Get_IsReachable answers with a three-valued enum on purpose: Reachable,
// Unreachable, and Unknown_ProviderNotReady - "I could not tell" is NOT
// "no". This test pins the two ends a caller can actually act on, on a map
// where the provider is known Ready:
//
//   - two points on the same floor  -> Reachable
//   - a floor point and a point 60,000uu off the mesh -> NOT Reachable
//
// The off-mesh half asserts the negative FIRST as "not Reachable" - which is
// the decision every consumer makes - and only then names Unreachable as the
// exact value. Reading it in that order is deliberate: if the adapter ever
// starts answering Unknown_ProviderNotReady here, the first assertion still
// holds and the second one says precisely what changed.
//
// Everything here goes through UCk_Utils_NavSurface_UE.
//============================================================================

class UCk_AutoTest_NavSurface_ReachabilityOnFloorAndOffMesh : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    private const FVector NearbyOffset = FVector(300.0, 0.0, 0.0);
    private const FVector OffMeshPoint = FVector(60000.0, 60000.0, 60000.0);

    private FVector _FloorPoint = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",   n"Check_ProviderIsReady", 900);
        Add_Step(          "find a point that is genuinely on the floor",  n"Step_FindFloorPoint");
        Add_Step(          "two points on the same floor are reachable",   n"Step_AssertSameFloorReachable");
        Add_Step(          "a point off the mesh is not reachable",        n"Step_AssertOffMeshNotReachable");
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
            FinishFailure(f"staging failed: the origin does not project onto the level's navmesh (status {Result.Get_Status()}) - the fixture, not the reachability contract, is broken");
            return;
        }

        _FloorPoint = Result.Get_Location();
    }

    UFUNCTION()
    private void Step_AssertSameFloorReachable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Target = _FloorPoint + NearbyOffset;

        const auto Reachability = utils_nav_surface::Get_IsReachable(
            FCk_NavSurface_ReachabilityQuery(_FloorPoint, Target));

        Assert_True(Reachability == ECk_NavSurface_Reachability::Reachable,
            f"{_FloorPoint} and {Target} sit on the same unobstructed floor - got {Reachability}");
    }

    UFUNCTION()
    private void Step_AssertOffMeshNotReachable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Reachability = utils_nav_surface::Get_IsReachable(
            FCk_NavSurface_ReachabilityQuery(_FloorPoint, OffMeshPoint));

        Assert_True(Reachability != ECk_NavSurface_Reachability::Reachable,
            f"nothing walkable exists anywhere near {OffMeshPoint}, so claiming it is Reachable would send a caller walking at nothing");

        Assert_True(Reachability == ECk_NavSurface_Reachability::Unreachable,
            f"the provider is Ready, so the goal's projection failing is a definite Unreachable rather than an 'I cannot tell' - got {Reachability}");
    }
}
