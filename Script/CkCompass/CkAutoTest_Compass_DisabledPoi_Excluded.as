// Language=angelscript

//============================================================================
// CK COMPASS - AUTOMATION TEST: disabled POI is excluded, re-enable restores
//============================================================================
//
// CkPoi v2: disable is the Poi.Disabled CkEntityTag. An in-range POI
// disappears from entries after the tag is added (Add_UsingGameplayTag) and
// returns after it is removed (Request_TryRemove_UsingGameplayTag) - the
// projector skips entities carrying Poi.Disabled every update. Both mutations
// are deferred, so each is followed by a wait on the membership actually
// changing rather than on a fixed number of hops.
//
// Isolated Y band: 59600.
//============================================================================

class UCk_AutoTest_Compass_DisabledPoi_Excluded : UCk_AutoTest_Base
{
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

        Add_Step_WaitUntil("enabled in-range POI appears on the compass", n"Check_OnCompass");
        Add_Step(          "disable the POI",                            n"Step_Disable");
        Add_Step_WaitUntil("disabled POI leaves the compass",            n"Check_OffCompass");
        Add_Step(          "re-enable the POI",                          n"Step_Enable");
        Add_Step_WaitUntil("re-enabled POI returns to the compass",      n"Check_OnCompass");

        Run_Steps(InHandle);
    }

    //------------------------------------------------------------------------
    // Steps
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Step_Disable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_tag::Add_UsingGameplayTag(_PoiOwner, _DisabledTag);
    }

    UFUNCTION()
    private void Step_Enable(FCk_Handle InHandle, FInstancedStruct InPayload)
    {
        utils_entity_tag::Request_TryRemove_UsingGameplayTag(_PoiOwner, _DisabledTag);
    }

    //------------------------------------------------------------------------
    // Conditions
    //------------------------------------------------------------------------

    UFUNCTION()
    private void Check_OnCompass(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoIsOnCompass());
    }

    UFUNCTION()
    private void Check_OffCompass(FCk_Handle InHandle, FCk_SharedBool OutResult, FInstancedStruct InPayload)
    {
        auto Res = OutResult;
        Res.Set(DoIsOnCompass() == false);
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

}
