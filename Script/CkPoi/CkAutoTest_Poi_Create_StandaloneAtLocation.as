// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: standalone POI at a world location
//============================================================================
//
// The standalone-POI pattern (utils_poi::Create was removed): create an
// entity, add a Transform at the target world location, then Add the POI
// directly onto it. Position is verified observationally: a compass on an
// observer at the band origin (Manual heading 0) must project the POI at
// bearing ~0 / distance ~1000 (it was placed 1000uu along +X).
//
// NOTE: the class keeps its historical Create name (the AutoTests level has a
// placed runner actor referencing it by class path — renaming requires an
// editor level edit).
//
// Isolated Y band: 52400.
//============================================================================

class UCk_AutoTest_Poi_Create_StandaloneAtLocation : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Poi _Created;
    private FVector _Base = FVector(0.0, 52400.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        // Observer entity with a compass, Manual heading 0.
        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto CompassParams = FCk_Fragment_Compass_ParamsData();
        CompassParams.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, CompassParams);
        _Compass.Request_SetManualHeading(0.0);

        // Standalone POI 1000uu along +X from the observer: own entity + Transform + Poi.
        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark");
        auto Params = FCk_Fragment_Poi_ParamsData(Category);

        auto PoiHost = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        PoiHost.Request_OverrideToSelf();
        utils_transform::Add(PoiHost,
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 0.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Created = utils_poi::Add(PoiHost, Params);

        Assert_True(ck::IsValid(_Created),
            "utils_poi::Add should return a valid FCk_Handle_Poi");

        WaitOneFrame(n"OnSettled_Requests");
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
        auto Found = false;
        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Created)
            {
                Found = true;
                Assert_True(Math::Abs(Entry.Get_BearingDegrees()) < 0.5,
                    f"Created POI straight ahead should project at bearing ~0 (got {Entry.Get_BearingDegrees()})");
                Assert_True(Math::Abs(Entry.Get_Distance() - 1000.0) < 5.0,
                    f"Created POI should be ~1000uu away (got {Entry.Get_Distance()})");
            }
        }
        Assert_True(Found, "Created standalone POI should appear on the observer's compass");

        FinishSuccess();
    }
}
