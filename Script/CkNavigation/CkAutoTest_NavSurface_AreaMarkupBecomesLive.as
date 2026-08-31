// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: A PAINTED AREA BECOMES LIVE ON THE SURFACE
//============================================================================
//
// Request_AreaMarkup is the provider-neutral replacement for reaching at
// UNavArea subclasses directly, and Get_IsMarkupLive is the named condition
// every fixture that paints one is supposed to settle on instead of counting
// frames. This test is the contract for that pair:
//
//   paint -> the request drains -> the tiles carry the area -> IsMarkupLive.
//
// WHAT THIS DELIBERATELY DOES NOT ASSERT. The well-known `Nav.Area.Restricted`
// area is walkable at normal cost by design (see UCk_NavArea_Restricted):
// traversal semantics are owned by each agent's query filter, and no filter
// registered anywhere in the suite today excludes it. So there is no
// exclusion for a projection or a reachability query behind the box to
// observe, and asserting one would be asserting a capability the markup
// request does not have. Supplying an unmapped filter tag to manufacture one
// is worse than useless: the adapter fires an ensure for an unmapped tag,
// which fails the test for the wrong reason. What IS guaranteed - that the
// paint reaches the surface and reports itself live - is what is asserted.
//
// SHARED-WORLD HYGIENE: the carve is registered for cleanup, so it is
// unpainted on every exit path including the harness's own timeout. It is also
// benign while it stands, precisely because Restricted costs the same as bare
// floor to every filter in the suite.
//
// Everything here goes through UCk_Utils_NavSurface_UE.
//============================================================================

class UCk_AutoTest_NavSurface_AreaMarkupBecomesLive : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 30.0f;

    // Off the x-axis corridor the crowd fixtures stage in, and well inside the level's nav volume.
    private const FVector PaintCentreCandidate = FVector(0.0, 700.0, 0.0);

    // Comfortably larger than a Recast tile cell, so the polygon under the centre is fully inside
    // the painted box rather than straddling its edge.
    private const FVector PaintHalfExtents = FVector(120.0, 120.0, 120.0);

    private FCk_Handle_NavSurfaceMarkup _Markup;
    private FVector _PaintCentre = FVector::ZeroVector;
    private int32 _MarkupCompletions = 0;
    private bool _MarkupSucceeded = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready", n"Check_ProviderIsReady", 900);
        Add_Step(          "find walkable ground to paint over",         n"Step_FindPaintCentre");
        Add_Step(          "paint an exclusion box through the facade",  n"Step_PaintMarkup");
        Add_Step_WaitUntil("the paint request drains",                   n"Check_MarkupRequestCompleted", 900);
        Add_Step(          "the markup exists and the tiles are asked to rebuild", n"Step_AssertPaintedAndRebuild");
        Add_Step_WaitUntil("the painted area is live on the surface",    n"Check_MarkupIsLive", 2500);
        Add_Step(          "the facade agrees the markup is live",       n"Step_AssertLive");
        Run_Steps(InHandle);
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_FindPaintCentre(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Query = FCk_NavSurface_ProjectionQuery(PaintCentreCandidate);
        Query.Set_Mode(ECk_NavSurface_ProjectionMode::Closest);

        const auto Result = utils_nav_surface::Try_ProjectPoint(Query);
        if (Result.Get_Status() != ECk_NavSurface_QueryStatus::Success)
        {
            FinishFailure(f"staging failed: {PaintCentreCandidate} does not project onto the level's navmesh (status {Result.Get_Status()}) - there is nothing there to paint over, so the fixture is broken, not the markup contract");
            return;
        }

        _PaintCentre = Result.Get_Location();
    }

    UFUNCTION()
    private void Step_PaintMarkup(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        auto Request = FCk_Request_NavSurface_AreaMarkup(
            utils_shapes::Make_Box(FCk_ShapeBox_Dimensions(PaintHalfExtents)),
            utils_gameplay_tag::ResolveGameplayTag(n"Nav.Area.Restricted"));
        Request.Set_WorldTransform(FTransform(FRotator::ZeroRotator, _PaintCentre, FVector::OneVector));

        _Markup = utils_nav_surface::Request_AreaMarkup(
            Request, FCk_Delegate_Request_OnCompleted(this, n"OnMarkupCompleted"));

        // The markup entity is parented to the WORLD, not to this runner, so the harness's own
        // subtree teardown never reaches it - registering it here is what unpaints the carve.
        Track_ForCleanup(FCk_Handle(_Markup));

        Assert_True(ck::IsValid(_Markup),
            "Request_AreaMarkup hands back the handle the caller needs to observe and release the paint - an invalid one leaves the carve unreachable");

        Assert_Equals_Int(_MarkupCompletions, 0,
            "the paint is deferred - its completion is owed when the request DRAINS, not when it is enqueued");
    }

    UFUNCTION()
    private void OnMarkupCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _MarkupCompletions += 1;
        _MarkupSucceeded = InResult == ECk_Request_OperationResult::Succeeded;
    }

    UFUNCTION()
    private void Check_MarkupRequestCompleted(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_MarkupCompletions > 0);
    }

    UFUNCTION()
    private void Step_AssertPaintedAndRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_Equals_Int(_MarkupCompletions, 1,
            "a request completion is a fire-exactly-once guarantee");
        Assert_True(_MarkupSucceeded,
            "Nav.Area.Restricted is a registered provider area and the box has extent, so the paint must be accepted");
        Assert_True(utils_nav_surface::Has(FCk_Handle(_Markup)),
            "the handle Request_AreaMarkup returned must carry the markup feature");

        utils_nav_surface::Request_SurfaceRebuild_ForTesting();
    }

    UFUNCTION()
    private void Check_MarkupIsLive(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_IsMarkupLive(_Markup));
    }

    UFUNCTION()
    private void Step_AssertLive(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        Assert_True(utils_nav_surface::Get_IsMarkupLive(_Markup),
            f"the paint at {_PaintCentre} drained and the tiles rebuilt, so the surface must report the area live - this is the condition every markup fixture settles on instead of counting frames");
    }
}
