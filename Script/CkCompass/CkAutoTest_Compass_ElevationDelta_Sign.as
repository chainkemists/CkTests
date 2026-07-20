// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: elevation delta sign (above/below arrows)
//============================================================================
//
// Two POIs 1000uu ahead: one 500uu ABOVE the observer, one 500uu BELOW.
// Entry _ElevationDelta must be ~+500 and ~-500 respectively (PoiZ minus
// ObserverZ) — the data UI uses for above/below indicators.
//
// Isolated Y band: 60000.
//============================================================================

class UCk_AutoTest_Compass_ElevationDelta_Sign : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Poi _Above;
    private FCk_Handle_Poi _Below;
    private FVector _Base = FVector(0.0, 60000.0, 200.0);

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

        _Above = DoSpawnPoi(FVector(1000.0, -100.0, 500.0), n"Poi.Category.TestAbove");
        _Below = DoSpawnPoi(FVector(1000.0, 100.0, -500.0), n"Poi.Category.TestBelow");

        WaitOneFrame(n"OnSettled_Requests");
    }

    private FCk_Handle_Poi DoSpawnPoi(FVector InOffset, FName InCategoryName)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);
        return utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(InCategoryName)));
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
        auto FoundAbove = false;
        auto FoundBelow = false;
        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Above)
            {
                FoundAbove = true;
                Assert_True(Math::Abs(Entry.Get_ElevationDelta() - 500.0) < 5.0,
                    f"POI 500 above should report ElevationDelta ~+500 (got {Entry.Get_ElevationDelta()})");
            }
            if (Entry.Get_Poi() == _Below)
            {
                FoundBelow = true;
                Assert_True(Math::Abs(Entry.Get_ElevationDelta() + 500.0) < 5.0,
                    f"POI 500 below should report ElevationDelta ~-500 (got {Entry.Get_ElevationDelta()})");
            }
        }
        Assert_True(FoundAbove && FoundBelow, "Both elevation POIs should be on the compass");

        FinishSuccess();
    }
}
