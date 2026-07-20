// Language=angelscript

//============================================================================
// CK POI — AUTOMATION TEST: Create standalone POI at a world location
//============================================================================
//
// utils_poi::Create spawns a standalone transform-only host + POI at the
// given world transform. Position is verified observationally: a compass on
// an observer at the band origin (Manual heading 0) must project the created
// POI at bearing ~0 / distance ~1000 (it was placed 1000uu along +X).
//
// The created host is owned by the world's TransientEntity (not this runner),
// so the POI is registered via Track_ForCleanup. NOTE: cleanup destroys the
// tracked handle's entity; the transform-only host it hangs under is inert.
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

        // Standalone POI 1000uu along +X from the observer.
        auto Category = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.Landmark");
        auto Params = FCk_Fragment_Poi_ParamsData(Category);
        _Created = utils_poi::Create(ck::TransientEntity(),
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 0.0, 0.0)), Params, FCk_Time());

        Assert_True(ck::IsValid(_Created),
            "utils_poi::Create should return a valid FCk_Handle_Poi");
        Track_ForCleanup(FCk_Handle(_Created));

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
