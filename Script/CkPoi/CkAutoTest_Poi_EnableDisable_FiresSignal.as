// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: EnableDisable request fires signal + flips state
//============================================================================
//
// Request_EnableDisable(Disable) must flip Get_EnableDisable to Disable and
// fire OnPoiEnableDisable exactly once; re-enabling fires it again. Requests
// are deferred, so each mutation is followed by a WaitOneFrame settle.
//
// Isolated Y band: 52800.
//============================================================================

class UCk_AutoTest_Poi_EnableDisable_FiresSignal : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle_Poi _Poi;
    private int32 _SignalCount = 0;
    private ECk_EnableDisable _LastState = ECk_EnableDisable::Enable;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        auto LocalHandle = InHandle;

        auto Owner = utils_entity_lifetime::Request_CreateEntity(LocalHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, FVector(0.0, 52800.0, 0.0)),
            ECk_Replication::DoesNotReplicate);

        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Door");
        _Poi = utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(Category));

        _Poi.BindTo_OnEnableDisable(
            FCk_Delegate_Poi_EnableDisable(this, n"OnEnableDisable"));

        _Poi.Request_EnableDisable(FCk_Request_Poi_EnableDisable(ECk_EnableDisable::Disable));
        WaitOneFrame(n"OnSettled_AfterDisable");
    }

    UFUNCTION()
    private void OnEnableDisable(FCk_Handle_Poi InPoi, ECk_EnableDisable InNewState)
    {
        _SignalCount++;
        _LastState = InNewState;
    }

    UFUNCTION()
    private void OnSettled_AfterDisable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 1, "Disable should fire OnPoiEnableDisable once");
        Assert_True(_LastState == ECk_EnableDisable::Disable,
            "Signal payload should carry the new (Disabled) state");
        Assert_True(utils_poi::Get_EnableDisable(_Poi) == ECk_EnableDisable::Disable,
            "Get_EnableDisable should report Disable after the request settles");

        _Poi.Request_EnableDisable(FCk_Request_Poi_EnableDisable(ECk_EnableDisable::Enable));
        WaitOneFrame(n"OnSettled_AfterEnable");
    }

    UFUNCTION()
    private void OnSettled_AfterEnable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_SignalCount, 2, "Re-enable should fire OnPoiEnableDisable again");
        Assert_True(_LastState == ECk_EnableDisable::Enable,
            "Signal payload should carry the new (Enabled) state");
        Assert_True(utils_poi::Get_EnableDisable(_Poi) == ECk_EnableDisable::Enable,
            "Get_EnableDisable should report Enable after the request settles");

        FinishSuccess();
    }
}
