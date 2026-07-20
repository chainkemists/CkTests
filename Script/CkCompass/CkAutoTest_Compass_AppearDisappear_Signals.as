// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: entry appear/disappear membership signals
//============================================================================
//
// Membership deltas are the push contract: creating an in-range POI fires
// OnEntryAppeared exactly once; destroying its owner fires
// OnEntryDisappeared exactly once (no repeats while it stays).
//
// Isolated Y band: 59200.
//============================================================================

class UCk_AutoTest_Compass_AppearDisappear_Signals : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle _PoiOwner;
    private FCk_Handle_Poi _Poi;
    private FVector _Base = FVector(0.0, 59200.0, 0.0);

    private int32 _AppearedCount = 0;
    private int32 _DisappearedCount = 0;

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Compass_ParamsData();
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(0.0);

        _Compass.BindTo_OnEntryAppeared(
            FCk_Delegate_Compass_EntryAppeared(this, n"OnEntryAppeared"));
        _Compass.BindTo_OnEntryDisappeared(
            FCk_Delegate_Compass_EntryDisappeared(this, n"OnEntryDisappeared"));

        // Let the empty compass settle a couple of frames first.
        WaitOneFrame(n"OnSettled_Empty");
    }

    UFUNCTION()
    private void OnEntryAppeared(FCk_Handle_Compass InCompass, FCk_Compass_Entry InEntry)
    {
        _AppearedCount++;
    }

    UFUNCTION()
    private void OnEntryDisappeared(FCk_Handle_Compass InCompass, FCk_Handle_Poi InPoi)
    {
        _DisappearedCount++;
    }

    UFUNCTION()
    private void OnSettled_Empty(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AppearedCount, 0, "No signals before any POI exists");

        _PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(_PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 0.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(_PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestMembership")));

        WaitOneFrame(n"OnSettled_AfterCreate");
    }

    UFUNCTION()
    private void OnSettled_AfterCreate(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_AfterCreate2");
    }

    UFUNCTION()
    private void OnSettled_AfterCreate2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AppearedCount, 1, "Creating one in-range POI should fire Appeared exactly once");
        Assert_Equals_Int(_DisappearedCount, 0, "Nothing has disappeared yet");

        utils_entity_lifetime::Request_DestroyEntity(_PoiOwner);
        WaitOneFrame(n"OnSettled_AfterDestroy");
    }

    UFUNCTION()
    private void OnSettled_AfterDestroy(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_AfterDestroy2");
    }

    UFUNCTION()
    private void OnSettled_AfterDestroy2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_Equals_Int(_AppearedCount, 1, "Appeared must not re-fire for a stable entry");
        Assert_Equals_Int(_DisappearedCount, 1, "Destroying the POI owner should fire Disappeared exactly once");

        FinishSuccess();
    }
}
