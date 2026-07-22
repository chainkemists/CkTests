// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: per-POI MaxVisibleRange culls by distance
//============================================================================
//
// Three POIs 1000uu ahead of the observer:
//   - range 500  -> beyond its own limit -> ABSENT
//   - range 0    -> unlimited            -> present
//   - range 1500 -> within its limit     -> present
//
// Isolated Y band: 58000.
//============================================================================

class UCk_AutoTest_Compass_RangeCull : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Poi _ShortRange;
    private FCk_Handle_Poi _Unlimited;
    private FCk_Handle_Poi _LongRange;
    private FVector _Base = FVector(0.0, 58000.0, 0.0);

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

        _ShortRange = DoSpawnPoi(FVector(1000.0, -100.0, 0.0), n"Poi.Category.TestShort", 500.0);
        _Unlimited = DoSpawnPoi(FVector(1000.0, 0.0, 0.0), n"Poi.Category.TestUnlimited", 0.0);
        _LongRange = DoSpawnPoi(FVector(1000.0, 100.0, 0.0), n"Poi.Category.TestLong", 1500.0);

        WaitOneFrame(n"OnSettled_Requests");
    }

    private FCk_Handle_Poi DoSpawnPoi(FVector InOffset, FName InCategoryName, float InRange)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);

        auto Poi = utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(InCategoryName)));

        // Range/fade config now lives in CkVisibleRange (composed onto the POI). MaxRange 0 =
        // unlimited. The compass reads this config and computes distance itself — no Update_Distance.
        utils_visible_range::Add(Owner, FCk_Fragment_VisibleRange_ParamsData(InRange));

        return Poi;
    }

    UFUNCTION()
    private void OnSettled_Requests(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Projection");
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        auto Entries = utils_compass::Get_Entries(_Compass);
        auto FoundShort = false;
        auto FoundUnlimited = false;
        auto FoundLong = false;
        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _ShortRange) { FoundShort = true; }
            if (Entry.Get_Poi() == _Unlimited) { FoundUnlimited = true; }
            if (Entry.Get_Poi() == _LongRange) { FoundLong = true; }
        }

        Assert_True(!FoundShort, "POI with MaxVisibleRange 500 at distance ~1000 must be culled");
        Assert_True(FoundUnlimited, "POI with MaxVisibleRange 0 (unlimited) must be present");
        Assert_True(FoundLong, "POI with MaxVisibleRange 1500 at distance ~1000 must be present");

        FinishSuccess();
    }
}
