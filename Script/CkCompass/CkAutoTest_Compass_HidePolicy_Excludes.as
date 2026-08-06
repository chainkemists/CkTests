// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: Hide policy excludes out-of-arc POIs
//============================================================================
//
// Arc 90 (half-arc 45). A Hide-policy POI at bearing +60 must be ABSENT
// from the entries; a Hide-policy control POI at +10 (inside the arc) must
// be present.
//
// Isolated Y band: 57600.
//============================================================================

class UCk_AutoTest_Compass_HidePolicy_Excludes : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Poi _Outside;
    private FCk_Handle_Poi _Inside;
    private FVector _Base = FVector(0.0, 57600.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Compass_Spec(90.0);
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(0.0);

        // +60 degrees, Hide -> must not appear.
        _Outside = DoSpawnPoi(FVector(500.0, 866.0, 0.0), n"Poi.Category.TestHidden");
        // +10 degrees, Hide but inside the arc -> must appear.
        _Inside = DoSpawnPoi(FVector(984.8, 173.6, 0.0), n"Poi.Category.TestVisible");

        WaitUntil(n"Check_Projected", n"OnSettled_Projection");
    }

    private FCk_Handle_Poi DoSpawnPoi(FVector InOffset, FName InCategoryName)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);

        auto Poi = utils_poi::Add(Owner, FCk_Poi_Spec(
            utils_gameplay_tag::ResolveGameplayTag(InCategoryName)));

        // Offscreen policy now lives in CkPoiDisplayDefinition, keyed by the compass consumer.
        // Hide is also the default when no definition exists, but composed explicitly here.
        auto DisplayParams = FCk_PoiDisplayDefinition_Spec(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Compass"));
        DisplayParams.Set_OffscreenPolicy(ECk_Poi_OffscreenPolicy::Hide);
        utils_poi_display_definition::Add(Poi, DisplayParams);

        return Poi;
    }

    // Waits on THIS test's own POIs reaching the compass, never on a bare entry
    // count: autotests share one PIE world and a neighbouring band's POIs can
    // occupy the projection while this test's are still pending.
    UFUNCTION()
    private void Check_Projected(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        auto Found0 = false;

        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Inside) { Found0 = true; }
        }

        auto Res = OutResult;
        Res.Set(Found0);
    }

    UFUNCTION()
    private void OnSettled_Projection(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        auto FoundOutside = false;
        auto FoundInside = false;
        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Outside) { FoundOutside = true; }
            if (Entry.Get_Poi() == _Inside) { FoundInside = true; }
        }

        Assert_True(!FoundOutside, "Hide-policy POI outside the arc must be excluded from entries");
        Assert_True(FoundInside, "Hide-policy POI inside the arc must be present");
        Assert_Equals_Int(Entries.Num(), 1, "Exactly one POI should survive the Hide policy");

        FinishSuccess();
    }
}
