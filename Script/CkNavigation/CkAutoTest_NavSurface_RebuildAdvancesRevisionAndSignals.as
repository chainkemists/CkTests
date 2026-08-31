// Language=angelscript
//============================================================================
// CK NAV SURFACE - AUTOMATION TEST: A REBUILD ADVANCES THE REVISION AND SIGNALS
//============================================================================
//
// The facade exposes one navigation-revision observer for the whole suite -
// Get_SurfaceRevision plus BindTo_OnSurfaceRebuilt - and consumers use the two
// together: the signal says "something changed", the revision says "which
// change". A build that advanced the counter without broadcasting, or
// broadcast without advancing, breaks every cache invalidation downstream, and
// neither half shows up if only the other is asserted.
//
// The wait is on the SIGNAL, not on the counter, because the signal is what
// the assertion is really about and it is emitted by the same processor pass
// that publishes the new revision - gating on the counter would release one
// pass early and read a broadcast that has not happened yet.
//
// The binding uses IgnorePayloadInFlight on purpose: with the default replay
// policy a rebuild broadcast already in flight when this test binds would fire
// immediately and the test would pass without its own rebuild ever running.
//
// SHARED-WORLD CAVEAT: the revision is global to the PIE world, so a
// concurrent navmesh change from elsewhere could in principle satisfy the
// wait. The tests in this map run one at a time and this test triggers its own
// rebuild, so in practice the observed advance is this test's - but the
// assertion is "a rebuild was observed", not "exactly one, and it was mine".
//
// Everything here goes through UCk_Utils_NavSurface_UE.
//============================================================================

class UCk_AutoTest_NavSurface_RebuildAdvancesRevisionAndSignals : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 25.0f;

    private int64 _RevisionAtStart = 0;
    private int32 _RebuiltCount = 0;
    private int32 _RebuildRequestCompletions = 0;
    private bool _RebuildRequestSucceeded = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        Add_Step_WaitUntil("the nav surface provider settles at Ready",       n"Check_ProviderIsReady", 900);
        Add_Step(          "capture the revision and ask for a rebuild",       n"Step_RequestRebuild");
        Add_Step_WaitUntil("the surface reports itself rebuilt",               n"Check_RebuiltSignalFired", 2500);
        Add_Step_WaitUntil("the provider settles back at Ready",               n"Check_ProviderIsReady", 2500);
        Add_Step(          "the revision advanced and the build has finished", n"Step_AssertRevisionAdvanced");
        Run_Steps(InHandle);
    }

    UFUNCTION(BlueprintOverride)
    void DoEndPlay(FCk_Handle InHandle)
    {
        // The signal lives on the world's transient entity, which outlives this test entity by the
        // whole PIE session - an unbound-on-exit binding would keep firing into a dead script for
        // every later test that touches the navmesh.
        utils_nav_surface::UnbindFrom_OnSurfaceRebuilt(
            FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"));
    }

    UFUNCTION()
    private void Check_ProviderIsReady(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(utils_nav_surface::Get_ProviderHealth() == ECk_NavSurface_ProviderHealth::Ready);
    }

    UFUNCTION()
    private void Step_RequestRebuild(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        _RevisionAtStart = utils_nav_surface::Get_SurfaceRevision();

        utils_nav_surface::BindTo_OnSurfaceRebuilt(
            FCk_Delegate_NavSurface_OnSurfaceRebuilt(this, n"OnSurfaceRebuilt"),
            ECk_Signal_BindingPolicy::IgnorePayloadInFlight,
            ECk_Signal_PostFireBehavior::DoNothing);

        utils_nav_surface::Request_SurfaceRebuild_ForTesting(
            FCk_Delegate_Request_OnCompleted(this, n"OnRebuildRequestCompleted"));

        Assert_Equals_Int(_RebuildRequestCompletions, 1,
            "Request_SurfaceRebuild_ForTesting kicks the provider inline, so its completion is owed on the calling stack");
        Assert_True(_RebuildRequestSucceeded,
            "a provider that resolved Ready must accept a rebuild request - a Failed_NotEnqueued here means the facade could not reach it");
    }

    UFUNCTION()
    private void OnRebuildRequestCompleted(FCk_Handle InRequestOwner, ECk_Request_OperationResult InResult)
    {
        _RebuildRequestCompletions += 1;
        _RebuildRequestSucceeded = InResult == ECk_Request_OperationResult::Succeeded;
    }

    UFUNCTION()
    private void OnSurfaceRebuilt(FCk_Handle InHandle)
    {
        _RebuiltCount += 1;
    }

    UFUNCTION()
    private void Check_RebuiltSignalFired(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(_RebuiltCount > 0);
    }

    UFUNCTION()
    private void Step_AssertRevisionAdvanced(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        const auto RevisionNow = utils_nav_surface::Get_SurfaceRevision();

        Assert_True(_RebuiltCount >= 1,
            f"BindTo_OnSurfaceRebuilt must deliver the rebuild it was bound before - fired {_RebuiltCount} times");

        Assert_True(RevisionNow > _RevisionAtStart,
            f"the revision is what tells a consumer WHICH change it saw, so a broadcast without an advance is a broken pair - was {_RevisionAtStart}, now {RevisionNow}");

        Assert_False(utils_nav_surface::Get_IsBuildInProgress(),
            "the surface reported itself rebuilt and the provider read back Ready, so no build may still be running");
    }
}
