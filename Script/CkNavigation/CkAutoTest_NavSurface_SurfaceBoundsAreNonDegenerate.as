// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: SURFACE BOUNDS DESCRIBE THE REAL SURFACE
//============================================================================
//
// Get_SurfaceBounds is the facade's "where is there any surface at all"
// readout - consumers size grids, spatial partitions and debug draws off it.
// The failure mode worth pinning is the quiet one: a provider that cannot
// resolve NavData returns FBox{ForceInit}, i.e. a degenerate box, which reads
// as a perfectly ordinary value everywhere downstream.
//
// So the box is checked for horizontal extent (a single flat floor makes a
// legitimate zero-thickness Z, so Z only has to be non-negative) AND for containing a
// point the facade independently agrees is walkable. The second half is what
// makes this more than a not-zero check: a box with extent but in the wrong
// place would pass the first and fail the second.
//
// Everything here goes through UCk_Utils_NavSurface_UE.
//============================================================================

class UCk_AutoTest_NavSurface_SurfaceBoundsAreNonDegenerate : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 15.0f;

    // A baked navmesh volume is metres across; 1uu is only there to reject the ForceInit box.
    private const float MinExtentUu = 1.0;

    private FVector _FloorPoint = FVector::ZeroVector;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",  n"Check_ProviderIsReady", 900);
        Add_Step(          "find a point that is genuinely on the floor", n"Step_FindFloorPoint");
        Add_Step(          "the bounds have extent and contain it",       n"Step_AssertBounds");
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
            FinishFailure(f"staging failed: the origin does not project onto the level's navmesh (status {Result.Get_Status()}) - the fixture, not the bounds contract, is broken");
            return;
        }

        _FloorPoint = Result.Get_Location();
    }

    UFUNCTION()
    private void Step_AssertBounds(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto Bounds = utils_nav_surface::Get_SurfaceBounds();
        const auto Size = Bounds.Max - Bounds.Min;

        Assert_True(Size.X > MinExtentUu && Size.Y > MinExtentUu && Size.Z >= 0.0,
            f"a Ready provider must describe a real area - Get_SurfaceBounds answered min {Bounds.Min} max {Bounds.Max}, extent {Size}. A negative or zero horizontal extent is the ForceInit box an unresolved provider returns (a flat single-floor navmesh legitimately has zero Z thickness).");

        const auto ContainsFloorPoint =
               _FloorPoint.X >= Bounds.Min.X && _FloorPoint.X <= Bounds.Max.X
            && _FloorPoint.Y >= Bounds.Min.Y && _FloorPoint.Y <= Bounds.Max.Y
            && _FloorPoint.Z >= Bounds.Min.Z && _FloorPoint.Z <= Bounds.Max.Z;

        Assert_True(ContainsFloorPoint,
            f"the facade just projected {_FloorPoint} onto the surface, so the surface bounds must contain it - min {Bounds.Min} max {Bounds.Max}");
    }
}
