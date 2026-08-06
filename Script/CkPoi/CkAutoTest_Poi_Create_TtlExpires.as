// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: composed TTL ping expires
//============================================================================
//
// The ping pattern (utils_poi::Create with TTL was removed): compose the POI
// directly onto its own entity and pair it with a CkTimer whose OnDone
// destroys the host entity. The handle must be valid immediately after
// composition and become invalid within the timeout after the TTL elapses.
//
// NOTE: the class keeps its historical Create name (the AutoTests level has a
// placed runner actor referencing it by class path — renaming requires an
// editor level edit).
//
// Isolated Y band: 52600.
//============================================================================

class UCk_AutoTest_Poi_Create_TtlExpires : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _PingHost;
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

        _PingHost = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        _PingHost.Request_OverrideToSelf();
        utils_transform::Add(_PingHost, FTransform(FRotator::ZeroRotator, FVector(0.0, 52600.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Ping = utils_poi::Add(_PingHost, Params);

        auto TtlParams = FCk_Timer_Spec(FCk_Time(0.4f));
        TtlParams.Set_Behavior(ECk_Timer_Behavior::StopOnDone).Set_StartingState(ECk_Timer_State::Running);
        auto TtlTimer = utils_timer::Add(_PingHost, TtlParams);
        TtlTimer.BindTo_OnDone(FCk_Delegate_Timer(this, n"OnTtlDone"));

        _WasValidInitially = ck::IsValid(_Ping);
        Assert_True(_WasValidInitially,
            "A composed TTL ping should have a valid handle before expiry");
        Track_ForCleanup(FCk_Handle(_Ping));

        utils_timer::Create_Tick(LocalHandle, FCk_Delegate_Timer(this, n"OnTick"));
    }

    UFUNCTION()
    private void OnTtlDone(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (ck::Is_NOT_Valid(_PingHost)) { return; }
        utils_entity_lifetime::Request_DestroyEntity(_PingHost);
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
