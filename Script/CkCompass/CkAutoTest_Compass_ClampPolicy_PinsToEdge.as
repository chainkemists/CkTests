// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: ClampToEdge policy pins out-of-arc POIs
//============================================================================
//
// Arc 90 (half-arc 45). Two ClampToEdge POIs at bearings +60 and -60 (both
// outside the arc) must appear pinned at NormalizedOffset +1 / -1 with
// ArcState ClampedToEdge; a control POI at +10 sits inside the arc with
// ArcState InsideArc and offset ~ +10/45 = 0.222.
//
// Isolated Y band: 57200.
//============================================================================

class UCk_AutoTest_Compass_ClampPolicy_PinsToEdge : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 6.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle_Poi _RightClamped;
    private FCk_Handle_Poi _LeftClamped;
    private FCk_Handle_Poi _Inside;
    private FVector _Base = FVector(0.0, 57200.0, 0.0);

    UFUNCTION(BlueprintOverride)
    void DoBeginPlay(FCk_Handle InHandle)
    {
        auto _CkPerfScope = ck::ScopedStat();
        _SelfHandle = InHandle;

        auto Observer = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Observer.Request_OverrideToSelf();
        utils_transform::Add(Observer, FTransform(FRotator::ZeroRotator, _Base),
            ECk_Replication::DoesNotReplicate);

        auto Params = FCk_Fragment_Compass_ParamsData(90.0);
        Params.Set_HeadingSource(ECk_Compass_HeadingSource::Manual);
        _Compass = utils_compass::Add(Observer, Params);
        _Compass.Request_SetManualHeading(0.0);

        // +60 degrees: (cos60, sin60) * 1000 = (500, 866).
        _RightClamped = DoSpawnPoi(FVector(500.0, 866.0, 0.0), n"Poi.Category.TestClampRight",
            ECk_Poi_OffscreenPolicy::ClampToEdge);
        // -60 degrees: (500, -866).
        _LeftClamped = DoSpawnPoi(FVector(500.0, -866.0, 0.0), n"Poi.Category.TestClampLeft",
            ECk_Poi_OffscreenPolicy::ClampToEdge);
        // +10 degrees: (984.8, 173.6) — inside the 45-degree half-arc.
        _Inside = DoSpawnPoi(FVector(984.8, 173.6, 0.0), n"Poi.Category.TestInside",
            ECk_Poi_OffscreenPolicy::ClampToEdge);

        WaitOneFrame(n"OnSettled_Requests");
    }

    private FCk_Handle_Poi DoSpawnPoi(FVector InOffset, FName InCategoryName, ECk_Poi_OffscreenPolicy InPolicy)
    {
        auto Owner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        Owner.Request_OverrideToSelf();
        utils_transform::Add(Owner, FTransform(FRotator::ZeroRotator, _Base + InOffset),
            ECk_Replication::DoesNotReplicate);

        auto Poi = utils_poi::Add(Owner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(InCategoryName)));

        // Offscreen policy now lives in CkPoiDisplayDefinition, keyed by the compass consumer.
        auto DisplayParams = FCk_Fragment_PoiDisplayDefinition_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Consumer.Compass"));
        DisplayParams.Set_OffscreenPolicy(InPolicy);
        utils_poi_display_definition::Add(Poi, DisplayParams);

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
        Assert_Equals_Int(Entries.Num(), 3, "All three POIs should be present (clamped, not hidden)");

        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _RightClamped)
            {
                Assert_True(Entry.Get_ArcState() == ECk_Compass_EntryArcState::ClampedToEdge,
                    "POI at +60 with 45-degree half-arc should be ClampedToEdge");
                Assert_True(Math::Abs(Entry.Get_NormalizedOffset() - 1.0) < 0.01,
                    f"Right-clamped POI should pin at +1 (got {Entry.Get_NormalizedOffset()})");
            }
            else if (Entry.Get_Poi() == _LeftClamped)
            {
                Assert_True(Entry.Get_ArcState() == ECk_Compass_EntryArcState::ClampedToEdge,
                    "POI at -60 with 45-degree half-arc should be ClampedToEdge");
                Assert_True(Math::Abs(Entry.Get_NormalizedOffset() + 1.0) < 0.01,
                    f"Left-clamped POI should pin at -1 (got {Entry.Get_NormalizedOffset()})");
            }
            else if (Entry.Get_Poi() == _Inside)
            {
                Assert_True(Entry.Get_ArcState() == ECk_Compass_EntryArcState::InsideArc,
                    "POI at +10 should be InsideArc");
                Assert_True(Math::Abs(Entry.Get_NormalizedOffset() - 0.2222) < 0.01,
                    f"POI at +10 over half-arc 45 should sit at ~0.222 (got {Entry.Get_NormalizedOffset()})");
            }
        }

        FinishSuccess();
    }
}
