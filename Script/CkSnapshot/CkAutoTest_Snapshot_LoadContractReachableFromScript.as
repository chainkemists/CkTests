// Language=angelscript

//============================================================================
// CK SNAPSHOT — AUTOMATION TEST: THE LOAD CONTRACT IS REACHABLE FROM SCRIPT
//============================================================================
//
// Every public API must work in C++, Blueprint AND AngelScript, and the
// save/load contract had a hole: the four calls a script-side consumer needs
// were either unreflected or simply never called from any .as in the tree, so
// nothing would have noticed if a binding stopped resolving.
//
//   Get_IsRebuildInProgress   the PRODUCER predicate — "may I seed?"
//   Get_IsReadyToResume       the poll form of "is this world the player's?"
//   Promise_OnHydrated        the per-entity push form — "my restored values are final"
//   Get_DidLoadComplete       the report predicate a consumer branches on
//
// This test deliberately runs OUTSIDE a load and pins the no-load-in-progress
// half of each contract, which is the half every consumer hits on a world that
// never loaded. It does not — and must not — drive a real load: a load travels
// the world, and every autotest in this map shares one PIE world.
//
// The load-bearing assertion is the last one. Get_DidLoadComplete is FALSE for
// a NoLoadInProgress report, so a consumer written against it cannot mistake
// "there was no load" for "the load completed" — which is exactly the class of
// bug a bare `Result == Success` comparison produces the other way round once a
// completed load is allowed to report losses.
//============================================================================

class UCk_AutoTest_Snapshot_LoadContractReachableFromScript : UCk_AutoTest_Base
{
    // Set while a Promise_* call is on the stack, so a delegate that fires from
    // inside it is distinguishable from one that fires a frame later. An
    // immediate promise that quietly became deferred would still pass a plain
    // fire-count assertion on the following frame.
    private bool _InsidePromiseCall = false;

    private int32 _HydratedFireCount = 0;
    private bool _HydratedFiredSynchronously = false;

    private int32 _LoadCompleteFireCount = 0;
    private bool _LoadCompleteFiredSynchronously = false;
    private bool _DidLoadCompleteAtFire = true;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto Self = InHandle;

        Assert_False(utils_snapshot::Get_IsRebuildInProgress(Self),
            "No load is rebuilding this world, so the producer predicate a construction-time seeder asks must "
            "answer false — a true here would suppress seeding forever");

        Assert_True(utils_snapshot::Get_IsReadyToResume(),
            "A world no load ever held IS the player's, so the poll form answers true — the never-loaded world "
            "is resolved by the contract, not by every consumer special-casing it");

        _InsidePromiseCall = true;
        utils_snapshot::Promise_OnHydrated(Self,
            FCk_Delegate_Hydration_OnHydrated(this, n"OnHydrated"));
        _InsidePromiseCall = false;

        Assert_Equals_Int(_HydratedFireCount, 1,
            "Promise_OnHydrated fires exactly once for an entity with nothing pending — a promise that stayed "
            "silent there would put every consumer back to polling a marker");
        Assert_True(_HydratedFiredSynchronously,
            "...and fires SYNCHRONOUSLY, from inside the call, because hydration is already as complete as it "
            "will ever be for this entity");

        _InsidePromiseCall = true;
        auto PromiseResult = utils_snapshot::Promise_OnLoadComplete(Self,
            FCk_Delegate_Snapshot_OnLoadComplete(this, n"OnLoadComplete"));
        _InsidePromiseCall = false;

        Assert_True(PromiseResult == ECk_Snapshot_PromiseResult::NoLoadInProgress,
            "The call RETURNS what it did, so a caller can branch without asking a second question — there was "
            "no load to wait for");

        Assert_Equals_Int(_LoadCompleteFireCount, 1,
            "Promise_OnLoadComplete fires exactly once outside a load");
        Assert_True(_LoadCompleteFiredSynchronously,
            "...synchronously, from inside the call");

        Assert_False(_DidLoadCompleteAtFire,
            "Get_DidLoadComplete is reachable from script AND answers FALSE for a NoLoadInProgress report: no "
            "load ran, so no load completed. It is the predicate a consumer branches on instead of comparing "
            "the result to Success");

        FinishSuccess();
    }

    UFUNCTION()
    private void OnHydrated(FCk_Handle InHandle)
    {
        _HydratedFireCount += 1;
        _HydratedFiredSynchronously = _InsidePromiseCall;
    }

    UFUNCTION()
    private void OnLoadComplete(FCk_Handle InHandle, FCk_Snapshot_LoadReport InReport)
    {
        _LoadCompleteFireCount += 1;
        _LoadCompleteFiredSynchronously = _InsidePromiseCall;
        _DidLoadCompleteAtFire = utils_snapshot::Get_DidLoadComplete(InReport);
    }
}
