// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: Created POI with TTL expires
//============================================================================
//
// utils_poi::Create with a TTL composes a countdown timer that destroys the
// POI when done (the ping primitive). The handle must be valid immediately
// after Create and become invalid within the timeout after the TTL elapses.
//
// TTL destruction is the poi's own lifecycle — nothing to Track_ForCleanup
// on the success path; the tracked fallback below only matters if the test
// fails (so a leaked ping can't poison later tests).
//
// Isolated Y band: 52600.
//============================================================================

class UCk_AutoTest_Poi_Create_TtlExpires : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle_Poi _Ping;
    private float _Elapsed = 0.0;
    private bool _WasValidInitially = false;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Ping");
        auto Params = FCk_Fragment_Poi_ParamsData(Category);

        _Ping = utils_poi::Create(ck::TransientEntity(),
            FTransform(FRotator::ZeroRotator, FVector(0.0, 52600.0, 0.0)), Params, FCk_Time(0.4));

        _WasValidInitially = ck::IsValid(_Ping);
        Assert_True(_WasValidInitially,
            "Create with TTL should return a valid handle before expiry");
        Track_ForCleanup(FCk_Handle(_Ping));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTick(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        _Elapsed += float(InDeltaT.Get_Seconds());

        if (ck::Is_NOT_Valid(_Ping))
        {
            Assert_True(_WasValidInitially, "Ping must have been valid before expiring");
            Assert_True(_Elapsed >= 0.3,
                f"Ping should live for roughly its TTL before expiring (expired at {_Elapsed}s)");
            FinishSuccess();
            return;
        }

        if (_Elapsed > 6.0)
        {
            FinishFailure(f"TTL ping never expired (still valid after {_Elapsed}s)");
        }
    }
}
