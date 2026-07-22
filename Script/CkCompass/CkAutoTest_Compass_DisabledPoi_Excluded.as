// Language=angelscript

//============================================================================
// CK COMPASS — AUTOMATION TEST: disabled POI is excluded, re-enable restores
//============================================================================
//
// CkPoi v2: disable is the Poi.Disabled CkEntityTag. An in-range POI
// disappears from entries after the tag is added (Add_UsingGameplayTag) and
// returns after it is removed (Request_TryRemove_UsingGameplayTag) — the
// projector skips entities carrying Poi.Disabled every update. Both mutations
// are deferred one pump, so each is followed by a settle frame.
//
// Isolated Y band: 59600.
//============================================================================

class UCk_AutoTest_Compass_DisabledPoi_Excluded : UCk_AutoTest_Base
{
    default _TimeoutSeconds = 8.0f;

    private FCk_Handle _SelfHandle;
    private FCk_Handle_Compass _Compass;
    private FCk_Handle _PoiOwner;
    private FCk_Handle_Poi _Poi;
    private FGameplayTag _DisabledTag;
    private FVector _Base = FVector(0.0, 59600.0, 0.0);

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

        _PoiOwner = utils_entity_lifetime::Request_CreateEntity(_SelfHandle);
        _PoiOwner.Request_OverrideToSelf();
        utils_transform::Add(_PoiOwner,
            FTransform(FRotator::ZeroRotator, _Base + FVector(1000.0, 0.0, 0.0)),
            ECk_Replication::DoesNotReplicate);
        _Poi = utils_poi::Add(_PoiOwner, FCk_Fragment_Poi_ParamsData(
            utils_gameplay_tag::ResolveGameplayTag(n"Poi.Category.TestToggle")));

        _DisabledTag = utils_gameplay_tag::ResolveGameplayTag(n"Poi.Disabled");

        WaitOneFrame(n"OnSettled_Initial");
    }

    private bool DoIsOnCompass()
    {
        auto Entries = utils_compass::Get_Entries(_Compass);
        for (auto Entry : Entries)
        {
            if (Entry.Get_Poi() == _Poi) { return true; }
        }
        return false;
    }

    UFUNCTION()
    private void OnSettled_Initial(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_Initial2");
    }

    UFUNCTION()
    private void OnSettled_Initial2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(DoIsOnCompass(), "Enabled in-range POI should be on the compass");

        utils_entity_tag::Add_UsingGameplayTag(_PoiOwner, _DisabledTag);
        WaitOneFrame(n"OnSettled_AfterDisable");
    }

    UFUNCTION()
    private void OnSettled_AfterDisable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_AfterDisable2");
    }

    UFUNCTION()
    private void OnSettled_AfterDisable2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(!DoIsOnCompass(), "Disabled POI must be excluded from compass entries");

        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_PoiOwner, _DisabledTag);
        WaitOneFrame(n"OnSettled_AfterEnable");
    }

    UFUNCTION()
    private void OnSettled_AfterEnable(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }
        WaitOneFrame(n"OnSettled_AfterEnable2");
    }

    UFUNCTION()
    private void OnSettled_AfterEnable2(FCk_Handle_Timer InTimer, FCk_Chrono InChrono, FCk_Time InDeltaT)
    {
        if (IsFinished()) { return; }

        Assert_True(DoIsOnCompass(), "Re-enabled POI should return to compass entries");
        FinishSuccess();
    }
}
